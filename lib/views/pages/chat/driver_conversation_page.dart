import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/chat/driver_chat_conversation_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_copy.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_header.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_message_bubble.dart';
import 'package:blockatie/views/pages/orders/order_details.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One Driver conversation.
///
/// The thread provider is created here and scoped to this route, so leaving the
/// page disposes it and its polling timer with it.
class DriverConversationPage extends StatelessWidget {
  const DriverConversationPage({
    super.key,
    required this.conversationId,
    required this.title,
    this.shipmentId,
    this.policyNum,
    this.repository,
  });

  final int conversationId;
  final String title;
  final int? shipmentId;
  final String? policyNum;

  @visibleForTesting
  final DriverChatRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DriverChatConversationProvider>(
      create: (_) => DriverChatConversationProvider(
        conversationId: conversationId,
        repository: repository ?? DriverChatService(),
      ),
      child: _ConversationView(
        title: title,
        shipmentId: shipmentId,
        policyNum: policyNum,
      ),
    );
  }
}

class _ConversationView extends StatefulWidget {
  const _ConversationView({
    required this.title,
    this.shipmentId,
    this.policyNum,
  });

  final String title;
  final int? shipmentId;
  final String? policyNum;

  @override
  State<_ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<_ConversationView>
    with WidgetsBindingObserver {
  /// Distance from the start of the thread at which older messages load.
  static const double _olderMessagesThreshold = 220;

  /// How far from the newest message still counts as "reading the latest".
  static const double _bottomThreshold = 160;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  late final DriverChatConversationProvider _provider;
  late final DriverChatConversationsProvider _conversations;

  /// The session this screen belongs to. Anything that finishes after the
  /// session moved on is ignored rather than drawn.
  final int _accountGeneration = UserSessionState.generation;
  bool get _active =>
      mounted && _accountGeneration == UserSessionState.generation;

  Set<String> _knownKeys = <String>{};
  int _seenLatestMessageId = 0;
  int _lastMarkedMessageId = 0;
  bool _initialLoadCompleted = false;
  bool _hasUnreadNewMessages = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<DriverChatConversationProvider>();
    _provider.addListener(_onProviderChanged);
    // Tells the app-wide provider which thread is on screen, so a push signal
    // for this conversation refetches through the existing cursor instead of
    // opening anything.
    _conversations = context.read<DriverChatConversationsProvider>();
    _conversations.registerOpenConversation(
      _provider.conversationId,
      _provider.pollOnce,
    );
    WidgetsBinding.instance.addObserver(this);
    UserSessionState.register(_resetConversation);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) unawaited(_loadInitial());
    });
  }

  /// Called by the session boundary on logout or account switch. The provider
  /// clears and stops itself; this only drops what the widget holds.
  void _resetConversation() {
    _messageController.clear();
    _knownKeys = <String>{};
    _seenLatestMessageId = 0;
    _lastMarkedMessageId = 0;
    _initialLoadCompleted = false;
    if (mounted) {
      setState(() => _hasUnreadNewMessages = false);
    }
  }

  @override
  void dispose() {
    UserSessionState.unregister(_resetConversation);
    _conversations.unregisterOpenConversation(_provider.conversationId);
    _provider.removeListener(_onProviderChanged);
    _provider.stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadInitial() async {
    if (!_active) return;
    await _provider.loadInitial();
    if (!_active || _provider.state == DriverChatConversationState.error) {
      return;
    }
    _knownKeys = _provider.messages.map((m) => m.identityKey).toSet();
    _seenLatestMessageId = _provider.latestMessageId;
    // The list is reversed, so it already opens on the newest message.
    _initialLoadCompleted = true;
    unawaited(_markVisibleMessagesRead());
    // Polling belongs to the provider, which refuses to run a second timer, so
    // a repeated call here is harmless.
    _provider.startPolling();
  }

  void _onScroll() {
    if (!_active || !_scrollController.hasClients) return;
    // Reversed list: the far end of the scroll is the start of the thread.
    if (_scrollController.position.extentAfter <= _olderMessagesThreshold) {
      unawaited(_loadOlder());
    }
    // Reaching the newest message answers the indicator, so it should not
    // linger once the driver has caught up.
    if (_hasUnreadNewMessages && _isNearNewest) {
      setState(() => _hasUnreadNewMessages = false);
      unawaited(_markVisibleMessagesRead());
    }
  }

  /// Loads the previous page of messages.
  ///
  /// No scroll correction is needed: the list is reversed, so older messages
  /// are appended at the far end of the scroll axis and the offset the driver
  /// is sitting at — measured from the newest message — does not move.
  ///
  /// The provider refuses overlapping calls, and it sets its loading state
  /// before the first await, so the scroll notifications that arrive while a
  /// page is in flight cannot start a second request.
  Future<void> _loadOlder() async {
    if (!_provider.hasOlder ||
        _provider.isLoading ||
        _provider.isLoadingOlder) {
      return;
    }
    await _provider.loadOlder();
  }

  bool get _isNearNewest {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels < _bottomThreshold;
  }

  /// Scrolls to the newest message, which in a reversed list is offset zero.
  ///
  /// Deferred to after the frame so the message that prompted it is laid out
  /// before the scroll target is read.
  Future<void> _scrollToNewest() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // New messages
  // ---------------------------------------------------------------------------

  /// Reacts to whatever the provider just did, including its own poll.
  ///
  /// Only an advance of the newest stored id counts as arrival: loading older
  /// messages adds rows without moving it, and must not look like new traffic.
  void _onProviderChanged() {
    if (!_active) return;

    final messages = _provider.messages;
    final incoming = messages
        .where((m) => !m.isMine && !_knownKeys.contains(m.identityKey))
        .toList(growable: false);
    _knownKeys = messages.map((m) => m.identityKey).toSet();

    final latest = _provider.latestMessageId;
    final advanced = latest > _seenLatestMessageId;
    _seenLatestMessageId = latest;

    if (!_initialLoadCompleted || !advanced || incoming.isEmpty) return;

    context
        .read<DriverChatConversationsProvider>()
        .applyLatestMessage(messages.last);

    if (_isNearNewest) {
      unawaited(_scrollToNewest());
      unawaited(_markVisibleMessagesRead());
    } else if (!_hasUnreadNewMessages) {
      // Never yank the view while the driver is reading further up.
      setState(() => _hasUnreadNewMessages = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Read state
  // ---------------------------------------------------------------------------

  /// Acknowledges everything incoming that is currently loaded.
  ///
  /// Skipped when the newest incoming message is one we already acknowledged,
  /// so sitting in an idle thread does not send a request every poll.
  Future<void> _markVisibleMessagesRead() async {
    if (!_active) return;
    // Resolved before the await so nothing reaches for a BuildContext once the
    // request has completed.
    final conversations = context.read<DriverChatConversationsProvider>();

    final newestIncoming = _provider.messages
        .where((m) => !m.isMine && m.messageId != null)
        .fold<int>(
          0,
          (latest, m) => m.messageId! > latest ? m.messageId! : latest,
        );
    if (newestIncoming == 0 || newestIncoming <= _lastMarkedMessageId) return;

    final result = await _provider.markRead();
    if (!_active || result == null) return;
    _lastMarkedMessageId = result.lastReadMessageId;
    // The server's figure, not a local guess.
    conversations.applyConversationUnread(
      _provider.conversationId,
      result.unreadCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  Future<void> _sendMessage() async {
    final text = _messageController.text;
    if (text.trim().isEmpty) {
      _showMessage(chatCopy(context, 'Write a message first.', 'اكتب رسالة أولاً.'));
      return;
    }
    if (_provider.isSending) return;

    _messageController.clear();
    final sent = await _provider.sendMessage(text);
    if (!_active) return;
    await _scrollToNewest();
    _afterSendAttempt(sent);
  }

  /// Re-sends a failed message under its original key.
  ///
  /// This goes through the provider, which reuses that message's
  /// `client_message_id`, so the backend recognises a retry instead of storing
  /// the text twice — and no second bubble is created.
  Future<void> _retryMessage(String clientMessageId) async {
    final sent = await _provider.retryFailed(clientMessageId);
    if (!_active) return;
    await _scrollToNewest();
    _afterSendAttempt(sent);
  }

  void _afterSendAttempt(bool sent) {
    if (!_active) return;
    if (sent && _provider.messages.isNotEmpty) {
      context
          .read<DriverChatConversationsProvider>()
          .applyLatestMessage(_provider.messages.last);
      return;
    }
    if (!sent) {
      _showMessage(chatErrorText(context, _provider.errorMessage));
    }
  }

  void _showMessage(String value) {
    if (!_active || value.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
      );
  }

  // ---------------------------------------------------------------------------
  // Shipment context
  // ---------------------------------------------------------------------------

  /// Opens the Driver's own shipment screen.
  ///
  /// Only the id travels: that screen resolves and authorizes the shipment
  /// itself, so nothing here treats chat metadata as permission.
  Future<void> _openShipment(int shipmentId) async {
    _provider.pausePolling();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: DriverChatRoutes.shipment),
        builder: (_) => OrderDetailPage(
          shipmentId: shipmentId,
          phoneCustomer: '',
          // The thread is already open behind this screen; offering to open it
          // again from there would stack a second copy.
          allowChatEntry: false,
        ),
      ),
    );
    if (!_active) return;
    _provider.resumePolling(immediate: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_active) return;
    if (state == AppLifecycleState.resumed) {
      _provider.resumePolling(immediate: _initialLoadCompleted);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _provider.pausePolling();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final policy = widget.policyNum?.trim() ?? '';
    final shipmentId = widget.shipmentId;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xffF6F8FC),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DriverChatHeader(
                title: widget.title.trim().isEmpty
                    ? chatCopy(context, 'Operations', 'العمليات')
                    : widget.title.trim(),
                subtitle: policy.isEmpty
                    ? chatCopy(
                        context,
                        'Operations and support',
                        'العمليات والدعم',
                      )
                    : '${chatCopy(context, 'Shipment', 'الشحنة')} $policy',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              if (shipmentId != null && shipmentId > 0)
                _ShipmentContextBar(
                  policyNum: policy,
                  onTap: () => _openShipment(shipmentId),
                ),
              Expanded(
                child: Consumer<DriverChatConversationProvider>(
                  builder: (context, provider, _) => _buildMessages(provider),
                ),
              ),
              _MessageComposer(
                controller: _messageController,
                focusNode: _messageFocusNode,
                isSending: context.select<DriverChatConversationProvider, bool>(
                  (provider) => provider.isSending,
                ),
                onSend: _sendMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(DriverChatConversationProvider provider) {
    if (provider.isLoading ||
        provider.state == DriverChatConversationState.initial) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.state == DriverChatConversationState.error &&
        provider.messages.isEmpty) {
      return _MessagesError(
        message: chatErrorText(context, provider.errorMessage),
        onRetry: _loadInitial,
      );
    }

    if (provider.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            chatCopy(
              context,
              'Send a message to start this conversation.',
              'أرسل رسالة لبدء هذه المحادثة.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final showOlderSpinner = provider.isLoadingOlder;

    return Stack(
      children: [
        // Reversed: index 0 is the newest message, pinned to the bottom. Older
        // pages then extend away from the viewport instead of pushing the
        // thread down, so loading them cannot disturb the reading position.
        ListView.builder(
          controller: _scrollController,
          reverse: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: provider.messages.length + (showOlderSpinner ? 1 : 0),
          itemBuilder: (context, index) {
            if (showOlderSpinner && index == provider.messages.length) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            // The data stays oldest -> newest; only the axis is flipped, so
            // the thread still reads chronologically down the screen.
            final messageIndex = provider.messages.length - 1 - index;
            final message = provider.messages[messageIndex];
            final previous =
                messageIndex > 0 ? provider.messages[messageIndex - 1] : null;
            final createdAt = message.createdAt;
            // One separator per day: only the first message of a day draws it.
            final needsSeparator = createdAt != null &&
                (previous == null ||
                    DriverChatDateFormatter.isDifferentDay(
                      previous.createdAt,
                      createdAt,
                    ));

            return KeyedSubtree(
              key: ValueKey(message.identityKey),
              child: Column(
                children: [
                  if (needsSeparator)
                    DriverChatDateSeparator(value: createdAt),
                  DriverChatMessageBubble(
                    message: message,
                    onRetry: message.hasFailed &&
                            message.clientMessageId != null
                        ? () => _retryMessage(message.clientMessageId!)
                        : null,
                  ),
                ],
              ),
            );
          },
        ),
        if (_hasUnreadNewMessages)
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: _NewMessagesButton(
              onTap: () {
                setState(() => _hasUnreadNewMessages = false);
                unawaited(_scrollToNewest());
                unawaited(_markVisibleMessagesRead());
              },
            ),
          ),
      ],
    );
  }
}

class _NewMessagesButton extends StatelessWidget {
  const _NewMessagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
      label: Text(chatCopy(context, 'New messages', 'رسائل جديدة')),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

class _ShipmentContextBar extends StatelessWidget {
  const _ShipmentContextBar({required this.policyNum, required this.onTap});

  final String policyNum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xffEAF2FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chatCopy(context, 'Shipment details', 'تفاصيل الشحنة'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (policyNum.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          policyNum,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  isRtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: const Color(0xff94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: const Color(0x190F172A),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  // Grows with the message, then scrolls, so a long note never
                  // swallows the thread.
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: chatCopy(
                      context,
                      'Write a message',
                      'اكتب رسالة',
                    ),
                    filled: true,
                    fillColor: const Color(0xffF1F5F9),
                    contentPadding:
                        const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xffE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: chatCopy(context, 'Send', 'إرسال'),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    // Disabled only while a send is in flight. A failed message
                    // is retried from its own bubble, so this never blocks it.
                    onPressed: isSending ? null : onSend,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: AppColors.primary,
                      shape: const CircleBorder(),
                    ),
                    child: isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesError extends StatelessWidget {
  const _MessagesError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: Color(0xff94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff334155),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(chatCopy(context, 'Try again', 'إعادة المحاولة')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
