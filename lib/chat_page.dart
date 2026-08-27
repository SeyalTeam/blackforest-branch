import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_server_prefs.dart';
import 'common_scaffold.dart';

const Duration _chatPollInterval = Duration(seconds: 15);
const Color _whatsAppGreen = Color(0xFF25D366);
const Color _whatsAppDarkGreen = Color(0xFF075E54);
const Color _whatsAppOutgoingBubble = Color(0xFFD9FDD3);
const Color _whatsAppWallpaperBase = Color(0xFFEDE3D1);
const Color _whatsAppWallpaperIcon = Color(0xFFB6A88F);

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  static final ValueNotifier<int> unreadChatNotifier = ValueNotifier<int>(0);

  static void setUnreadChatCount(int count) {
    unreadChatNotifier.value = count;
    CommonScaffold.setUnreadChatCount(count);
  }

  static Future<int> checkUnreadChatCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token')?.trim();
      if (token == null || token.isEmpty) return 0;

      final receiptsRes = await http.get(
        _apiUri(
          '/api/message-receipts',
          queryParameters: {
            'limit': '500',
            'depth': '0',
            'where[recipientAudience][equals]': 'staff',
            'where[status][not_equals]': 'read',
          },
        ),
        headers: _authHeaders(token),
      );

      if (receiptsRes.statusCode == 200) {
        final data = _decodeResponse(receiptsRes);
        final count =
            data?['totalDocs'] as int? ?? (data?['docs'] as List?)?.length ?? 0;
        setUnreadChatCount(count);
        return count;
      }
    } catch (e) {
      debugPrint('Error checking unread chat messages in branch: ' + e.toString());
    }
    return 0;
  }

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _CurrentChatUser? _currentUser;
  _MessageThreadSummary? _thread;
  List<_ChatMessage> _messages = const [];
  List<_ChatMessage> _optimisticMessages = const [];
  Map<String, _MessageReceiptSummary> _outgoingReceiptsByMessageId = const {};

  Timer? _pollTimer;
  bool _isBootstrapping = true;
  bool _isRefreshing = false;
  bool _bootstrapInFlight = false;
  bool _conversationLoadInFlight = false;
  String _draftText = '';
  String? _loadError;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    ChatPage.setUnreadChatCount(0);
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(_handleDraftChanged);
    _startPolling();
    _bootstrapConversation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _messageController.removeListener(_handleDraftChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshConversation(showLoader: false));
    }
  }

  bool get _isChatVisible =>
      mounted && _appLifecycleState == AppLifecycleState.resumed;

  bool get _hasDraftText => _draftText.trim().isNotEmpty;

  void _handleDraftChanged() {
    final nextDraft = _messageController.text;
    if (nextDraft == _draftText) return;
    if (!mounted) return;
    setState(() {
      _draftText = nextDraft;
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_chatPollInterval, (_) {
      unawaited(_refreshConversation(showLoader: false));
    });
  }

  Future<void> _bootstrapConversation({bool showLoader = true}) async {
    if (_bootstrapInFlight) return;
    _bootstrapInFlight = true;

    if (mounted) {
      setState(() {
        if (showLoader) {
          _isBootstrapping = true;
        }
        _loadError = null;
      });
    }

    try {
      final currentUser = await _loadCurrentUser();
      if (!mounted) return;

      setState(() {
        _currentUser = currentUser;
        if (!currentUser.isEmployeeLinked) {
          _thread = null;
          _messages = const [];
          _optimisticMessages = const [];
          _outgoingReceiptsByMessageId = const {};
        }
      });

      if (!currentUser.isEmployeeLinked) {
        return;
      }

      await _refreshConversation(showLoader: false, forceScrollToBottom: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _normalizeError(error);
        _thread = null;
        _messages = const [];
        _optimisticMessages = const [];
        _outgoingReceiptsByMessageId = const {};
      });
    } finally {
      _bootstrapInFlight = false;
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
        });
      }
    }
  }

  Future<_MessageThreadSummary?> _fetchOrCreateThread({
    required String token,
    required String currentUserId,
  }) async {
    _MessageThreadSummary? thread = await _fetchThreadByStaffUser(token, currentUserId);
    if (thread != null) return thread;

    try {
      final createRes = await http.post(
        _apiUri('/api/message-threads'),
        headers: _authHeaders(token, json: true),
        body: jsonEncode({
          'staffUser': currentUserId,
          'status': 'open',
        }),
      );
      if (createRes.statusCode == 200 || createRes.statusCode == 201) {
        final data = _decodeResponse(createRes);
        thread = _MessageThreadSummary.fromJson(data?['doc'] ?? data);
        if (thread != null) return thread;
      }
    } catch (e) {
      debugPrint('Error creating message thread: ' + e.toString());
    }

    return await _fetchThreadByStaffUser(token, currentUserId);
  }

  Future<void> _refreshConversation({
    bool showLoader = true,
    bool forceScrollToBottom = false,
    bool showRefreshIndicator = false,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) {
      await _bootstrapConversation(showLoader: showLoader);
      return;
    }

    if (!currentUser.isEmployeeLinked) {
      return;
    }

    if (_conversationLoadInFlight) return;
    _conversationLoadInFlight = true;

    final previousMessageCount = _messages.length;
    final wasNearBottom = _isNearBottom();

    if (mounted) {
      setState(() {
        if (showLoader && _messages.isEmpty) {
          _isBootstrapping = true;
        }
        if (showRefreshIndicator) {
          _isRefreshing = true;
        }
        _loadError = null;
      });
    }

    try {
      final token = await _readToken();
      final thread = await _fetchOrCreateThread(
        token: token,
        currentUserId: currentUser.id,
      );

      if (thread == null) {
        if (!mounted) return;
        setState(() {
          _thread = null;
          _messages = const [];
          _optimisticMessages = const [];
          _outgoingReceiptsByMessageId = const {};
        });
        return;
      }

      final responses = await Future.wait([
        http.get(
          _apiUri(
            '/api/messages',
            queryParameters: {
              'limit': '500',
              'depth': '0',
              'sort': 'seq',
              'where[thread][equals]': thread.id,
            },
          ),
          headers: _authHeaders(token),
        ),
        http.get(
          _apiUri(
            '/api/message-receipts',
            queryParameters: {
              'limit': '500',
              'depth': '0',
              'where[thread][equals]': thread.id,
            },
          ),
          headers: _authHeaders(token),
        ),
      ]);

      final messageResponse = responses[0];
      final receiptResponse = responses[1];

      if (messageResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(
            messageResponse,
            'Unable to load conversation messages.',
          ),
        );
      }

      if (receiptResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(receiptResponse, 'Unable to load message receipts.'),
        );
      }

      final messageDocs =
          (_decodeResponse(messageResponse)?['docs'] as List?) ?? const [];
      final receiptDocs =
          (_decodeResponse(receiptResponse)?['docs'] as List?) ?? const [];

      final messages =
          messageDocs
              .map(_ChatMessage.fromJson)
              .whereType<_ChatMessage>()
              .toList(growable: false);

      final outgoingReceiptsByMessageId = <String, _MessageReceiptSummary>{};
      final staffReceiptsByMessageId = <String, _MessageReceiptSummary>{};

      for (final doc in receiptDocs) {
        final receipt = _MessageReceiptSummary.fromJson(doc);
        if (receipt == null) continue;

        final targetMap = receipt.recipientAudience == 'staff'
            ? staffReceiptsByMessageId
            : outgoingReceiptsByMessageId;
        final existing = targetMap[receipt.messageId];
        if (existing == null || receipt.rank > existing.rank) {
          targetMap[receipt.messageId] = receipt;
        }
      }

      if (!mounted) return;
      setState(() {
        _thread = thread;
        _messages = messages;
        _outgoingReceiptsByMessageId = outgoingReceiptsByMessageId;
      });

      final shouldScroll =
          forceScrollToBottom ||
          previousMessageCount == 0 ||
          (messages.length > previousMessageCount && wasNearBottom);
      if (shouldScroll) {
        _scrollToBottom();
      }

      unawaited(
        _applyIncomingReceiptUpdates(
          token: token,
          messages: messages,
          receiptsByMessageId: staffReceiptsByMessageId,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _normalizeError(error);
      });
    } finally {
      _conversationLoadInFlight = false;
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
          if (showRefreshIndicator) {
            _isRefreshing = false;
          }
        });
      }
    }
  }

  Future<void> _applyIncomingReceiptUpdates({
    required String token,
    required List<_ChatMessage> messages,
    required Map<String, _MessageReceiptSummary> receiptsByMessageId,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null) return;

    for (final message in messages) {
      if (message.isFromAdmin) {
        final receipt = receiptsByMessageId[message.id];
        if (receipt == null) continue;

        if (_isChatVisible) {
          if (receipt.status != 'read') {
            unawaited(
              _patchReceiptStatus(
                token: token,
                receipt: receipt,
                status: 'read',
              ),
            );
          }
        } else if (receipt.status == 'sent') {
          unawaited(
            _patchReceiptStatus(
              token: token,
              receipt: receipt,
              status: 'delivered',
            ),
          );
        }
      }
    }
  }

  Future<_MessageReceiptSummary?> _patchReceiptStatus({
    required String token,
    required _MessageReceiptSummary receipt,
    required String status,
  }) async {
    if (receipt.status == status) {
      return receipt;
    }

    try {
      final response = await http.patch(
        _apiUri('/api/message-receipts/' + receipt.id),
        headers: _authHeaders(token, json: true),
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          'Chat receipt update failed for ' + receipt.id + ': ' + response.statusCode.toString(),
        );
        return null;
      }

      return _MessageReceiptSummary.fromJson(_decodeResponse(response)) ??
          receipt.copyWith(status: status);
    } catch (error) {
      debugPrint('Chat receipt update error for ' + receipt.id + ': ' + error.toString());
      return null;
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final maxOffset = _scrollController.position.maxScrollExtent;
    return (maxOffset - _scrollController.offset) < 120;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  int _nextOptimisticSeq() {
    int maxSeq = 0;
    for (final message in _messages) {
      if (message.seq > maxSeq) {
        maxSeq = message.seq;
      }
    }
    for (final message in _optimisticMessages) {
      if (message.seq > maxSeq) {
        maxSeq = message.seq;
      }
    }
    return maxSeq + 1;
  }

  void _addOptimisticMessage({
    required _ChatMessage message,
    required _MessageReceiptSummary receipt,
  }) {
    setState(() {
      _optimisticMessages = List<_ChatMessage>.from(_optimisticMessages)
        ..add(message);
      _outgoingReceiptsByMessageId = Map<String, _MessageReceiptSummary>.from(
        _outgoingReceiptsByMessageId,
      )..[message.id] = receipt;
    });
    _scrollToBottom();
  }

  void _removeOptimisticMessage(String localId) {
    setState(() {
      _optimisticMessages = _optimisticMessages
          .where((m) => m.id != localId)
          .toList();
      final updatedReceipts = Map<String, _MessageReceiptSummary>.from(
        _outgoingReceiptsByMessageId,
      );
      updatedReceipts.remove(localId);
      _outgoingReceiptsByMessageId = updatedReceipts;
    });
  }

  void _replaceOptimisticMessage({
    required String localId,
    required _ChatMessage serverMessage,
  }) {
    setState(() {
      _optimisticMessages = _optimisticMessages
          .where((m) => m.id != localId)
          .toList();
      final updatedMessages = List<_ChatMessage>.from(_messages);
      final existingIndex = updatedMessages.indexWhere(
        (m) => m.id == serverMessage.id,
      );
      if (existingIndex >= 0) {
        updatedMessages[existingIndex] = serverMessage;
      } else {
        updatedMessages.add(serverMessage);
      }
      updatedMessages.sort((a, b) {
        final seqCompare = a.seq.compareTo(b.seq);
        if (seqCompare != 0) return seqCompare;
        return a.createdAt.compareTo(b.createdAt);
      });
      _messages = updatedMessages;

      final updatedReceipts = Map<String, _MessageReceiptSummary>.from(
        _outgoingReceiptsByMessageId,
      );
      final optimisticReceipt = updatedReceipts.remove(localId);
      if (optimisticReceipt != null) {
        updatedReceipts[serverMessage.id] = optimisticReceipt.copyWith(
          id: serverMessage.id,
          messageId: serverMessage.id,
        );
      }
      _outgoingReceiptsByMessageId = updatedReceipts;
    });
    _scrollToBottom();
  }

  List<_ChatMessage> _displayMessages() {
    final allMessages = <_ChatMessage>[..._messages, ..._optimisticMessages];
    allMessages.sort((a, b) {
      final seqCompare = a.seq.compareTo(b.seq);
      if (seqCompare != 0) return seqCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
    return allMessages;
  }

  Future<void> _sendMessage() async {
    final currentUser = _currentUser;
    final text = _messageController.text.trim();

    if (currentUser == null || text.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();
    _messageController.clear();

    final token = await _readToken();
    var thread = _thread;

    if (thread == null) {
      thread = await _fetchOrCreateThread(
        token: token,
        currentUserId: currentUser.id,
      );
      if (thread != null && mounted) {
        setState(() {
          _thread = thread;
        });
      }
    }

    if (thread == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to initialize chat conversation. Please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final threadId = thread.id;
    final localSeq = _nextOptimisticSeq();
    final localId = 'local-' + DateTime.now().microsecondsSinceEpoch.toString() + '-' + localSeq.toString();
    final optimisticMessage = _ChatMessage(
      id: localId,
      threadId: threadId,
      senderUserId: currentUser.id,
      senderRole: 'staff',
      text: text,
      seq: localSeq,
      createdAt: DateTime.now(),
    );
    final optimisticReceipt = _MessageReceiptSummary(
      id: localId,
      messageId: localId,
      recipientAudience: 'admins',
      status: 'sent',
    );
    _addOptimisticMessage(
      message: optimisticMessage,
      receipt: optimisticReceipt,
    );

    try {
      final response = await http.post(
        _apiUri('/api/messages'),
        headers: _authHeaders(token, json: true),
        body: jsonEncode({'thread': thread.id, 'text': text}),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          _responseMessage(response, 'Unable to send the message.'),
        );
      }

      final createdMessage = _ChatMessage.fromJson(_decodeResponse(response));
      if (createdMessage != null) {
        _replaceOptimisticMessage(
          localId: localId,
          serverMessage: createdMessage,
        );
        unawaited(
          _refreshConversation(showLoader: false, forceScrollToBottom: true),
        );
      } else {
        _removeOptimisticMessage(localId);
        await _refreshConversation(
          showLoader: false,
          forceScrollToBottom: true,
        );
      }
    } catch (error) {
      _removeOptimisticMessage(localId);
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = text;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_normalizeError(error)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _currentUser;
    final displayMessages = _displayMessages();

    return Scaffold(
      backgroundColor: _whatsAppWallpaperBase,
      appBar: AppBar(
        backgroundColor: _whatsAppDarkGreen,
        foregroundColor: Colors.white,
        elevation: 1,
        titleSpacing: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Row(
          children: [
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF128C7E),
              ),
              alignment: Alignment.center,
              child: const Text(
                'AD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Management • Online',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD4EBE7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh chat',
            onPressed: () => _refreshConversation(showLoader: true, forceScrollToBottom: true),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: const _WhatsAppWallpaperPainter(),
              ),
            ),
            Column(
              children: [
                if (_isRefreshing)
                  const LinearProgressIndicator(
                    minHeight: 2.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(_whatsAppGreen),
                  ),
                Expanded(
                  child: _buildChatBody(currentUser, displayMessages),
                ),
                _buildInputBar(currentUser),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBody(
    _CurrentChatUser? currentUser,
    List<_ChatMessage> displayMessages,
  ) {
    if (_isBootstrapping && displayMessages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _whatsAppDarkGreen),
      );
    }

    if (currentUser != null && !currentUser.isEmployeeLinked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off_rounded, size: 52, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'Employee Profile Not Linked',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your user account must be linked to an employee profile before chat can be used.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadError != null && displayMessages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _whatsAppDarkGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                onPressed: () => _bootstrapConversation(showLoader: true),
              ),
            ],
          ),
        ),
      );
    }

    if (displayMessages.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 44, color: _whatsAppDarkGreen),
              SizedBox(height: 10),
              Text(
                'Direct Admin Communication',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Send a message to reach management directly.\nMessages will appear in real time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      itemCount: displayMessages.length,
      itemBuilder: (context, index) {
        final message = displayMessages[index];
        final isOutgoing = !message.isFromAdmin;
        final receipt = isOutgoing ? _outgoingReceiptsByMessageId[message.id] : null;

        final showDateChip = index == 0 ||
            !_isSameCalendarDay(
              displayMessages[index - 1].createdAt,
              message.createdAt,
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateChip) ...[
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    _formatDateChip(message.createdAt),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF54656F),
                    ),
                  ),
                ),
              ),
            ],
            Align(
              alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isOutgoing ? _whatsAppOutgoingBubble : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: isOutgoing ? const Radius.circular(12) : Radius.zero,
                    bottomRight: isOutgoing ? Radius.zero : const Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isOutgoing) ...[
                      const Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _whatsAppDarkGreen,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      message.text,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: Color(0xFF111B21),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Spacer(),
                        Text(
                          DateFormat('hh:mm a').format(message.createdAt.toLocal()),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF667781),
                          ),
                        ),
                        if (isOutgoing) ...[
                          const SizedBox(width: 4),
                          _buildReceiptStatusIcon(receipt?.status),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReceiptStatusIcon(String? status) {
    if (status == 'read') {
      return const Icon(Icons.done_all_rounded, size: 16, color: Color(0xFF53BDEB));
    }
    if (status == 'delivered') {
      return const Icon(Icons.done_all_rounded, size: 16, color: Color(0xFF8696A0));
    }
    return const Icon(Icons.done_rounded, size: 16, color: Color(0xFF8696A0));
  }

  Widget _buildInputBar(_CurrentChatUser? currentUser) {
    final bool canSend = currentUser?.isEmployeeLinked == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: canSend,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 15),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: _hasDraftText ? _whatsAppGreen : _whatsAppDarkGreen,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: canSend && _hasDraftText ? _sendMessage : null,
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentChatUser {
  final String id;
  final String? employeeId;
  final String displayName;
  final String role;

  const _CurrentChatUser({
    required this.id,
    required this.employeeId,
    required this.displayName,
    required this.role,
  });

  bool get isEmployeeLinked => employeeId != null && employeeId!.isNotEmpty;
}

class _MessageThreadSummary {
  final String id;
  final String staffUserId;
  final String status;
  final String? participantName;
  final DateTime? lastMessageAt;

  const _MessageThreadSummary({
    required this.id,
    required this.staffUserId,
    required this.status,
    required this.participantName,
    required this.lastMessageAt,
  });

  static _MessageThreadSummary? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final id = _relationshipId(json);
    final staffUserId = _relationshipId(json['staffUser']);
    if (id == null || staffUserId == null) return null;

    return _MessageThreadSummary(
      id: id,
      staffUserId: staffUserId,
      status: _stringValue(json['status']) ?? 'open',
      participantName: _stringValue(json['participantName']),
      lastMessageAt: _parseDate(json['lastMessageAt']),
    );
  }
}

class _ChatMessage {
  final String id;
  final String threadId;
  final String? senderUserId;
  final String senderRole;
  final String text;
  final int seq;
  final DateTime createdAt;

  const _ChatMessage({
    required this.id,
    required this.threadId,
    this.senderUserId,
    required this.senderRole,
    required this.text,
    required this.seq,
    required this.createdAt,
  });

  bool get isFromAdmin => senderRole == 'admin' || senderRole == 'superadmin';

  static _ChatMessage? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final id = _relationshipId(json);
    final threadId = _relationshipId(json['thread']);
    final senderUserId = _relationshipId(json['senderUser']);
    final createdAt = _parseDate(json['createdAt']);
    final text = _stringValue(json['text']);
    final seq = _intValue(json['seq']) ?? 0;

    if (id == null || threadId == null || createdAt == null || text == null) {
      return null;
    }

    return _ChatMessage(
      id: id,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: _stringValue(json['senderRole']) ?? '',
      text: text,
      seq: seq,
      createdAt: createdAt,
    );
  }
}

class _MessageReceiptSummary {
  static const int deliveredRank = 1;
  static const int readRank = 2;

  final String id;
  final String messageId;
  final String? recipientAudience;
  final String status;

  const _MessageReceiptSummary({
    required this.id,
    required this.messageId,
    required this.recipientAudience,
    required this.status,
  });

  int get rank {
    switch (status) {
      case 'read':
        return readRank;
      case 'delivered':
        return deliveredRank;
      default:
        return 0;
    }
  }

  _MessageReceiptSummary copyWith({
    String? id,
    String? messageId,
    String? recipientAudience,
    String? status,
  }) {
    return _MessageReceiptSummary(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      recipientAudience: recipientAudience ?? this.recipientAudience,
      status: status ?? this.status,
    );
  }

  static _MessageReceiptSummary? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final id = _relationshipId(json);
    final messageId = _relationshipId(json['message']);
    if (id == null || messageId == null) return null;

    return _MessageReceiptSummary(
      id: id,
      messageId: messageId,
      recipientAudience: _stringValue(json['recipientAudience']),
      status: _stringValue(json['status']) ?? 'sent',
    );
  }
}

class _WhatsAppWallpaperPainter extends CustomPainter {
  const _WhatsAppWallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = _whatsAppWallpaperBase;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final iconPaint = Paint()
      ..color = _whatsAppWallpaperIcon.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const double step = 64.0;
    for (double y = 16; y < size.height; y += step) {
      for (double x = 16; x < size.width; x += step) {
        final double pattern = ((x / step).floor() + (y / step).floor()) % 4;
        final center = Offset(x, y);

        if (pattern == 0) {
          canvas.drawCircle(center, 9, iconPaint);
        } else if (pattern == 1) {
          final rect = Rect.fromCenter(center: center, width: 14, height: 14);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            iconPaint,
          );
        } else if (pattern == 2) {
          final path = Path()
            ..moveTo(center.dx - 8, center.dy + 7)
            ..lineTo(center.dx, center.dy - 8)
            ..lineTo(center.dx + 8, center.dy + 7)
            ..close();
          canvas.drawPath(path, iconPaint);
        } else {
          canvas.drawLine(
            Offset(center.dx - 7, center.dy),
            Offset(center.dx + 7, center.dy),
            iconPaint,
          );
          canvas.drawLine(
            Offset(center.dx, center.dy - 7),
            Offset(center.dx, center.dy + 7),
            iconPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<String> _readToken() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token')?.trim();
  if (token == null || token.isEmpty) {
    throw Exception('Session expired. Please login again.');
  }
  return token;
}

Future<_CurrentChatUser> _loadCurrentUser() async {
  final token = await _readToken();
  final response = await http.get(
    _apiUri('/api/users/me'),
    headers: _authHeaders(token),
  );

  if (response.statusCode != 200) {
    throw Exception(_responseMessage(response, 'Unable to load user profile.'));
  }

  final decoded = _decodeResponse(response);
  final userJson = decoded?['user'];
  if (userJson is! Map<String, dynamic>) {
    throw Exception('Malformed user profile response.');
  }

  final id = _relationshipId(userJson);
  if (id == null) {
    throw Exception('Missing user id in profile.');
  }

  final employeeId = _relationshipId(userJson['employee']);
  final displayName = _stringValue(userJson['name']) ??
      _stringValue(userJson['username']) ??
      _stringValue(userJson['email']) ??
      'Staff';
  final role = _stringValue(userJson['role']) ?? 'staff';

  return _CurrentChatUser(
    id: id,
    employeeId: employeeId,
    displayName: displayName,
    role: role,
  );
}

Future<_MessageThreadSummary?> _fetchThreadByStaffUser(
  String token,
  String staffUserId,
) async {
  final response = await http.get(
    _apiUri(
      '/api/message-threads',
      queryParameters: {
        'limit': '1',
        'depth': '0',
        'where[staffUser][equals]': staffUserId,
      },
    ),
    headers: _authHeaders(token),
  );

  if (response.statusCode != 200) {
    return null;
  }

  final docs = (_decodeResponse(response)?['docs'] as List?) ?? const [];
  if (docs.isEmpty) return null;
  return _MessageThreadSummary.fromJson(docs.first);
}

Uri _apiUri(String path, {Map<String, String>? queryParameters}) {
  final cleanPath = path.startsWith('/') ? path : '/' + path;
  return Uri.https(apiHostPrimary, cleanPath, queryParameters);
}

Map<String, String> _authHeaders(String token, {bool json = false}) {
  return {
    'Authorization': 'Bearer ' + token,
    if (json) 'Content-Type': 'application/json',
  };
}

Map<String, dynamic>? _decodeResponse(http.Response response) {
  final rawBody = utf8.decode(response.bodyBytes);
  if (rawBody.trim().isEmpty) return null;

  try {
    final decoded = jsonDecode(rawBody);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String _responseMessage(http.Response response, String fallback) {
  final decoded = _decodeResponse(response);
  if (decoded == null) return fallback + ' (' + response.statusCode.toString() + ')';

  final directMessage = _stringValue(decoded['message']);
  if (directMessage != null && directMessage.isNotEmpty) {
    return directMessage;
  }

  final errors = decoded['errors'];
  if (errors is List && errors.isNotEmpty) {
    for (final error in errors) {
      if (error is Map<String, dynamic>) {
        final message = _stringValue(error['message']);
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    }
  }

  return fallback + ' (' + response.statusCode.toString() + ')';
}

String _normalizeError(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

String? _relationshipId(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }

  if (value is Map<String, dynamic>) {
    final id = value['id'] ?? value['_id'];
    if (id is String && id.trim().isNotEmpty) {
      return id;
    }
  }

  return null;
}

String? _stringValue(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

DateTime? _parseDate(dynamic value) {
  final stringValue = _stringValue(value);
  if (stringValue == null) return null;
  return DateTime.tryParse(stringValue);
}

String _formatDateChip(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final current = DateTime(local.year, local.month, local.day);
  final difference = current.difference(today).inDays;

  if (difference == 0) return 'Today';
  if (difference == -1) return 'Yesterday';
  if (difference >= -6 && difference <= 6) {
    return DateFormat('EEEE').format(local);
  }
  return DateFormat('d MMMM yyyy').format(local);
}

bool _isSameCalendarDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}
