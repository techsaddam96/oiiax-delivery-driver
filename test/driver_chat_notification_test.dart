// Driver Chat FCM receiving and routing.
//
// The routing decision is pure and tested directly; the behaviour that needs a
// session, a Navigator and providers is driven through the real
// NotificationSystem.navigator() with the storage channels mocked, so what is
// checked is the shipped path rather than a re-implementation of it.

import 'dart:async';

import 'package:blockatie/constants/notification_routes.dart';
import 'package:blockatie/constants/notification_system.dart';
import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/provider/chat/driver_chat_conversation_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/chat/driver_conversation_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

DriverChatConversation _conversation({required int id, int unread = 0}) {
  return DriverChatConversation(
    conversationId: id,
    conversationType: 'shipment_driver',
    title: 'Shipment $id',
    lastMessage: 'Please confirm pickup',
    lastMessageType: 'text',
    unreadCount: unread,
    shipmentId: 7700 + id,
    policyNum: 'BLK-$id',
    shipmentStatusId: 4,
    lastMessageSenderRole: 'admin',
    lastMessageAt: DateTime(2026, 9, 20, 9, 30),
  );
}

DriverChatMessage _incoming(int id, {int conversationId = 3001}) {
  return DriverChatMessage(
    messageId: id,
    conversationId: conversationId,
    senderRole: 'admin',
    senderName: 'Admin / Operations',
    messageType: 'text',
    message: 'message $id',
    isMine: false,
    isRead: false,
    createdAt: DateTime(2026, 9, 20, 9, 30).add(Duration(minutes: id)),
    status: DriverChatMessageStatus.sent,
  );
}

/// The payload shape services/helpers/driver_chat_notifications.php emits.
Map<String, dynamic> _chatPayload({
  Object? conversationId = 3001,
  Object? messageId = 51,
  Object? notificationId = 900,
  Object? shipmentId = 7701,
  String type = 'driver_chat_message',
  Map<String, dynamic> extra = const {},
}) {
  return <String, dynamic>{
    'type': type,
    if (conversationId != null) 'conversation_id': '$conversationId',
    if (messageId != null) 'message_id': '$messageId',
    if (notificationId != null) 'notification_id': '$notificationId',
    if (shipmentId != null) 'shipment_id': '$shipmentId',
    ...extra,
  };
}

class _FakeChatRepository implements DriverChatRepository {
  int unreadCountCalls = 0;
  final List<int> probedConversationIds = <int>[];
  final List<int> requestedAfterIds = <int>[];

  Future<int> Function()? onUnreadCount;
  Future<DriverChatMessagesPage> Function(int conversationId)? onGetMessages;
  Future<DriverChatNewMessagesPage> Function(int afterMessageId)?
      onGetNewMessages;
  Future<DriverChatConversationPage> Function(int page)? onListConversations;

  @override
  Future<int> getUnreadCount({CancelToken? cancelToken}) {
    unreadCountCalls++;
    return onUnreadCount?.call() ?? Future.value(0);
  }

  @override
  Future<DriverChatMessagesPage> getMessages({
    required int conversationId,
    int? beforeMessageId,
    int limit = 30,
    CancelToken? cancelToken,
  }) {
    probedConversationIds.add(conversationId);
    return onGetMessages?.call(conversationId) ??
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
  Future<DriverChatConversationPage> listConversations({
    int page = 1,
    int limit = 15,
    CancelToken? cancelToken,
  }) {
    return onListConversations?.call(page) ??
        Future.value(
          DriverChatConversationPage(
            conversations: const <DriverChatConversation>[],
            pagination: const DriverChatPagination(
              page: 1,
              limit: 15,
              total: 0,
              totalPages: 0,
            ),
          ),
        );
  }

  @override
  Future<DriverChatSendResult> sendMessage({
    required int conversationId,
    required String message,
    required String clientMessageId,
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<DriverChatReadResult> markRead({
    required int conversationId,
    int? lastMessageId,
    CancelToken? cancelToken,
  }) {
    return Future.value(
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
  Future<DriverChatConversationResult> getOrCreateShipmentConversation({
    required int shipmentId,
    CancelToken? cancelToken,
  }) =>
      throw UnimplementedError();
}

/// Records pushed route names.
class _RouteLog extends NavigatorObserver {
  final List<String?> pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Routing decision — pure
  // ---------------------------------------------------------------------------

  group('driver_chat_message resolution', () {
    test('resolves to the chat thread', () {
      final target = resolveDriverNotificationTarget(_chatPayload());

      expect(target, isNotNull);
      expect(
        target!.destination,
        DriverNotificationDestination.chatConversation,
      );
      expect(target.type, 'driver_chat_message');
      expect(target.conversationId, 3001);
      expect(target.messageId, 51);
      expect(target.notificationId, 900);
    });

    test('accepts ints as well as strings', () {
      final target = resolveDriverNotificationTarget(<String, dynamic>{
        'type': 'driver_chat_message',
        'conversation_id': 3001,
        'message_id': 51,
      });

      expect(target?.conversationId, 3001);
      expect(target?.messageId, 51);
    });

    test('an admin thread without a shipment still routes', () {
      final target =
          resolveDriverNotificationTarget(_chatPayload(shipmentId: null));

      expect(
        target?.destination,
        DriverNotificationDestination.chatConversation,
      );
      expect(target?.shipmentId, isNull);
    });

    test('a missing conversation_id is inert', () {
      expect(
        resolveDriverNotificationTarget(_chatPayload(conversationId: null)),
        isNull,
      );
    });

    test('malformed ids are inert', () {
      for (final bad in <Object>[0, -1, 'abc', '', '  ', 1.5, 'null']) {
        expect(
          resolveDriverNotificationTarget(_chatPayload(conversationId: bad)),
          isNull,
          reason: 'conversation_id=$bad must not route',
        );
      }
    });

    test('an array or object where a scalar belongs is inert', () {
      expect(
        resolveDriverNotificationTarget(<String, dynamic>{
          'type': 'driver_chat_message',
          'conversation_id': [3001],
        }),
        isNull,
      );
      expect(
        resolveDriverNotificationTarget(<String, dynamic>{
          'type': 'driver_chat_message',
          'conversation_id': {'id': 3001},
        }),
        isNull,
      );
    });

    test('a forged driver_id in the payload changes nothing', () {
      final clean = resolveDriverNotificationTarget(_chatPayload());
      final forged = resolveDriverNotificationTarget(
        _chatPayload(extra: const {'driver_id': '999', 'user_id': '999'}),
      );

      // The resolver has no driver field at all, and the key is unchanged, so
      // there is nothing a forged id could steer.
      expect(forged!.conversationId, clean!.conversationId);
      expect(forged.dedupeKey, clean.dedupeKey);
    });

    test('shipment_id is carried but is not what selects the screen', () {
      final target = resolveDriverNotificationTarget(
        _chatPayload(conversationId: 3001, shipmentId: 999999),
      );

      expect(target?.conversationId, 3001);
      expect(target?.shipmentId, 999999);
      // Routing is by conversation, never by shipment.
      expect(
        target?.destination,
        DriverNotificationDestination.chatConversation,
      );
    });

    test('an unsupported type is still ignored', () {
      expect(
        resolveDriverNotificationTarget(_chatPayload(type: 'chat')),
        isNull,
      );
      expect(
        resolveDriverNotificationTarget(_chatPayload(type: 'client_chat')),
        isNull,
      );
    });
  });

  group('driver_chat_message de-duplication', () {
    test('the same notification yields a stable key', () {
      final first = resolveDriverNotificationTarget(_chatPayload())!;
      final second = resolveDriverNotificationTarget(_chatPayload())!;

      expect(first.dedupeKey, second.dedupeKey);
    });

    test('different messages stay distinct', () {
      final first = resolveDriverNotificationTarget(
        _chatPayload(messageId: 51, notificationId: 900),
      )!;
      final second = resolveDriverNotificationTarget(
        _chatPayload(messageId: 52, notificationId: 901),
      )!;

      // A later message in the same thread must still be routable.
      expect(first.dedupeKey, isNot(second.dedupeKey));
    });

    test('falls back to message_id when the server sent no notification_id',
        () {
      final target = resolveDriverNotificationTarget(
        _chatPayload(notificationId: null, messageId: 51),
      )!;

      expect(target.dedupeKey, contains('51'));
    });

    test('falls back to the thread when neither id is present', () {
      final target = resolveDriverNotificationTarget(
        _chatPayload(notificationId: null, messageId: null),
      )!;

      expect(target.dedupeKey, 'driver_chat:conversation:3001');
    });

    test('a chat key never collides with a shipment key', () {
      final chat = resolveDriverNotificationTarget(
        _chatPayload(conversationId: 5, notificationId: null, messageId: null),
      )!;
      final shipment = resolveDriverNotificationTarget(<String, dynamic>{
        'type': 'shipment_assigned',
        'shipment_id': '5',
      })!;

      expect(chat.dedupeKey, isNot(shipment.dedupeKey));
    });
  });

  group('existing routes are unaffected', () {
    test('settlement still resolves', () {
      final target = resolveDriverNotificationTarget(<String, dynamic>{
        'type': 'driver_settlement',
        'settlement_id': '44',
      });

      expect(
        target?.destination,
        DriverNotificationDestination.settlementDetails,
      );
      expect(target?.settlementId, 44);
    });

    test('every assigned-shipment type still resolves', () {
      for (final type in DriverNotificationTypes.assignedShipment) {
        final target = resolveDriverNotificationTarget(<String, dynamic>{
          'type': type,
          'shipment_id': '77',
        });
        expect(
          target?.destination,
          DriverNotificationDestination.shipmentDetails,
          reason: '$type must still route',
        );
      }
    });

    test('available_shipment still resolves', () {
      final target = resolveDriverNotificationTarget(<String, dynamic>{
        'type': 'available_shipment',
      });

      expect(
        target?.destination,
        DriverNotificationDestination.availableShipments,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Foreground signal handling
  // ---------------------------------------------------------------------------

  group('foreground signal', () {
    late _FakeChatRepository repository;
    late DriverChatConversationsProvider conversations;

    setUp(() {
      repository = _FakeChatRepository();
      conversations = DriverChatConversationsProvider(repository: repository);
      addTearDown(conversations.dispose);
    });

    test('refreshes the unread count from the server', () async {
      repository.onUnreadCount = () async => 4;

      await conversations.handleChatSignal(3001);

      expect(repository.unreadCountCalls, 1);
      expect(conversations.globalUnreadCount, 4);
    });

    test('asks the open thread for newer messages', () async {
      var fetched = 0;
      conversations.registerOpenConversation(3001, () async => fetched++);

      await conversations.handleChatSignal(3001);

      expect(fetched, 1);
    });

    test('a signal for another thread does not disturb the open one',
        () async {
      var fetched = 0;
      conversations.registerOpenConversation(3001, () async => fetched++);

      await conversations.handleChatSignal(4002);

      expect(fetched, 0);
      // The badge is still re-read: the unread total is global.
      expect(repository.unreadCountCalls, 1);
    });

    test('a closed thread is not asked for anything', () async {
      var fetched = 0;
      conversations.registerOpenConversation(3001, () async => fetched++);
      conversations.unregisterOpenConversation(3001);

      await conversations.handleChatSignal(3001);

      expect(fetched, 0);
    });

    test('a stale unregister cannot silence the thread that replaced it',
        () async {
      var newer = 0;
      conversations.registerOpenConversation(3001, () async {});
      conversations.registerOpenConversation(4002, () async => newer++);
      // The first page disposes after the second registered.
      conversations.unregisterOpenConversation(3001);

      await conversations.handleChatSignal(4002);

      expect(newer, 1);
    });

    test('a malformed conversation id is inert', () async {
      await conversations.handleChatSignal(0);
      await conversations.handleChatSignal(-1);

      expect(repository.unreadCountCalls, 0);
    });

    test('a session change clears the open registration', () async {
      var fetched = 0;
      conversations.registerOpenConversation(3001, () async => fetched++);

      UserSessionState.reset(SessionResetReason.accountChanged);
      await conversations.handleChatSignal(3001);

      expect(conversations.openConversationId, isNull);
      expect(fetched, 0);
    });
  });

  group('ownership probe', () {
    late _FakeChatRepository repository;
    late DriverChatConversationsProvider conversations;

    setUp(() {
      repository = _FakeChatRepository();
      conversations = DriverChatConversationsProvider(repository: repository);
      addTearDown(conversations.dispose);
    });

    test('a thread the server accepts may be opened', () async {
      expect(await conversations.canOpenNotifiedConversation(3001), isTrue);
      expect(repository.probedConversationIds, [3001]);
    });

    test('an unauthorized thread may not be opened', () async {
      repository.onGetMessages = (_) async => throw const ChatAuthorizationExceptionStub();

      expect(await conversations.canOpenNotifiedConversation(3001), isFalse);
    });

    test('a nonexistent thread may not be opened', () async {
      // The backend answers identically for both, and so does this.
      repository.onGetMessages = (_) async => throw const ChatAuthorizationExceptionStub();

      expect(await conversations.canOpenNotifiedConversation(999999), isFalse);
    });

    test('a malformed id is refused without a request', () async {
      expect(await conversations.canOpenNotifiedConversation(0), isFalse);
      expect(await conversations.canOpenNotifiedConversation(-5), isFalse);
      expect(repository.probedConversationIds, isEmpty);
    });

    test('a late answer from the previous driver is discarded', () async {
      final gate = Completer<DriverChatMessagesPage>();
      repository.onGetMessages = (_) => gate.future;

      final pending = conversations.canOpenNotifiedConversation(3001);
      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete(
        const DriverChatMessagesPage(
          messages: <DriverChatMessage>[],
          hasMore: false,
        ),
      );

      expect(await pending, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Signal + poll must not double a message
  // ---------------------------------------------------------------------------

  group('signal and poll together', () {
    test('one message arrives once however many times it is fetched',
        () async {
      final repository = _FakeChatRepository();
      final conversations =
          DriverChatConversationsProvider(repository: repository);
      addTearDown(conversations.dispose);

      final thread = DriverChatConversationProvider(
        conversationId: 3001,
        repository: repository,
        pollingInterval: const Duration(milliseconds: 40),
      );
      addTearDown(thread.dispose);

      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );
      // Both the poll and the signal see the same stored message.
      repository.onGetNewMessages = (after) async => DriverChatNewMessagesPage(
            messages: [_incoming(11)],
            latestMessageId: 11,
            hasMore: false,
          );

      await thread.loadInitial();
      conversations.registerOpenConversation(3001, thread.pollOnce);

      // A poll and a push signal for the same message, back to back.
      await thread.pollOnce();
      await conversations.handleChatSignal(3001);
      await conversations.handleChatSignal(3001);

      expect(
        thread.messages.map((m) => m.identityKey).toList(),
        ['server:10', 'server:11'],
      );
      expect(thread.messages.where((m) => m.messageId == 11).length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Tap routing, through the real NotificationSystem
  // ---------------------------------------------------------------------------

  group('notification tap', () {
    late _FakeChatRepository repository;
    late DriverChatConversationsProvider conversations;
    late DriverChatLauncherProvider launcher;
    late _RouteLog routes;

    setUpAll(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          switch (call.method) {
            case 'read':
              final key = (call.arguments as Map)['key'] as String?;
              if (key == 'driver_api_key') return 'key-driver-a';
              if (key == 'driver_session_id') return '901';
              return null;
            case 'readAll':
              return <String, String>{
                'driver_api_key': 'key-driver-a',
                'driver_session_id': '901',
              };
            case 'containsKey':
              return true;
            default:
              return null;
          }
        },
      );
    });

    setUp(() {
      repository = _FakeChatRepository();
      conversations = DriverChatConversationsProvider(repository: repository);
      launcher = DriverChatLauncherProvider(
        sessionReader: () async =>
            const DriverSession(apiKey: 'key-driver-a', driverId: '901'),
      );
      routes = _RouteLog();
      NotificationSystem.resetDriverSessionState();
    });

    tearDown(() {
      conversations.dispose();
      launcher.dispose();
      NotificationSystem.resetDriverSessionState();
    });

    Widget app() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<DriverChatConversationsProvider>.value(
            value: conversations,
          ),
          ChangeNotifierProvider<DriverChatLauncherProvider>.value(
            value: launcher,
          ),
        ],
        child: MaterialApp(
          navigatorKey: Nav.key,
          navigatorObservers: [routes],
          home: const Scaffold(body: Center(child: Text('Driver home'))),
        ),
      );
    }

    Future<void> deliverTap(WidgetTester tester, Map<String, dynamic> data,
        {int settleMs = 400}) async {
      unawaited(NotificationSystem().navigator(data: data));
      await tester.pump();
      await tester.pump(Duration(milliseconds: settleMs));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the exact conversation from the payload',
        (tester) async {
      repository.onListConversations = (_) async => DriverChatConversationPage(
            conversations: [_conversation(id: 3001)],
            pagination: const DriverChatPagination(
              page: 1,
              limit: 15,
              total: 1,
              totalPages: 1,
            ),
          );
      await conversations.loadInitial();

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await deliverTap(tester, _chatPayload(conversationId: 3001));

      expect(routes.pushed, ['driver-chat/conversation/3001']);
      expect(find.byType(DriverConversationPage), findsOneWidget);
      // Ownership was proven against the API before anything opened.
      expect(repository.probedConversationIds, contains(3001));
    });

    testWidgets('a repeated delivery routes once', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      final payload = _chatPayload(conversationId: 3001);
      await deliverTap(tester, payload);
      await deliverTap(tester, payload);
      await deliverTap(tester, payload);

      expect(routes.pushed, ['driver-chat/conversation/3001']);
    });

    testWidgets('an unauthorized conversation opens nothing', (tester) async {
      repository.onGetMessages =
          (_) async => throw const ChatAuthorizationExceptionStub();

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await deliverTap(tester, _chatPayload(conversationId: 4444));

      expect(routes.pushed, isEmpty);
      expect(find.byType(DriverConversationPage), findsNothing);
    });

    testWidgets('a malformed payload opens nothing', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await deliverTap(tester, _chatPayload(conversationId: null));
      await deliverTap(tester, _chatPayload(conversationId: 'abc'));
      await deliverTap(tester, _chatPayload(type: 'something_else'));

      expect(routes.pushed, isEmpty);
      expect(repository.probedConversationIds, isEmpty);
    });

    testWidgets('a session change before the probe answers opens nothing',
        (tester) async {
      final gate = Completer<DriverChatMessagesPage>();
      repository.onGetMessages = (_) => gate.future;

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      unawaited(
        NotificationSystem().navigator(data: _chatPayload(conversationId: 3001)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Driver A logs out, Driver B signs in, then A's answer lands.
      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete(
        const DriverChatMessagesPage(
          messages: <DriverChatMessage>[],
          hasMore: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(routes.pushed, isEmpty);
      expect(find.byType(DriverConversationPage), findsNothing);
    });

    testWidgets('the thread already on screen is not pushed again',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await deliverTap(tester, _chatPayload(conversationId: 3001));
      expect(routes.pushed, ['driver-chat/conversation/3001']);

      // A second notification for a different message in the same thread.
      await deliverTap(
        tester,
        _chatPayload(conversationId: 3001, messageId: 52, notificationId: 901),
      );

      expect(routes.pushed, ['driver-chat/conversation/3001']);
      expect(find.byType(DriverConversationPage), findsOneWidget);
    });

    testWidgets('a different thread still opens while one is on screen',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await deliverTap(tester, _chatPayload(conversationId: 3001));
      await deliverTap(
        tester,
        _chatPayload(conversationId: 4002, messageId: 60, notificationId: 910),
      );

      expect(routes.pushed, [
        'driver-chat/conversation/3001',
        'driver-chat/conversation/4002',
      ]);
    });

    testWidgets('the badge is re-read from the server after opening',
        (tester) async {
      repository.onUnreadCount = () async => 2;

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final before = repository.unreadCountCalls;

      await deliverTap(tester, _chatPayload(conversationId: 3001));

      expect(repository.unreadCountCalls, greaterThan(before));
      expect(conversations.globalUnreadCount, 2);
    });

    testWidgets('a tap arriving before the Navigator exists is not lost',
        (tester) async {
      // Nothing is mounted yet: this is the terminated-launch shape.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      unawaited(
        NotificationSystem().navigator(data: _chatPayload(conversationId: 3001)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // The app finishes starting while the tap is still waiting.
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(routes.pushed, contains('driver-chat/conversation/3001'));
    });
  });
}

/// Stands in for the 403 the Chat API returns for a conversation that is not
/// this driver's — and for one that does not exist, which answers identically.
class ChatAuthorizationExceptionStub implements Exception {
  const ChatAuthorizationExceptionStub();
}
