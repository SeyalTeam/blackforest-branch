import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:branch/api_config.dart';
import 'package:branch/common_scaffold.dart';
import 'package:branch/home.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration _chatPollInterval = Duration(seconds: 20);
const Color _whatsAppGreen = Color(0xFF25D366);
const Color _whatsAppHeaderShadow = Color(0x14000000);
const Color _whatsAppOutgoingBubble = Color(0xFFD9FDD3);
const Color _whatsAppWallpaperBase = Color(0xFFEDE3D1);
const Color _whatsAppWallpaperIcon = Color(0xFFB6A88F);

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonScaffold(
      title: 'Chat',
      pageType: PageType.chat,
      showAppBar: false,
      hideBottomNavigationBar: true,
      body: _EmployeeChatScreen(),
    );
  }
}

class _EmployeeChatScreen extends StatefulWidget {
  const _EmployeeChatScreen();

  @override
  State<_EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<_EmployeeChatScreen>
    with WidgetsBindingObserver {
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

  String get _chatTitle {
    final participantName = _thread?.participantName?.trim();
    final currentName = _currentUser?.displayName.trim();
    if (participantName != null &&
        participantName.isNotEmpty &&
        participantName != currentName) {
      return participantName;
    }
    return 'Admin';
  }

  String get _avatarLetters {
    final parts = _chatTitle
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) {
      return parts.first.characters.take(1).toString().toUpperCase();
    }
    return '${parts[0].characters.take(1)}${parts[1].characters.take(1)}'
        .toUpperCase();
  }

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
      final thread = await _fetchThreadByStaffUser(token, currentUser.id);

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

      final messagesResponse = responses[0];
      final receiptsResponse = responses[1];

      if (messagesResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(messagesResponse, 'Unable to load messages.'),
        );
      }

      if (receiptsResponse.statusCode != 200) {
        throw Exception(
          _responseMessage(
            receiptsResponse,
            'Unable to load message receipts.',
          ),
        );
      }

      final messageDocs =
          (_decodeResponse(messagesResponse)?['docs'] as List?) ?? const [];
      final receiptDocs =
          (_decodeResponse(receiptsResponse)?['docs'] as List?) ?? const [];

      final messages = <_ChatMessage>[];
      for (final doc in messageDocs) {
        final message = _ChatMessage.fromJson(doc);
        if (message != null) {
          messages.add(message);
        }
      }
      messages.sort((a, b) {
        final seqCompare = a.seq.compareTo(b.seq);
        if (seqCompare != 0) return seqCompare;
        return a.createdAt.compareTo(b.createdAt);
      });

      final Map<String, _MessageReceiptSummary> staffReceiptsByMessageId = {};
      final Map<String, _MessageReceiptSummary> outgoingReceiptsByMessageId =
          {};
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

  Future<_CurrentChatUser> _loadCurrentUser() async {
    final token = await _readToken();
    final response = await http.get(
      _apiUri(
        '/api/users/me',
        queryParameters: {'depth': '5', 'showHiddenFields': 'true'},
      ),
      headers: _authHeaders(token),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(response, 'Unable to load the current user.'),
      );
    }

    final decoded = _decodeResponse(response);
    final dynamic rawUser = decoded?['user'] ?? decoded;
    if (rawUser is! Map<String, dynamic>) {
      throw Exception('Unable to read the current user profile.');
    }

    final userId = _relationshipId(rawUser);
    if (userId == null) {
      throw Exception('Current user profile is missing an id.');
    }

    return _CurrentChatUser(
      id: userId,
      employeeId: _relationshipId(rawUser['employee']),
      displayName:
          _stringValue(rawUser['name']) ??
          _stringValue(rawUser['username']) ??
          _stringValue(rawUser['email']) ??
          'You',
    );
  }

  Future<_MessageThreadSummary?> _fetchThreadByStaffUser(
    String token,
    String currentUserId,
  ) async {
    final response = await http.get(
      _apiUri(
        '/api/message-threads',
        queryParameters: {
          'limit': '1',
          'depth': '0',
          'where[staffUser][equals]': currentUserId,
        },
      ),
      headers: _authHeaders(token),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _responseMessage(response, 'Unable to look up the chat thread.'),
      );
    }

    final docs = (_decodeResponse(response)?['docs'] as List?) ?? const [];
    if (docs.isEmpty) return null;

    final thread = _MessageThreadSummary.fromJson(docs.first);
    if (thread == null) {
      throw Exception('Unable to parse the chat thread.');
    }

    return thread;
  }

  Future<Map<String, _MessageReceiptSummary>> _applyIncomingReceiptUpdates({
    required String token,
    required List<_ChatMessage> messages,
    required Map<String, _MessageReceiptSummary> receiptsByMessageId,
  }) async {
    if (messages.isEmpty || receiptsByMessageId.isEmpty) {
      return receiptsByMessageId;
    }

    final updatedReceipts = Map<String, _MessageReceiptSummary>.from(
      receiptsByMessageId,
    );
    final shouldMarkRead = _isChatVisible;

    for (final message in messages) {
      if (!message.isFromAdmin) continue;

      var receipt = updatedReceipts[message.id];
      if (receipt == null) continue;

      if (receipt.rank < _MessageReceiptSummary.deliveredRank) {
        final deliveredReceipt = await _patchReceiptStatus(
          token: token,
          receipt: receipt,
          status: 'delivered',
        );
        if (deliveredReceipt != null) {
          receipt = deliveredReceipt;
          updatedReceipts[message.id] = deliveredReceipt;
        }
      }

      if (!shouldMarkRead) {
        continue;
      }

      if (receipt.rank < _MessageReceiptSummary.deliveredRank) {
        continue;
      }

      if (receipt.rank < _MessageReceiptSummary.readRank) {
        final readReceipt = await _patchReceiptStatus(
          token: token,
          receipt: receipt,
          status: 'read',
        );
        if (readReceipt != null) {
          updatedReceipts[message.id] = readReceipt;
        }
      }
    }

    return updatedReceipts;
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
        _apiUri('/api/message-receipts/${receipt.id}'),
        headers: _authHeaders(token, json: true),
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          'Chat receipt update failed for ${receipt.id}: ${response.statusCode}',
        );
        return null;
      }

      return _MessageReceiptSummary.fromJson(_decodeResponse(response)) ??
          receipt.copyWith(status: status);
    } catch (error) {
      debugPrint('Chat receipt update error for ${receipt.id}: $error');
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
    if (!mounted) return;
    setState(() {
      _optimisticMessages = _optimisticMessages
          .where((message) => message.id != localId)
          .toList(growable: false);
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
    if (!mounted) return;
    setState(() {
      _optimisticMessages = _optimisticMessages
          .where((message) => message.id != localId)
          .toList(growable: false);

      final updatedMessages = List<_ChatMessage>.from(_messages)
        ..removeWhere((message) => message.id == serverMessage.id)
        ..add(serverMessage);
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
    final thread = _thread;
    final text = _messageController.text.trim();

    if (thread == null || text.isEmpty || thread.status != 'open') {
      return;
    }

    FocusScope.of(context).unfocus();
    _messageController.clear();

    final localSeq = _nextOptimisticSeq();
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}-$localSeq';
    final optimisticMessage = _ChatMessage(
      id: localId,
      threadId: thread.id,
      senderRole: 'staff',
      text: text,
      seq: localSeq,
      createdAt: DateTime.now(),
    );
    final optimisticReceipt = _MessageReceiptSummary(
      id: localId,
      messageId: localId,
      recipientAudience: 'admin',
      status: 'sent',
    );
    _addOptimisticMessage(
      message: optimisticMessage,
      receipt: optimisticReceipt,
    );

    try {
      final token = await _readToken();
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

  Future<void> _handleBack() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }

  void _showPhaseOneMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _handleMenuAction(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.refresh:
        await _refreshConversation(
          showLoader: false,
          forceScrollToBottom: true,
          showRefreshIndicator: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          _WhatsAppChatAppBar(
            title: _chatTitle,
            avatarLetters: _avatarLetters,
            isRefreshing: _isRefreshing,
            onBack: _handleBack,
            onCallTap: () => _showPhaseOneMessage(
              'Voice calling is not part of chat phase 1.',
            ),
            onMenuSelected: _handleMenuAction,
          ),
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: _WhatsAppWallpaper()),
                Positioned.fill(
                  child: Column(
                    children: [
                      Expanded(child: _buildConversationBody()),
                      if (thread != null)
                        _Composer(
                          controller: _messageController,
                          isEnabled: thread.status == 'open',
                          hasText: _hasDraftText,
                          onSend: () => unawaited(_sendMessage()),
                          onCameraTap: () => _showPhaseOneMessage(
                            'Camera sharing is not part of chat phase 1.',
                          ),
                          onMicTap: () => _showPhaseOneMessage(
                            'Voice messages are not part of chat phase 1.',
                          ),
                          disabledMessage: thread.status == 'open'
                              ? null
                              : 'This chat is currently closed.',
                        ),
                    ],
                  ),
                ),
                if (_loadError != null && _messages.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: _InfoBanner(message: _loadError!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationBody() {
    final currentUser = _currentUser;
    final displayMessages = _displayMessages();

    if (_isBootstrapping && displayMessages.isEmpty && _thread == null) {
      return const Center(
        child: CircularProgressIndicator(color: _whatsAppGreen),
      );
    }

    if (_loadError != null && displayMessages.isEmpty) {
      return _CenteredStatus(
        title: _loadError!,
        subtitle: 'Pull down or use the menu to retry.',
        actionLabel: 'Retry',
        onAction: () => _bootstrapConversation(showLoader: false),
      );
    }

    if (currentUser != null && !currentUser.isEmployeeLinked) {
      return const _CenteredStatus(
        title: 'Chat is not available for this account.',
        subtitle:
            'Only logged-in employee-linked users can use the employee chat.',
      );
    }

    if (_thread == null) {
      return _CenteredStatus(
        title: 'No messages yet',
        subtitle:
            'An admin needs to start the conversation first. This screen checks every 20 seconds while the app is open.',
        actionLabel: 'Refresh',
        onAction: () => _bootstrapConversation(showLoader: false),
      );
    }

    if (displayMessages.isEmpty) {
      return _CenteredStatus(
        title: 'No messages yet',
        subtitle: 'Messages in this thread will appear here.',
        actionLabel: 'Refresh',
        onAction: () => _refreshConversation(showLoader: false),
      );
    }

    return RefreshIndicator(
      color: _whatsAppGreen,
      onRefresh: () => _refreshConversation(showLoader: false),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
        itemCount: displayMessages.length,
        itemBuilder: (context, index) {
          final message = displayMessages[index];
          final previous = index > 0 ? displayMessages[index - 1] : null;
          final showDateChip =
              previous == null ||
              !_isSameCalendarDay(previous.createdAt, message.createdAt);

          return Column(
            children: [
              if (showDateChip) ...[
                _DateChip(date: message.createdAt),
                const SizedBox(height: 10),
              ],
              _MessageBubble(
                message: message,
                receipt: _outgoingReceiptsByMessageId[message.id],
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

enum _ChatMenuAction { refresh }

class _WhatsAppChatAppBar extends StatelessWidget {
  final String title;
  final String avatarLetters;
  final bool isRefreshing;
  final Future<void> Function() onBack;
  final VoidCallback onCallTap;
  final Future<void> Function(_ChatMenuAction action) onMenuSelected;

  const _WhatsAppChatAppBar({
    required this.title,
    required this.avatarLetters,
    required this.isRefreshing,
    required this.onBack,
    required this.onCallTap,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: _whatsAppHeaderShadow,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F0F12), Color(0xFF7A1530)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  avatarLetters,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (isRefreshing) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _whatsAppGreen,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onCallTap,
                icon: const Icon(Icons.call_outlined, color: Colors.black87),
              ),
              PopupMenuButton<_ChatMenuAction>(
                icon: const Icon(Icons.more_vert, color: Colors.black87),
                onSelected: (action) => unawaited(onMenuSelected(action)),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ChatMenuAction.refresh,
                    child: Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatsAppWallpaper extends StatelessWidget {
  const _WhatsAppWallpaper();

  static const List<IconData> _icons = <IconData>[
    Icons.local_pizza_outlined,
    Icons.cake_outlined,
    Icons.local_cafe_outlined,
    Icons.fastfood_outlined,
    Icons.icecream_outlined,
    Icons.restaurant_outlined,
    Icons.bakery_dining_outlined,
    Icons.emoji_food_beverage_outlined,
    Icons.lunch_dining_outlined,
    Icons.ramen_dining_outlined,
    Icons.receipt_long_outlined,
    Icons.shopping_bag_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _whatsAppWallpaperBase,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.18,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = math.max(4, (constraints.maxWidth / 68).ceil());
              final rows = math.max(8, (constraints.maxHeight / 68).ceil() + 2);
              final total = columns * rows;

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(total, (index) {
                  final icon = _icons[index % _icons.length];
                  final angle = ((index % 7) - 3) * 0.18;
                  final size = 20.0 + (index % 4) * 3.0;

                  return SizedBox(
                    width: 60,
                    height: 56,
                    child: Center(
                      child: Transform.rotate(
                        angle: angle,
                        child: Icon(
                          icon,
                          size: size,
                          color: _whatsAppWallpaperIcon.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const _CenteredStatus({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15171A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF5F6368),
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: _whatsAppGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;

  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFF8A6D00)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6E5A00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool isEnabled;
  final bool hasText;
  final VoidCallback onSend;
  final VoidCallback onCameraTap;
  final VoidCallback onMicTap;
  final String? disabledMessage;

  const _Composer({
    required this.controller,
    required this.isEnabled,
    required this.hasText,
    required this.onSend,
    required this.onCameraTap,
    required this.onMicTap,
    this.disabledMessage,
  });

  @override
  Widget build(BuildContext context) {
    final bool showSend = hasText;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (disabledMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      disabledMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5F6368),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            enabled: isEnabled,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                color: Color(0xFF7A7F85),
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                18,
                                14,
                                12,
                                14,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Camera',
                          onPressed: onCameraTap,
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            color: Color(0xFF606468),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _whatsAppGreen,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      onPressed: isEnabled
                          ? (showSend ? onSend : onMicTap)
                          : null,
                      icon: Icon(
                        showSend ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          _formatDateChip(date),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF5F6368),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final _MessageReceiptSummary? receipt;

  const _MessageBubble({required this.message, required this.receipt});

  @override
  Widget build(BuildContext context) {
    final bool isOutgoing = !message.isFromAdmin;
    final Color bubbleColor = isOutgoing
        ? _whatsAppOutgoingBubble
        : Colors.white;
    const messageStyle = TextStyle(
      fontSize: 16,
      height: 1.32,
      color: Colors.black87,
    );
    const timeStyle = TextStyle(fontSize: 12, color: Color(0xFF667781));
    const double horizontalPadding = 12;
    const double inlineGap = 10;
    const double iconGap = 4;
    const double statusIconWidth = 17;
    final String timeText = DateFormat(
      'HH:mm',
    ).format(message.createdAt.toLocal());

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxBubbleWidth = math.min(
            MediaQuery.of(context).size.width * 0.80,
            constraints.maxWidth,
          );
          final double contentMaxWidth = math.max(
            0,
            maxBubbleWidth - (horizontalPadding * 2),
          );
          final double metaWidth =
              _measureTextWidth(
                context: context,
                text: timeText,
                style: timeStyle,
              ) +
              (isOutgoing ? iconGap + statusIconWidth : 0);

          final textPainter = TextPainter(
            text: TextSpan(text: message.text, style: messageStyle),
            textDirection: Directionality.of(context),
          )..layout(maxWidth: contentMaxWidth);

          final bool isMultiLine = textPainter.computeLineMetrics().length > 1;
          final bool showTimeInline =
              !isMultiLine &&
              (textPainter.width + inlineGap + metaWidth) <= contentMaxWidth;
          final double resolvedBubbleWidth = showTimeInline
              ? math.min(
                  maxBubbleWidth,
                  (textPainter.width + inlineGap + metaWidth) +
                      (horizontalPadding * 2),
                )
              : maxBubbleWidth;

          return SizedBox(
            width: resolvedBubbleWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isOutgoing ? 12 : 4),
                  bottomRight: Radius.circular(isOutgoing ? 4 : 12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: showTimeInline
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(message.text, style: messageStyle),
                          ),
                          const SizedBox(width: inlineGap),
                          _MessageMeta(
                            timeText: timeText,
                            isOutgoing: isOutgoing,
                            status: receipt?.status,
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message.text, style: messageStyle),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _MessageMeta(
                              timeText: timeText,
                              isOutgoing: isOutgoing,
                              status: receipt?.status,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final String timeText;
  final bool isOutgoing;
  final String? status;

  const _MessageMeta({
    required this.timeText,
    required this.isOutgoing,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final bool showDelivered = status == 'delivered' || status == 'read';
    final bool showRead = status == 'read';
    final IconData tickIcon = showDelivered
        ? Icons.done_all_rounded
        : Icons.done_rounded;
    final Color tickColor = showRead
        ? const Color(0xFF53BDEB)
        : const Color(0xFF8C979F);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          timeText,
          style: const TextStyle(fontSize: 12, color: Color(0xFF667781)),
        ),
        if (isOutgoing) ...[
          const SizedBox(width: 4),
          Icon(tickIcon, size: 17, color: tickColor),
        ],
      ],
    );
  }
}

class _CurrentChatUser {
  final String id;
  final String? employeeId;
  final String displayName;

  const _CurrentChatUser({
    required this.id,
    required this.employeeId,
    required this.displayName,
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
  final String senderRole;
  final String text;
  final int seq;
  final DateTime createdAt;

  const _ChatMessage({
    required this.id,
    required this.threadId,
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
    final createdAt = _parseDate(json['createdAt']);
    final text = _stringValue(json['text']);
    final seq = _intValue(json['seq']) ?? 0;

    if (id == null || threadId == null || createdAt == null || text == null) {
      return null;
    }

    return _ChatMessage(
      id: id,
      threadId: threadId,
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
    final recipientAudience = _stringValue(json['recipientAudience']);
    final status = _stringValue(json['status']);
    if (id == null || messageId == null || status == null) return null;

    return _MessageReceiptSummary(
      id: id,
      messageId: messageId,
      recipientAudience: recipientAudience,
      status: status,
    );
  }
}

Future<String> _readToken() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token')?.trim();
  if (token == null || token.isEmpty) {
    throw Exception('Session expired. Please login again.');
  }
  return token;
}

Uri _apiUri(String path, {Map<String, String>? queryParameters}) {
  final base = Uri.parse(ApiConfig.domain);
  return Uri(
    scheme: base.scheme.isNotEmpty ? base.scheme : 'https',
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: path,
    queryParameters: queryParameters,
  );
}

Map<String, String> _authHeaders(String token, {bool json = false}) {
  return {
    'Authorization': 'Bearer $token',
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
  if (decoded == null) return '$fallback (${response.statusCode})';

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

  return '$fallback (${response.statusCode})';
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

double _measureTextWidth({
  required BuildContext context,
  required String text,
  required TextStyle style,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  return painter.width;
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
