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
const Color _whatsAppDarkGreen = Color(0xFF075E54);
const Color _whatsAppHeaderShadow = Color(0x14000000);
const Color _whatsAppOutgoingBubble = Color(0xFFD9FDD3);
const Color _whatsAppWallpaperBase = Color(0xFFEDE3D1);
const Color _whatsAppWallpaperIcon = Color(0xFFB6A88F);

class ChatContact {
  final String id;
  final String name;
  final String role;
  final String? email;
  final String? photoUrl;
  final bool isAdmin;
  final String? staffUserId;

  const ChatContact({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.photoUrl,
    this.isAdmin = false,
    this.staffUserId,
  });

  static const admin = ChatContact(
    id: 'admin',
    name: 'Admin',
    role: 'Management',
    isAdmin: true,
  );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return isAdmin ? 'AD' : 'EM';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts[0].characters.take(1)}${parts[1].characters.take(1)}'.toUpperCase();
  }

  Color get roleColor {
    final r = role.toLowerCase();
    if (r.contains('admin')) return const Color(0xFF7A1530);
    if (r.contains('chef')) return const Color(0xFFD97706);
    if (r.contains('driver') || r.contains('delivery')) return const Color(0xFF2563EB);
    if (r.contains('cashier')) return const Color(0xFF059669);
    if (r.contains('manager')) return const Color(0xFF7C3AED);
    if (r.contains('supervisor')) return const Color(0xFF0D9488);
    if (r.contains('waiter')) return const Color(0xFFDB2777);
    if (r.contains('store')) return const Color(0xFFEA580C);
    if (r.contains('kitchen')) return const Color(0xFFC026D3);
    return const Color(0xFF4B5563);
  }
}

class _ConversationItem {
  final ChatContact contact;
  final _ChatMessage? lastMessage;
  final int unreadCount;

  const _ConversationItem({
    required this.contact,
    this.lastMessage,
    this.unreadCount = 0,
  });
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  List<ChatContact> _allContacts = const [];
  List<_ChatMessage> _allMessages = const [];
  List<_ConversationItem> _conversationItems = const [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchOpen = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _loadInboxData();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInboxData(showLoader: false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_chatPollInterval, (_) {
      _loadInboxData(showLoader: false);
    });
  }

  Future<void> _loadInboxData({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final token = await _readToken();
      final responses = await Future.wait([
        http.get(
          _apiUri(
            '/api/employees',
            queryParameters: {'limit': '200', 'depth': '1', 'sort': 'name'},
          ),
          headers: _authHeaders(token),
        ),
        http.get(
          _apiUri(
            '/api/users',
            queryParameters: {'limit': '200', 'depth': '1', 'sort': 'name'},
          ),
          headers: _authHeaders(token),
        ),
        http.get(
          _apiUri(
            '/api/messages',
            queryParameters: {'limit': '500', 'depth': '0', 'sort': '-createdAt'},
          ),
          headers: _authHeaders(token),
        ),
      ]);

      final employeesRes = responses[0];
      final usersRes = responses[1];
      final messagesRes = responses[2];

      final Map<String, dynamic> staffUsersByEmployeeId = {};
      final Map<String, dynamic> staffUsersById = {};

      if (usersRes.statusCode == 200) {
        final decoded = _decodeResponse(usersRes);
        final docs = (decoded?['docs'] as List?) ?? [];
        for (final doc in docs) {
          if (doc is Map<String, dynamic>) {
            final uid = (doc['id'] ?? doc['_id'])?.toString();
            final empId = _relationshipId(doc['employee']);
            if (uid != null) {
              staffUsersById[uid] = doc;
            }
            if (empId != null) {
              staffUsersByEmployeeId[empId] = doc;
            }
          }
        }
      }

      final List<ChatContact> contacts = [];

      if (employeesRes.statusCode == 200) {
        final decoded = _decodeResponse(employeesRes);
        final docs = (decoded?['docs'] as List?) ?? [];
        for (final doc in docs) {
          if (doc is Map<String, dynamic>) {
            final id = (doc['id'] ?? doc['_id'])?.toString() ?? '';
            final name = (doc['name'] ?? '').toString().trim();
            final role = (doc['team'] ?? doc['role'] ?? 'Staff').toString().trim();
            final email = (doc['email'] ?? '').toString().trim();

            final matchingUser = staffUsersByEmployeeId[id];
            final staffUid = matchingUser != null
                ? (matchingUser['id'] ?? matchingUser['_id'])?.toString()
                : null;

            if (name.isNotEmpty) {
              contacts.add(
                ChatContact(
                  id: id,
                  name: name,
                  role: role.isEmpty ? 'Staff' : role,
                  email: email.isNotEmpty ? email : null,
                  staffUserId: staffUid,
                ),
              );
            }
          }
        }
      }

      if (contacts.isEmpty && staffUsersById.isNotEmpty) {
        for (final entry in staffUsersById.entries) {
          final doc = entry.value;
          final name = (doc['name'] ?? doc['username'] ?? '').toString().trim();
          final role = (doc['role'] ?? 'Staff').toString().trim();
          if (name.isNotEmpty &&
              role.toLowerCase() != 'admin' &&
              role.toLowerCase() != 'superadmin') {
            contacts.add(
              ChatContact(
                id: entry.key,
                name: name,
                role: role,
                staffUserId: entry.key,
              ),
            );
          }
        }
      }

      contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      List<_ChatMessage> messages = [];
      if (messagesRes.statusCode == 200) {
        final decoded = _decodeResponse(messagesRes);
        final docs = (decoded?['docs'] as List?) ?? [];
        messages = docs
            .map(_ChatMessage.fromJson)
            .whereType<_ChatMessage>()
            .toList(growable: false);
      }

      // Group messages by contact
      final Map<String, _ChatMessage> latestMessageByContact = {};

      for (final msg in messages) {
        final text = msg.text;
        // Check if message is tagged with a recipient [@Name • Role]
        if (text.startsWith('[@') && text.contains(']')) {
          final endIdx = text.indexOf(']');
          final tag = text.substring(2, endIdx).toLowerCase();
          for (final c in contacts) {
            if (tag.contains(c.name.toLowerCase()) ||
                tag.contains(c.role.toLowerCase())) {
              if (!latestMessageByContact.containsKey(c.id)) {
                latestMessageByContact[c.id] = msg;
              }
              break;
            }
          }
        } else {
          // Untagged message belongs to Admin conversation
          if (!latestMessageByContact.containsKey('admin')) {
            latestMessageByContact['admin'] = msg;
          }
        }
      }

      // Build conversations list
      final List<_ConversationItem> conversations = [];

      // Always include Admin
      conversations.add(
        _ConversationItem(
          contact: ChatContact.admin,
          lastMessage: latestMessageByContact['admin'],
        ),
      );

      // Add contacts that have message history
      for (final c in contacts) {
        if (latestMessageByContact.containsKey(c.id)) {
          conversations.add(
            _ConversationItem(
              contact: c,
              lastMessage: latestMessageByContact[c.id],
            ),
          );
        }
      }

      // Sort conversations: latest message first!
      conversations.sort((a, b) {
        final aTime = a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _allContacts = contacts;
          _allMessages = messages;
          _conversationItems = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading chat inbox in branch: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openChatWithContact(ChatContact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EmployeeChatScreen(
          contact: contact,
          allContacts: _allContacts,
        ),
      ),
    ).then((_) {
      _loadInboxData(showLoader: false);
      CommonScaffold.checkUnreadChatCount();
    });
  }

  void _openContactsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmployeeContactsSheet(
        contacts: _allContacts,
        activeContact: ChatContact.admin,
        onSelectContact: (contact) {
          Navigator.of(ctx).pop();
          _openChatWithContact(contact);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _conversationItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.contact.name.toLowerCase().contains(_searchQuery) ||
          item.contact.role.toLowerCase().contains(_searchQuery) ||
          (item.lastMessage?.text.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();

    return CommonScaffold(
      title: 'Chat',
      pageType: PageType.chat,
      showAppBar: false,
      hideBottomNavigationBar: false,
      body: Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: FloatingActionButton(
          onPressed: _openContactsModal,
          backgroundColor: _whatsAppGreen,
          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
        ),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          shadowColor: _whatsAppHeaderShadow,
          automaticallyImplyLeading: false,
          title: _isSearchOpen
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search chats...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : const Text(
                  'Chats',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          actions: [
            IconButton(
              icon: Icon(
                _isSearchOpen ? Icons.close : Icons.search,
                color: const Color(0xFF374151),
              ),
              onPressed: () {
                setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF374151)),
              onPressed: () => _loadInboxData(),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: _whatsAppGreen),
              )
            : RefreshIndicator(
                color: _whatsAppGreen,
                onRefresh: () => _loadInboxData(showLoader: false),
                child: filteredConversations.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF3F4F6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No chats yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap the chat button below to start messaging Admin or any team member.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: filteredConversations.length,
                        separatorBuilder: (context, index) => const Divider(
                          indent: 76,
                          height: 1,
                          color: Color(0xFFF1F5F9),
                        ),
                        itemBuilder: (context, index) {
                          final item = filteredConversations[index];
                          final contact = item.contact;
                          final lastMsg = item.lastMessage;

                          String previewText = 'Tap to open chat';
                          String timeText = '';
                          bool isOutgoing = false;

                          if (lastMsg != null) {
                            isOutgoing = !lastMsg.isFromAdmin;
                            String text = lastMsg.text;
                            if (text.startsWith('[@') && text.contains(']\n')) {
                              text = text.substring(text.indexOf(']\n') + 2);
                            } else if (text.startsWith('[@') && text.contains(']: ')) {
                              text = text.substring(text.indexOf(']: ') + 3);
                            }
                            previewText = text.trim();
                            timeText = _formatInboxTime(lastMsg.createdAt);
                          }

                          return InkWell(
                            onTap: () => _openChatWithContact(contact),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          contact.roleColor,
                                          contact.roleColor.withValues(alpha: 0.8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: contact.roleColor.withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: contact.isAdmin
                                        ? const Icon(
                                            Icons.admin_panel_settings_rounded,
                                            color: Colors.white,
                                            size: 26,
                                          )
                                        : Text(
                                            contact.initials,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      contact.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w700,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: contact.roleColor
                                                          .withValues(alpha: 0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      contact.role.toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w700,
                                                        color: contact.roleColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (timeText.isNotEmpty)
                                              Text(
                                                timeText,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (lastMsg != null && isOutgoing) ...[
                                              const Icon(
                                                Icons.done_all_rounded,
                                                size: 16,
                                                color: Color(0xFF53BDEB),
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            Expanded(
                                              child: Text(
                                                previewText,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: lastMsg != null
                                                      ? const Color(0xFF64748B)
                                                      : Colors.grey.shade400,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

class _EmployeeChatScreen extends StatefulWidget {
  final ChatContact contact;
  final List<ChatContact> allContacts;

  const _EmployeeChatScreen({
    required this.contact,
    this.allContacts = const [],
  });

  @override
  State<_EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<_EmployeeChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _CurrentChatUser? _currentUser;
  late ChatContact _activeContact;
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
    _activeContact = widget.contact;
    CommonScaffold.setUnreadChatCount(0);
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
    if (!_activeContact.isAdmin) {
      return _activeContact.name;
    }
    final participantName = _thread?.participantName?.trim();
    final currentName = _currentUser?.displayName.trim();
    if (participantName != null &&
        participantName.isNotEmpty &&
        participantName != currentName) {
      return participantName;
    }
    return 'Admin';
  }

  String get _chatSubtitle {
    if (!_activeContact.isAdmin) {
      return _activeContact.role.toUpperCase();
    }
    return 'Management • Online';
  }

  String get _avatarLetters {
    return _activeContact.initials;
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

  Future<_MessageThreadSummary?> _fetchOrCreateThread({
    required String token,
    required String targetUserId,
    required String currentUserId,
  }) async {
    // 1. Try finding thread for target user
    _MessageThreadSummary? thread = await _fetchThreadByStaffUser(token, targetUserId);
    if (thread != null) return thread;

    // 2. Try finding thread for current user
    if (targetUserId != currentUserId) {
      thread = await _fetchThreadByStaffUser(token, currentUserId);
      if (thread != null) return thread;
    }

    // 3. Try creating thread for current user
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
      debugPrint('Error creating message thread: $e');
    }

    // 4. Fallback to any available thread
    try {
      final listRes = await http.get(
        _apiUri('/api/message-threads', queryParameters: {'limit': '1', 'depth': '0'}),
        headers: _authHeaders(token),
      );
      if (listRes.statusCode == 200) {
        final docs = (_decodeResponse(listRes)?['docs'] as List?) ?? const [];
        if (docs.isNotEmpty) {
          thread = _MessageThreadSummary.fromJson(docs.first);
          if (thread != null) return thread;
        }
      }
    } catch (e) {
      debugPrint('Error fetching fallback thread: $e');
    }

    return thread;
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
      final targetUserId = _activeContact.isAdmin
          ? currentUser.id
          : (_activeContact.staffUserId ?? currentUser.id);

      final thread = await _fetchOrCreateThread(
        token: token,
        targetUserId: targetUserId,
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
          'Staff',
    );
  }

  Future<_MessageThreadSummary?> _fetchThreadByStaffUser(
    String token,
    String currentUserId,
  ) async {
    try {
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
        return null;
      }

      final docs = (_decodeResponse(response)?['docs'] as List?) ?? const [];
      if (docs.isEmpty) return null;

      return _MessageThreadSummary.fromJson(docs.first);
    } catch (_) {
      return null;
    }
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
          CommonScaffold.setUnreadChatCount(0);
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

    if (_activeContact.isAdmin) {
      return allMessages;
    }

    final contactNameLower = _activeContact.name.toLowerCase();
    final filtered = allMessages.where((msg) {
      final lower = msg.text.toLowerCase();
      return lower.contains('[@$contactNameLower') ||
          lower.contains('[@${_activeContact.role.toLowerCase()}');
    }).toList();

    return filtered.isNotEmpty ? filtered : allMessages;
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

    // Automatically resolve or create thread if not yet created
    if (thread == null) {
      final targetUserId = _activeContact.isAdmin
          ? currentUser.id
          : (_activeContact.staffUserId ?? currentUser.id);

      thread = await _fetchOrCreateThread(
        token: token,
        targetUserId: targetUserId,
        currentUserId: currentUser.id,
      );
      if (thread != null && mounted) {
        setState(() {
          _thread = thread;
        });
      }
    }

    final threadId = thread?.id ?? 'pending-thread-${currentUser.id}';
    final payloadText = _activeContact.isAdmin
        ? text
        : '[@${_activeContact.name} • ${_activeContact.role}]\n$text';

    final localSeq = _nextOptimisticSeq();
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}-$localSeq';
    final optimisticMessage = _ChatMessage(
      id: localId,
      threadId: threadId,
      senderRole: 'staff',
      text: payloadText,
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
      if (thread == null) {
        throw Exception('Unable to initialize chat conversation. Please try again.');
      }

      final response = await http.post(
        _apiUri('/api/messages'),
        headers: _authHeaders(token, json: true),
        body: jsonEncode({'thread': thread.id, 'text': payloadText}),
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
    Navigator.of(context).popUntil((route) => route.isFirst);
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

  void _openContactsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmployeeContactsSheet(
        contacts: widget.allContacts,
        activeContact: _activeContact,
        onSelectContact: (contact) {
          Navigator.of(ctx).pop();
          if (contact.id == _activeContact.id) return;
          setState(() {
            _activeContact = contact;
            _messages = const [];
            _optimisticMessages = const [];
            _outgoingReceiptsByMessageId = const {};
            _thread = null;
          });
          unawaited(_refreshConversation(showLoader: true, forceScrollToBottom: true));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = _thread;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _WhatsAppChatAppBar(
            title: _chatTitle,
            subtitle: _chatSubtitle,
            avatarLetters: _avatarLetters,
            avatarColor: _activeContact.roleColor,
            isRefreshing: _isRefreshing,
            onBack: _handleBack,
            onContactTap: _openContactsModal,
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
                      _Composer(
                        controller: _messageController,
                        isEnabled: thread == null || thread.status == 'open',
                        hasText: _hasDraftText,
                        onSend: () => unawaited(_sendMessage()),
                        onCameraTap: () => _showPhaseOneMessage(
                          'Camera sharing is not part of chat phase 1.',
                        ),
                        onMicTap: () => _showPhaseOneMessage(
                          'Voice messages are not part of chat phase 1.',
                        ),
                        disabledMessage: (thread != null && thread.status != 'open')
                            ? 'This chat is currently closed.'
                            : null,
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

    if (_thread == null || displayMessages.isEmpty) {
      return _CenteredStatus(
        title: 'Start chatting with ${_activeContact.name}',
        subtitle: _activeContact.isAdmin
            ? 'Type a message below to reach out to the management and admin team.'
            : 'Send a message below to start your conversation with ${_activeContact.name} (${_activeContact.role}).',
        actionLabel: 'Say Hello 👋',
        onAction: () async {
          _messageController.text = 'Hi ${_activeContact.name} 👋';
          _messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: _messageController.text.length),
          );
        },
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

class _EmployeeContactsSheet extends StatefulWidget {
  final List<ChatContact> contacts;
  final ChatContact activeContact;
  final ValueChanged<ChatContact> onSelectContact;

  const _EmployeeContactsSheet({
    required this.contacts,
    required this.activeContact,
    required this.onSelectContact,
  });

  @override
  State<_EmployeeContactsSheet> createState() => _EmployeeContactsSheetState();
}

class _EmployeeContactsSheetState extends State<_EmployeeContactsSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredContacts = widget.contacts.where((c) {
      if (_searchQuery.isEmpty) return true;
      return c.name.toLowerCase().contains(_searchQuery) ||
          c.role.toLowerCase().contains(_searchQuery);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Contact',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15171A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.contacts.length + 1} contacts available',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.black54),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or role...',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () => _searchController.clear(),
                      child: const Icon(
                        Icons.cancel,
                        color: Color(0xFF9CA3AF),
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                if (_searchQuery.isEmpty ||
                    'admin'.contains(_searchQuery) ||
                    'management'.contains(_searchQuery))
                  _buildContactTile(
                    contact: ChatContact.admin,
                    isSelected: widget.activeContact.isAdmin,
                    isPinnedAdmin: true,
                  ),
                if (filteredContacts.isNotEmpty &&
                    (_searchQuery.isEmpty ||
                        'admin'.contains(_searchQuery) ||
                        'management'.contains(_searchQuery)))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Text(
                      'TEAM MEMBERS (${filteredContacts.length})',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ...filteredContacts.map(
                  (c) => _buildContactTile(
                    contact: c,
                    isSelected: !widget.activeContact.isAdmin &&
                        widget.activeContact.id == c.id,
                  ),
                ),
                if (filteredContacts.isEmpty &&
                    !('admin'.contains(_searchQuery) ||
                        'management'.contains(_searchQuery)))
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No contacts matching "$_searchQuery"',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required ChatContact contact,
    required bool isSelected,
    bool isPinnedAdmin = false,
  }) {
    return InkWell(
      onTap: () => widget.onSelectContact(contact),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isSelected ? const Color(0xFFE8F5E9) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    contact.roleColor,
                    contact.roleColor.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: contact.roleColor.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: isPinnedAdmin
                  ? const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 24,
                    )
                  : Text(
                      contact.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: contact.roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: contact.roleColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          contact.role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: contact.roleColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isPinnedAdmin
                        ? 'Official Support & Management Chat'
                        : 'Team Member • ${contact.role}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: _whatsAppGreen,
                size: 22,
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

enum _ChatMenuAction { refresh }

class _WhatsAppChatAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String avatarLetters;
  final Color avatarColor;
  final bool isRefreshing;
  final Future<void> Function() onBack;
  final VoidCallback onContactTap;
  final VoidCallback onCallTap;
  final Future<void> Function(_ChatMenuAction action) onMenuSelected;

  const _WhatsAppChatAppBar({
    required this.title,
    this.subtitle,
    required this.avatarLetters,
    this.avatarColor = const Color(0xFF7A1530),
    required this.isRefreshing,
    required this.onBack,
    required this.onContactTap,
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
                  gradient: LinearGradient(
                    colors: [avatarColor, avatarColor.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: avatarColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (isRefreshing) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _whatsAppGreen,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF667781),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Contacts',
                onPressed: onContactTap,
                icon: const Icon(Icons.contacts_outlined, color: Colors.black87),
              ),
              IconButton(
                tooltip: 'Call',
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

    String recipientTag = '';
    String displayBody = message.text;
    if (message.text.startsWith('[@') && message.text.contains(']\n')) {
      final endIdx = message.text.indexOf(']\n');
      recipientTag = message.text.substring(2, endIdx);
      displayBody = message.text.substring(endIdx + 2);
    } else if (message.text.startsWith('[@') && message.text.contains(']: ')) {
      final endIdx = message.text.indexOf(']: ');
      recipientTag = message.text.substring(2, endIdx);
      displayBody = message.text.substring(endIdx + 3);
    }

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
            text: TextSpan(text: displayBody, style: messageStyle),
            textDirection: Directionality.of(context),
          )..layout(maxWidth: contentMaxWidth);

          final bool isMultiLine = textPainter.computeLineMetrics().length > 1;
          final bool showTimeInline =
              recipientTag.isEmpty &&
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
                            child: Text(displayBody, style: messageStyle),
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
                          if (recipientTag.isNotEmpty) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'To: $recipientTag',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          ],
                          Text(displayBody, style: messageStyle),
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

String _formatInboxTime(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDate = DateTime(local.year, local.month, local.day);
  final diff = today.difference(msgDate).inDays;

  if (diff == 0) {
    return DateFormat('HH:mm').format(local);
  } else if (diff == 1) {
    return 'Yesterday';
  } else if (diff < 7) {
    return DateFormat('EEEE').format(local);
  }
  return DateFormat('dd/MM/yy').format(local);
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
