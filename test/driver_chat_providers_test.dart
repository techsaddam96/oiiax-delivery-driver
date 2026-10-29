// State-layer tests for Driver Chat.
//
// Two properties matter most here and are tested from several angles:
//   * a response issued under one driver can never land in another driver's
//     state, however late it arrives;
//   * a retried send reuses its original client_message_id, so the backend's
//     idempotency index can recognise it and the thread never shows the same
//     message twice.

import 'dart:async';

import 'package:blockatie/models/chat/chat_exception.dart';
import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/provider/chat/driver_chat_conversation_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverChatConversation _conversation({
  required int id,
  int unread = 0,
  String lastMessage = 'hello',
}) {
  return DriverChatConversation(
    conversationId: id,
    conversationType: 'shipment_driver',
    title: 'Shipment $id',
    lastMessage: lastMessage,
    lastMessageType: 'text',
    unreadCount: unread,
    shipmentId: id,
    policyNum: 'BLK-$id',
    shipmentStatusId: 4,
    lastMessageSenderRole: 'admin',
    lastMessageAt: DateTime(2026, 9, 15, 9, 30),
  );
}

DriverChatConversationPage _conversationPage(
  List<DriverChatConversation> conversations, {
  int page = 1,
  int totalPages = 1,
  int? total,
}) {
  return DriverChatConversationPage(
    conversations: conversations,
    pagination: DriverChatPagination(
      page: page,
      limit: 15,
      total: total ?? conversations.length,
      totalPages: totalPages,
    ),
  );
}

DriverChatMessage _incoming(int id, {bool isRead = false}) {
  return DriverChatMessage(
    messageId: id,
    conversationId: 3001,
    senderRole: 'admin',
    senderName: 'Admin / Operations',
    messageType: 'text',
    message: 'message $id',
    isMine: false,
    isRead: isRead,
    createdAt: DateTime(2026, 9, 15, 9, 30).add(Duration(minutes: id)),
    status: DriverChatMessageStatus.sent,
  );
}

DriverChatMessage _stored(int id, String clientMessageId) {
  return DriverChatMessage(
    messageId: id,
    conversationId: 3001,
    senderRole: 'driver',
    senderName: '',
    messageType: 'text',
    message: 'On my way',
    isMine: true,
    isRead: false,
    createdAt: DateTime(2026, 9, 15, 10),
    clientMessageId: clientMessageId,
    status: DriverChatMessageStatus.sent,
  );
}

const ChatException _serverError = ChatServerException();

// -----------------------------------------------------------------------------
// Fake transport
// -----------------------------------------------------------------------------

class _FakeChatRepository implements DriverChatRepository {
  final List<int> listedPages = <int>[];
  final List<int?> requestedBeforeIds = <int?>[];
  final List<int> requestedAfterIds = <int>[];
  final List<String> sentClientMessageIds = <String>[];
  final List<String> sentMessages = <String>[];
  final List<int?> markReadCursors = <int?>[];
  int unreadCountCalls = 0;

  Future<DriverChatConversationPage> Function(int page)? onListConversations;
  Future<DriverChatMessagesPage> Function(int? beforeMessageId)? onGetMessages;
  Future<DriverChatNewMessagesPage> Function(int afterMessageId)?
      onGetNewMessages;
  Future<DriverChatSendResult> Function(String message, String clientMessageId)?
      onSendMessage;
  Future<DriverChatReadResult> Function(int? lastMessageId)? onMarkRead;
  Future<int> Function()? onUnreadCount;

  @override
  Future<DriverChatConversationPage> listConversations({
    int page = 1,
    int limit = 15,
    CancelToken? cancelToken,
  }) {
    listedPages.add(page);
    return onListConversations?.call(page) ??
        Future.value(_conversationPage(const <DriverChatConversation>[]));
  }

  @override
  Future<DriverChatMessagesPage> getMessages({
    required int conversationId,
    int? beforeMessageId,
    int limit = 30,
    CancelToken? cancelToken,
  }) {
    requestedBeforeIds.add(beforeMessageId);
    return onGetMessages?.call(beforeMessageId) ??
        Future.value(
          const DriverChatMessagesPage(
            messages: <DriverChatMessage>[],
            hasMore: false,
          ),
        );
  }

  @override
  Future<DriverChatNewMessagesPage> getNewMessages({
    required int conversationId,
    required int afterMessageId,
    int limit = 50,
    CancelToken? cancelToken,
  }) {
    requestedAfterIds.add(afterMessageId);
    return onGetNewMessages?.call(afterMessageId) ??
        Future.value(
          DriverChatNewMessagesPage(
            messages: const <DriverChatMessage>[],
            latestMessageId: afterMessageId,
            hasMore: false,
          ),
        );
  }

  @override
  Future<DriverChatSendResult> sendMessage({
    required int conversationId,
    required String message,
    required String clientMessageId,
    CancelToken? cancelToken,
  }) {
    sentClientMessageIds.add(clientMessageId);
    sentMessages.add(message);
    return onSendMessage?.call(message, clientMessageId) ??
        Future.value(
          DriverChatSendResult(
            message: _stored(100, clientMessageId),
            isDuplicate: false,
          ),
        );
  }

  @override
  Future<DriverChatReadResult> markRead({
    required int conversationId,
    int? lastMessageId,
    CancelToken? cancelToken,
  }) {
    markReadCursors.add(lastMessageId);
    return onMarkRead?.call(lastMessageId) ??
        Future.value(
          DriverChatReadResult(
            conversationId: conversationId,
            lastReadMessageId: lastMessageId ?? 0,
            markedCount: 1,
            unreadCount: 0,
            unreadBefore: 1,
          ),
        );
  }

  @override
  Future<int> getUnreadCount({CancelToken? cancelToken}) {
    unreadCountCalls++;
    return onUnreadCount?.call() ?? Future.value(0);
  }

  final List<int> resolvedShipmentIds = <int>[];
  Future<DriverChatConversationResult> Function(int shipmentId)?
      onGetOrCreateShipmentConversation;

  @override
  Future<DriverChatConversationResult> getOrCreateShipmentConversation({
    required int shipmentId,
    CancelToken? cancelToken,
  }) {
    resolvedShipmentIds.add(shipmentId);
    return onGetOrCreateShipmentConversation?.call(shipmentId) ??
        Future.value(
          DriverChatConversationResult(
            conversation: _conversation(id: 4000 + shipmentId),
            isCreated: false,
          ),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Conversation list
  // -------------------------------------------------------------------------

  group('DriverChatConversationsProvider', () {
    late _FakeChatRepository repository;
    late DriverChatConversationsProvider provider;

    setUp(() {
      repository = _FakeChatRepository();
      provider = DriverChatConversationsProvider(repository: repository);
      addTearDown(provider.dispose);
    });

    test('loads the first page and exposes its pagination', () async {
      repository.onListConversations = (_) async => _conversationPage(
            [_conversation(id: 3001, unread: 2), _conversation(id: 3002)],
            totalPages: 3,
            total: 40,
          );

      await provider.loadInitial();

      expect(provider.state, DriverChatConversationsState.loaded);
      expect(provider.conversations, hasLength(2));
      expect(provider.total, 40);
      expect(provider.hasNextPage, isTrue);
      expect(provider.hasPreviousPage, isFalse);
      expect(repository.listedPages, [1]);
    });

    test('an empty inbox is a distinct state, not an error', () async {
      await provider.loadInitial();

      expect(provider.state, DriverChatConversationsState.empty);
      expect(provider.conversations, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('a second load is skipped once the list is populated', () async {
      repository.onListConversations =
          (_) async => _conversationPage([_conversation(id: 3001)]);

      await provider.loadInitial();
      await provider.loadInitial();

      expect(repository.listedPages, [1]);
    });

    test('a page replaces the previous one rather than accumulating', () async {
      repository.onListConversations = (page) async => _conversationPage(
            [_conversation(id: page == 1 ? 3001 : 3002)],
            page: page,
            totalPages: 2,
            total: 2,
          );

      await provider.loadInitial();
      await provider.nextPage();

      expect(provider.conversations.single.conversationId, 3002);
      expect(provider.page, 2);
      expect(repository.listedPages, [1, 2]);
    });

    test('a page beyond the last is never requested', () async {
      repository.onListConversations = (page) async => _conversationPage(
            [_conversation(id: 3001)],
            page: page,
            totalPages: 1,
          );

      await provider.loadInitial();
      await provider.goToPage(5);
      await provider.nextPage();

      expect(repository.listedPages, [1]);
    });

    test('a failure surfaces a safe message, never a raw error', () async {
      repository.onListConversations = (_) async => throw _serverError;

      await provider.loadInitial();

      expect(provider.state, DriverChatConversationsState.error);
      expect(provider.errorMessage, 'chat_server_error');
    });

    test('the global badge is taken from the server and clamped', () async {
      repository.onUnreadCount = () async => 7;
      await provider.refreshUnreadCount();
      expect(provider.unreadCount, 7);

      repository.onUnreadCount = () async => -2;
      await provider.refreshUnreadCount();
      expect(provider.unreadCount, 0);
    });

    test('overlapping badge refreshes collapse into one request', () async {
      final gate = Completer<int>();
      repository.onUnreadCount = () => gate.future;

      final first = provider.refreshUnreadCount();
      final second = provider.refreshUnreadCount();
      gate.complete(3);
      await Future.wait([first, second]);

      expect(repository.unreadCountCalls, 1);
      expect(provider.unreadCount, 3);
    });

    test('marking a thread read moves the badge by the same delta', () async {
      repository.onListConversations = (_) async => _conversationPage([
            _conversation(id: 3001, unread: 4),
            _conversation(id: 3002, unread: 1),
          ]);
      repository.onUnreadCount = () async => 5;

      await provider.loadInitial();
      await provider.refreshUnreadCount();
      provider.applyConversationUnread(3001, 0);

      expect(provider.unreadCount, 1);
      expect(provider.conversations.first.unreadCount, 0);
    });

    test('a thread that is not on this page leaves the badge alone', () async {
      repository.onListConversations =
          (_) async => _conversationPage([_conversation(id: 3001, unread: 2)]);
      repository.onUnreadCount = () async => 2;

      await provider.loadInitial();
      await provider.refreshUnreadCount();
      provider.applyConversationUnread(9999, 0);

      expect(provider.unreadCount, 2);
    });

    test('the badge can never be driven negative', () async {
      repository.onListConversations =
          (_) async => _conversationPage([_conversation(id: 3001, unread: 4)]);

      await provider.loadInitial();
      // Badge still 0 because it was never fetched; the delta would be -4.
      provider.applyConversationUnread(3001, 0);

      expect(provider.unreadCount, 0);
    });

    test('a new message lifts its thread to the top of the list', () async {
      repository.onListConversations = (_) async => _conversationPage([
            _conversation(id: 3001, lastMessage: 'old'),
            _conversation(id: 3002, lastMessage: 'older'),
          ]);

      await provider.loadInitial();
      provider.applyLatestMessage(
        _incoming(60).copyWith(conversationId: 3002, message: 'brand new'),
      );

      expect(provider.conversations.first.conversationId, 3002);
      expect(provider.conversations.first.lastMessage, 'brand new');
      expect(provider.conversations.first.lastMessageSenderRole, 'admin');
    });

    test('a session reset wipes the list, the pages and the badge', () async {
      repository.onListConversations =
          (_) async => _conversationPage([_conversation(id: 3001, unread: 3)]);
      repository.onUnreadCount = () async => 3;

      await provider.loadInitial();
      await provider.refreshUnreadCount();
      expect(provider.conversations, isNotEmpty);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.conversations, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.state, DriverChatConversationsState.initial);
      expect(provider.pagination.total, 0);
    });

    test("driver A's late response never populates driver B", () async {
      final gate = Completer<DriverChatConversationPage>();
      repository.onListConversations = (_) => gate.future;

      final pending = provider.loadInitial();
      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete(_conversationPage([_conversation(id: 3001, unread: 9)]));
      await pending;

      expect(provider.conversations, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.state, DriverChatConversationsState.initial);
    });

    test("driver A's late badge response never populates driver B", () async {
      final gate = Completer<int>();
      repository.onUnreadCount = () => gate.future;

      final pending = provider.refreshUnreadCount();
      UserSessionState.reset(SessionResetReason.invalidSession);
      gate.complete(12);
      await pending;

      expect(provider.unreadCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  // A single thread
  // -------------------------------------------------------------------------

  group('DriverChatConversationProvider', () {
    late _FakeChatRepository repository;
    late DriverChatConversationProvider provider;

    DriverChatConversationProvider build({Duration? pollingInterval}) {
      final created = DriverChatConversationProvider(
        conversationId: 3001,
        repository: repository,
        pollingInterval:
            pollingInterval ?? const Duration(milliseconds: 25),
      );
      addTearDown(created.dispose);
      return created;
    }

    setUp(() {
      repository = _FakeChatRepository();
      provider = build();
    });

    test('loads the newest window oldest -> newest with a cursor', () async {
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10), _incoming(11)],
            hasMore: true,
            nextBeforeMessageId: 10,
          );

      await provider.loadInitial();

      expect(provider.state, DriverChatConversationState.loaded);
      expect(
        provider.messages.map((message) => message.messageId),
        [10, 11],
      );
      expect(provider.hasOlder, isTrue);
      expect(provider.latestMessageId, 11);
    });

    test('older pages merge in ahead of what is already loaded', () async {
      repository.onGetMessages = (before) async {
        if (before == null) {
          return DriverChatMessagesPage(
            messages: [_incoming(10), _incoming(11)],
            hasMore: true,
            nextBeforeMessageId: 10,
          );
        }
        return DriverChatMessagesPage(
          messages: [_incoming(8), _incoming(9)],
          hasMore: false,
        );
      };

      await provider.loadInitial();
      await provider.loadOlder();

      expect(
        provider.messages.map((message) => message.messageId),
        [8, 9, 10, 11],
      );
      expect(provider.hasOlder, isFalse);
      expect(repository.requestedBeforeIds, [null, 10]);
    });

    test('a message delivered twice appears once', () async {
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );
      repository.onGetNewMessages = (after) async => DriverChatNewMessagesPage(
            messages: [_incoming(10), _incoming(11)],
            latestMessageId: 11,
            hasMore: false,
          );

      await provider.loadInitial();
      await provider.fetchNewMessages();
      await provider.fetchNewMessages();

      expect(
        provider.messages.map((message) => message.identityKey),
        ['server:10', 'server:11'],
      );
    });

    test('the polling cursor only ever moves forward', () async {
      repository.onGetNewMessages = (after) async => DriverChatNewMessagesPage(
            messages: const <DriverChatMessage>[],
            // A stale or misbehaving reply reporting an older id.
            latestMessageId: after == 0 ? 20 : 5,
            hasMore: false,
          );

      await provider.fetchNewMessages();
      expect(provider.latestMessageId, 20);

      await provider.fetchNewMessages();
      expect(provider.latestMessageId, 20);
    });

    test('a failed load leaves the loaded thread on screen', () async {
      repository.onGetMessages = (before) async {
        if (before == null) {
          return DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: true,
            nextBeforeMessageId: 10,
          );
        }
        throw _serverError;
      };

      await provider.loadInitial();
      await provider.loadOlder();

      expect(provider.messages, hasLength(1));
      expect(provider.state, DriverChatConversationState.loaded);
      expect(provider.errorMessage, 'chat_server_error');
    });

    group('sending', () {
      test('an optimistic message is reconciled, not duplicated', () async {
        await provider.sendMessage('On my way');

        expect(provider.messages, hasLength(1));
        final stored = provider.messages.single;
        expect(stored.messageId, 100);
        expect(stored.status, DriverChatMessageStatus.sent);
        expect(stored.clientMessageId, repository.sentClientMessageIds.single);
        expect(provider.isSending, isFalse);
      });

      test('the message is visible immediately, before the server replies',
          () async {
        final gate = Completer<DriverChatSendResult>();
        repository.onSendMessage = (_, __) => gate.future;

        final pending = provider.sendMessage('On my way');
        expect(provider.messages.single.isPending, isTrue);
        expect(provider.isSending, isTrue);

        gate.complete(
          DriverChatSendResult(
            message: _stored(100, repository.sentClientMessageIds.single),
            isDuplicate: false,
          ),
        );
        await pending;

        expect(provider.messages.single.isPending, isFalse);
      });

      test('a blank message is refused without a request', () async {
        expect(await provider.sendMessage('   '), isFalse);

        expect(repository.sentClientMessageIds, isEmpty);
        expect(provider.messages, isEmpty);
        expect(provider.errorMessage, 'chat_message_required');
      });

      test('a failed send is kept and marked, not dropped', () async {
        repository.onSendMessage = (_, __) async => throw _serverError;

        expect(await provider.sendMessage('On my way'), isFalse);

        expect(provider.messages, hasLength(1));
        expect(provider.messages.single.hasFailed, isTrue);
        expect(provider.messages.single.message, 'On my way');
        expect(provider.errorMessage, 'chat_server_error');
      });

      test('a retry reuses the original client_message_id', () async {
        repository.onSendMessage = (_, __) async => throw _serverError;
        await provider.sendMessage('On my way');
        final originalId = repository.sentClientMessageIds.single;

        repository.onSendMessage = (message, clientMessageId) async =>
            DriverChatSendResult(
              message: _stored(100, clientMessageId),
              isDuplicate: false,
            );
        expect(await provider.retryFailed(originalId), isTrue);

        expect(repository.sentClientMessageIds, [originalId, originalId]);
        expect(provider.messages, hasLength(1));
        expect(provider.messages.single.messageId, 100);
      });

      test('a retry re-sends the original text, not the caller\'s', () async {
        repository.onSendMessage = (_, __) async => throw _serverError;
        await provider.sendMessage('Original text');
        final originalId = repository.sentClientMessageIds.single;

        repository.onSendMessage = (message, clientMessageId) async =>
            DriverChatSendResult(
              message: _stored(100, clientMessageId),
              isDuplicate: false,
            );
        await provider.retryFailed(originalId);

        expect(repository.sentMessages, ['Original text', 'Original text']);
      });

      test('a retry the backend recognises reconciles to one message',
          () async {
        repository.onSendMessage = (_, __) async => throw _serverError;
        await provider.sendMessage('On my way');
        final originalId = repository.sentClientMessageIds.single;

        repository.onSendMessage = (message, clientMessageId) async =>
            DriverChatSendResult(
              message: _stored(100, clientMessageId),
              // The first attempt did reach the server after all.
              isDuplicate: true,
            );
        await provider.retryFailed(originalId);

        expect(provider.messages, hasLength(1));
        expect(provider.messages.single.messageId, 100);
      });

      test('retrying an unknown or already-sent id does nothing', () async {
        await provider.sendMessage('On my way');
        final sentId = repository.sentClientMessageIds.single;

        expect(await provider.retryFailed(sentId), isFalse);
        expect(await provider.retryFailed('driver-chat-never-existed'), isFalse);
        expect(repository.sentClientMessageIds, hasLength(1));
      });

      test('a pending message sorts after every stored message', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_incoming(10), _incoming(11)],
              hasMore: false,
            );
        final gate = Completer<DriverChatSendResult>();
        repository.onSendMessage = (_, __) => gate.future;

        await provider.loadInitial();
        final pending = provider.sendMessage('On my way');

        expect(provider.messages.last.isPending, isTrue);
        expect(provider.messages.first.messageId, 10);

        gate.complete(
          DriverChatSendResult(
            message: _stored(100, repository.sentClientMessageIds.single),
            isDuplicate: false,
          ),
        );
        await pending;
      });

      test("a send that lands after a session change is discarded", () async {
        final gate = Completer<DriverChatSendResult>();
        repository.onSendMessage = (_, __) => gate.future;

        final pending = provider.sendMessage('On my way');
        UserSessionState.reset(SessionResetReason.accountChanged);
        gate.complete(
          DriverChatSendResult(
            message: _stored(100, repository.sentClientMessageIds.single),
            isDuplicate: false,
          ),
        );

        expect(await pending, isFalse);
        expect(provider.messages, isEmpty);
      });
    });

    group('read receipts', () {
      test('marks up to the newest incoming message and reports unread',
          () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_incoming(10), _incoming(11)],
              hasMore: false,
            );

        await provider.loadInitial();
        final result = await provider.markRead();

        expect(repository.markReadCursors, [11]);
        expect(result, isNotNull);
        expect(result!.unreadCount, 0);
        expect(provider.unreadCount, 0);
        expect(
          provider.messages.every((message) => message.isRead),
          isTrue,
        );
      });

      test('own messages are never marked read by this driver', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_stored(10, 'driver-chat-a'), _incoming(11)],
              hasMore: false,
            );

        await provider.loadInitial();
        await provider.markRead();

        final own = provider.messages.firstWhere((message) => message.isMine);
        expect(own.isRead, isFalse);
      });

      test('a thread with nothing incoming is not marked', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_stored(10, 'driver-chat-a')],
              hasMore: false,
            );

        await provider.loadInitial();

        expect(await provider.markRead(), isNull);
        expect(repository.markReadCursors, isEmpty);
      });

      test('a failure is reported without losing the thread', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_incoming(10)],
              hasMore: false,
            );
        repository.onMarkRead = (_) async => throw _serverError;

        await provider.loadInitial();

        expect(await provider.markRead(), isNull);
        expect(provider.messages, hasLength(1));
        expect(provider.errorMessage, 'chat_server_error');
      });
    });

    group('polling', () {
      test('starting twice never leaves an orphan timer behind', () async {
        provider.startPolling();
        provider.startPolling();
        provider.startPolling();
        expect(provider.isPolling, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 120));
        final pollsWhileRunning = repository.requestedAfterIds.length;
        expect(pollsWhileRunning, greaterThan(0));

        // One cancel must silence every timer that was ever created.
        provider.stopPolling();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(provider.isPolling, isFalse);
        expect(repository.requestedAfterIds.length, pollsWhileRunning);
      });

      test('pause stops the loop and resume brings it back', () async {
        provider.startPolling();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        final beforePause = repository.requestedAfterIds.length;

        provider.pausePolling();
        expect(provider.isPolling, isFalse);
        expect(provider.isPollingPaused, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(repository.requestedAfterIds.length, beforePause);

        provider.resumePolling();
        expect(provider.isPolling, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(repository.requestedAfterIds.length, greaterThan(beforePause));
      });

      test('resume does nothing for a loop that was never started', () async {
        provider.resumePolling();

        expect(provider.isPolling, isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(repository.requestedAfterIds, isEmpty);
      });

      test('a session change stops polling and clears the thread', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_incoming(10)],
              hasMore: false,
            );
        await provider.loadInitial();
        provider.startPolling();
        await Future<void>.delayed(const Duration(milliseconds: 60));

        UserSessionState.reset(SessionResetReason.accountInactive);

        expect(provider.isPolling, isFalse);
        expect(provider.messages, isEmpty);
        expect(provider.latestMessageId, 0);

        final afterReset = repository.requestedAfterIds.length;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(repository.requestedAfterIds.length, afterReset);
      });

      test('disposing stops polling', () async {
        final disposable = DriverChatConversationProvider(
          conversationId: 3001,
          repository: repository,
          pollingInterval: const Duration(milliseconds: 25),
        );
        disposable.startPolling();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(repository.requestedAfterIds, isNotEmpty);

        disposable.dispose();
        final afterDispose = repository.requestedAfterIds.length;
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(disposable.isPolling, isFalse);
        expect(repository.requestedAfterIds.length, afterDispose);
      });

      test('a poll does not put the thread into a loading state', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_incoming(10)],
              hasMore: false,
            );
        repository.onGetNewMessages = (after) async =>
            DriverChatNewMessagesPage(
              messages: [_incoming(11)],
              latestMessageId: 11,
              hasMore: false,
            );

        await provider.loadInitial();
        await provider.pollOnce();

        expect(provider.state, DriverChatConversationState.loaded);
        expect(provider.messages, hasLength(2));
      });

      test('a failing poll never replaces the thread with an error', () async {
        repository.onGetMessages = (_) async => DriverChatMessagesPage(
              messages: [_incoming(10)],
              hasMore: false,
            );
        await provider.loadInitial();

        repository.onGetNewMessages = (_) async => throw _serverError;
        await provider.pollOnce();

        expect(provider.state, DriverChatConversationState.loaded);
        expect(provider.messages, hasLength(1));
        expect(provider.errorMessage, isNull);
      });

      test('a poll drains a backlog but stops at the page cap', () async {
        repository.onGetNewMessages = (after) async =>
            DriverChatNewMessagesPage(
              messages: [_incoming(after + 1)],
              latestMessageId: after + 1,
              // Always more, so only the cap can end the loop.
              hasMore: true,
            );

        await provider.pollOnce();

        expect(
          repository.requestedAfterIds,
          hasLength(DriverChatConversationProvider.maxPollPages),
        );
      });
    });
  });
  // -------------------------------------------------------------------------
  // Resolving a shipment thread
  // -------------------------------------------------------------------------

  group('resolveShipmentConversation', () {
    late _FakeChatRepository repository;
    late DriverChatConversationsProvider provider;

    setUp(() {
      repository = _FakeChatRepository();
      provider = DriverChatConversationsProvider(repository: repository);
      addTearDown(provider.dispose);
    });

    test('returns the thread for a shipment that is not on the page',
        () async {
      repository.onListConversations =
          (_) async => _conversationPage([_conversation(id: 3001)]);
      repository.onGetOrCreateShipmentConversation = (shipmentId) async =>
          DriverChatConversationResult(
            conversation: _conversation(id: 9001),
            isCreated: true,
          );

      await provider.loadInitial();
      final resolved = await provider.resolveShipmentConversation(77);

      expect(resolved, isNotNull);
      expect(resolved!.conversationId, 9001);
      expect(repository.resolvedShipmentIds, [77]);
      // The visible page is untouched: an off-page thread is never spliced in.
      expect(provider.conversations.single.conversationId, 3001);
      expect(provider.pagination.total, 1);
    });

    test('refreshes the row when the thread is on the current page', () async {
      repository.onListConversations =
          (_) async => _conversationPage([_conversation(id: 3001, unread: 5)]);
      repository.onUnreadCount = () async => 5;
      repository.onGetOrCreateShipmentConversation = (_) async =>
          DriverChatConversationResult(
            conversation: _conversation(
              id: 3001,
              unread: 1,
              lastMessage: 'newer preview',
            ),
            isCreated: false,
          );

      await provider.loadInitial();
      await provider.refreshUnreadCount();
      await provider.resolveShipmentConversation(3001);

      expect(provider.conversations.single.unreadCount, 1);
      expect(provider.conversations.single.lastMessage, 'newer preview');
      // The badge moved by the same delta, not by a guess.
      expect(provider.unreadCount, 1);
      expect(provider.conversations, hasLength(1));
    });

    test('an invalid shipment id is refused without a request', () async {
      expect(await provider.resolveShipmentConversation(0), isNull);
      expect(await provider.resolveShipmentConversation(-1), isNull);
      expect(repository.resolvedShipmentIds, isEmpty);
    });

    test('a failure returns null and surfaces a safe message', () async {
      repository.onGetOrCreateShipmentConversation =
          (_) async => throw _serverError;

      expect(await provider.resolveShipmentConversation(77), isNull);
      expect(provider.errorMessage, 'chat_server_error');
    });

    test("a late resolution never reaches the next driver", () async {
      final gate = Completer<DriverChatConversationResult>();
      repository.onGetOrCreateShipmentConversation = (_) => gate.future;

      final pending = provider.resolveShipmentConversation(77);
      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete(
        DriverChatConversationResult(
          conversation: _conversation(id: 9001),
          isCreated: true,
        ),
      );

      expect(await pending, isNull);
      expect(provider.conversations, isEmpty);
    });
  });
}
