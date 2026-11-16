import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _chatInk = Color(0xff14213d);
const _chatBlue = Color(0xff2458dc);
const _chatSurface = Color(0xfff4f7fc);

class ChatInboxScreen extends StatelessWidget {
  const ChatInboxScreen({required this.isTrainer, super.key});

  final bool isTrainer;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _chatSurface,
        appBar: AppBar(title: const Text('Messages')),
        body: SafeArea(child: ChatInboxView(isTrainer: isTrainer)),
      );
}

class ChatInboxView extends StatefulWidget {
  const ChatInboxView({required this.isTrainer, super.key});

  final bool isTrainer;

  @override
  State<ChatInboxView> createState() => _ChatInboxViewState();
}

class _ChatInboxViewState extends State<ChatInboxView> {
  final _searchController = TextEditingController();
  late Future<List<_ChatContact>> _contacts;
  late final RealtimeChannel _channel;
  String _search = '';

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _contacts = _loadContacts();
    final userId = _client.auth.currentUser!.id;
    _channel = _client
        .channel('inbox:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'sender_id',
            value: userId,
          ),
          callback: _handleRealtimeChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: _handleRealtimeChange,
        )..subscribe();
  }

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_client.removeChannel(_channel));
    super.dispose();
  }

  void _handleRealtimeChange(PostgresChangePayload _) {
    if (mounted) setState(() => _contacts = _loadContacts());
  }

  Future<List<_ChatContact>> _loadContacts() async {
    final userId = _client.auth.currentUser!.id;
    final List<Map<String, dynamic>> records;
    if (widget.isTrainer) {
      final response = await _client
          .from('clients')
          .select('profile_id, full_name')
          .eq('trainer_id', userId)
          .not('profile_id', 'is', null)
          .order('full_name');
      records = List<Map<String, dynamic>>.from(response);
    } else {
      final client = await _client
          .from('clients')
          .select('trainer_id')
          .eq('profile_id', userId)
          .maybeSingle();
      final trainerId = client?['trainer_id'] as String?;
      records = trainerId == null
          ? []
          : [
              {
                'profile_id': trainerId,
                'full_name': 'Your coach',
              },
            ];
    }

    final contacts = records
        .where((record) => record['profile_id'] is String)
        .map((record) => _ChatContact(
              id: record['profile_id'] as String,
              name: record['full_name'] as String? ?? 'Your coach',
            ))
        .toList();
    if (contacts.isEmpty) return contacts;

    final response = await _client
        .from('messages')
        .select('sender_id, receiver_id, body, created_at, read_at')
        .or('sender_id.eq.$userId,receiver_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(500);
    final messages = List<Map<String, dynamic>>.from(response);
    final byPeer = {for (final contact in contacts) contact.id: contact};
    for (final message in messages) {
      final senderId = message['sender_id'] as String;
      final receiverId = message['receiver_id'] as String;
      final peerId = senderId == userId ? receiverId : senderId;
      final contact = byPeer[peerId];
      if (contact == null) continue;
      contact.lastMessage ??= message['body'] as String? ?? '';
      contact.lastMessageAt ??=
          DateTime.tryParse(message['created_at'] as String? ?? '');
      if (receiverId == userId && message['read_at'] == null) {
        contact.unreadCount++;
      }
    }
    contacts.sort((a, b) {
      final aTime = a.lastMessageAt;
      final bTime = b.lastMessageAt;
      if (aTime == null && bTime == null) return a.name.compareTo(b.name);
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return contacts;
  }

  Future<void> _openConversation(_ChatContact contact) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatConversationScreen(
        peerId: contact.id,
        peerName: contact.name,
      ),
    ));
    if (mounted) setState(() => _contacts = _loadContacts());
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_ChatContact>>(
              future: _contacts,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ChatState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Messages could not be loaded',
                    message: 'Check your connection, then try again.',
                    action: TextButton.icon(
                      onPressed: () =>
                          setState(() => _contacts = _loadContacts()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  );
                }
                final allContacts = snapshot.data ?? [];
                final contacts = allContacts
                    .where((contact) =>
                        contact.name.toLowerCase().contains(_search))
                    .toList();
                if (contacts.isEmpty) {
                  final noLinkedContact = allContacts.isEmpty;
                  return _ChatState(
                    icon: noLinkedContact
                        ? Icons.chat_bubble_outline
                        : Icons.search_off_outlined,
                    title: noLinkedContact
                        ? widget.isTrainer
                            ? 'No linked clients yet'
                            : 'Your coach is not linked yet'
                        : 'No matching conversations',
                    message: noLinkedContact
                        ? widget.isTrainer
                            ? 'Add a client account to start a private conversation.'
                            : 'Ask your trainer to finish setting up your account.'
                        : 'Try another name.',
                    action: noLinkedContact
                        ? TextButton.icon(
                            onPressed: () =>
                                setState(() => _contacts = _loadContacts()),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          )
                        : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      setState(() => _contacts = _loadContacts()),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: contacts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          minVerticalPadding: 12,
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xffe8eeff),
                            foregroundColor: _chatBlue,
                            child: Text(contact.name.isEmpty
                                ? '?'
                                : contact.name[0].toUpperCase()),
                          ),
                          title: Text(
                            contact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, color: _chatInk),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              contact.lastMessage ?? 'Start a conversation',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: contact.unreadCount > 0
                                    ? _chatInk
                                    : const Color(0xff71809a),
                                fontWeight: contact.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (contact.lastMessageAt != null)
                                Text(
                                  _formatTime(contact.lastMessageAt!),
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xff71809a)),
                                ),
                              if (contact.unreadCount > 0) ...[
                                const SizedBox(height: 6),
                                Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 22),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: _chatBlue,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text(
                                    contact.unreadCount > 99
                                        ? '99+'
                                        : '${contact.unreadCount}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: () => _openConversation(contact),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      );
}

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({
    required this.peerId,
    required this.peerName,
    super.key,
  });

  final String peerId;
  final String peerName;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late final SupabaseClient _client;
  late final String _userId;
  late final RealtimeChannel _channel;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    _userId = _client.auth.currentUser!.id;
    _channel = _client
        .channel('chat:$_userId:${widget.peerId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'sender_id',
            value: _userId,
          ),
          callback: _handleRealtimeChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: _userId,
          ),
          callback: _handleRealtimeChange,
        )..subscribe();
    _refreshMessages(markRead: true);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    unawaited(_client.removeChannel(_channel));
    super.dispose();
  }

  void _handleRealtimeChange(PostgresChangePayload payload) {
    final record =
        payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
    if (record['sender_id'] != widget.peerId &&
        record['receiver_id'] != widget.peerId) return;
    _refreshMessages(markRead: true);
  }

  Future<void> _refreshMessages({bool markRead = false}) async {
    try {
      if (markRead) {
        await _client
            .from('messages')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('sender_id', widget.peerId)
            .eq('receiver_id', _userId)
            .isFilter('read_at', null);
      }
      final response = await _client
          .from('messages')
          .select('id, sender_id, receiver_id, body, created_at, read_at')
          .or(
            'and(sender_id.eq.$_userId,receiver_id.eq.${widget.peerId}),'
            'and(sender_id.eq.${widget.peerId},receiver_id.eq.$_userId)',
          )
          .order('created_at', ascending: false)
          .limit(200);
      final messages = List<Map<String, dynamic>>.from(response.reversed);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
      _scrollToLatest();
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load messages. Check your connection and try again.';
      });
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || body.length > 4000 || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from('messages').insert({
        'sender_id': _userId,
        'receiver_id': widget.peerId,
        'body': body,
        'type': 'text',
      });
      _messageController.clear();
      await _refreshMessages();
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted)
        _showError(
            'Message could not be sent. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _chatSurface,
        appBar: AppBar(
          title: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xffe8eeff),
              foregroundColor: _chatBlue,
              child: Text(
                  widget.peerName.isEmpty
                      ? '?'
                      : widget.peerName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17)),
                  const Text('Private conversation',
                      style: TextStyle(fontSize: 11, color: Color(0xff71809a))),
                ],
              ),
            ),
          ]),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(child: _conversationBody()),
            _composer(),
          ]),
        ),
      );

  Widget _conversationBody() {
    if (_loading && _messages.isEmpty)
      return const Center(child: CircularProgressIndicator());
    if (_error != null && _messages.isEmpty) {
      return _ChatState(
        icon: Icons.cloud_off_outlined,
        title: 'Conversation unavailable',
        message: _error!,
        action: TextButton.icon(
          onPressed: () => _refreshMessages(markRead: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (_messages.isEmpty) {
      return _ChatState(
        icon: Icons.waving_hand_outlined,
        title: 'Start the conversation',
        message: 'Send a message to keep your coaching on track.',
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _MessageBubble(
        message: _messages[index],
        isMine: _messages[index]['sender_id'] == _userId,
      ),
    );
  }

  Widget _composer() => Material(
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  onChanged: (_) => setState(() {}),
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Write a message',
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending || _messageController.text.trim().isEmpty
                      ? null
                      : _sendMessage,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _ChatContact {
  _ChatContact({required this.id, required this.name});

  final String id;
  final String name;
  String? lastMessage;
  DateTime? lastMessageAt;
  int unreadCount = 0;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final Map<String, dynamic> message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final time =
        DateTime.tryParse(message['created_at'] as String? ?? '')?.toLocal();
    final body = message['body'] as String? ?? '';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
          decoration: BoxDecoration(
            color: isMine ? _chatBlue : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 5),
              bottomRight: Radius.circular(isMine ? 5 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(body,
                    style: TextStyle(
                        color: isMine ? Colors.white : _chatInk, height: 1.35)),
              ),
              const SizedBox(height: 5),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  time == null
                      ? ''
                      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: isMine
                          ? const Color(0xffdce8ff)
                          : const Color(0xff71809a),
                      fontSize: 10),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message['read_at'] == null ? Icons.done : Icons.done_all,
                    size: 14,
                    color: message['read_at'] == null
                        ? const Color(0xffdce8ff)
                        : const Color(0xff9ee6c4),
                  ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatState extends StatelessWidget {
  const _ChatState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                  color: const Color(0xffe9efff),
                  borderRadius: BorderRadius.circular(22)),
              child: Icon(icon, color: _chatBlue, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: _chatInk, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 7),
            Text(message,
                style: const TextStyle(color: Color(0xff6e7a91), height: 1.45),
                textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}/${local.day}';
}
