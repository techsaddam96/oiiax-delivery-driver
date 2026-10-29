// Widget tests for the Driver Chat screens.
//
// Every test drives the real providers over a fake transport, so what is being
// checked is the screen's behaviour against the actual state layer rather than
// a mock of it.

import 'dart:async';

import 'package:blockatie/models/chat/chat_exception.dart';
import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/provider/chat/driver_chat_conversation_provider.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/chat/driver_conversation_page.dart';
import 'package:blockatie/views/pages/chat/driver_conversations_page.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_header.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_chat_message_bubble.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_conversation_tile.dart';
import 'package:blockatie/views/pages/chat/widgets/driver_shipment_chat_action.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

final DateTime _today = DateTime.now();
final DateTime _yesterday = _today.subtract(const Duration(days: 1));

DriverChatConversation _conversation({
  required int id,
  int unread = 0,
  int? shipmentId,
  String? policyNum,
  String lastMessage = 'Please confirm pickup',
  String? lastSenderRole = 'admin',
  String title = 'Operations',
}) {
  return DriverChatConversation(
    conversationId: id,
    conversationType: shipmentId == null ? 'admin_driver' : 'shipment_driver',
    title: title,
    lastMessage: lastMessage,
    lastMessageType: 'text',
    unreadCount: unread,
    shipmentId: shipmentId,
    policyNum: policyNum,
    shipmentStatusId: shipmentId == null ? null : 4,
    lastMessageSenderRole: lastSenderRole,
    lastMessageAt: _today,
  );
}

DriverChatConversationPage _page(
  List<DriverChatConversation> conversations, {
  int page = 1,
  int totalPages = 1,
}) {
  return DriverChatConversationPage(
    conversations: conversations,
    pagination: DriverChatPagination(
      page: page,
      limit: 15,
      total: conversations.length,
      totalPages: totalPages,
    ),
  );
}

DriverChatMessage _incoming(
  int id, {
  String text = 'Please confirm pickup',
  DateTime? at,
  bool isRead = false,
}) {
  return DriverChatMessage(
    messageId: id,
    conversationId: 3001,
    senderRole: 'admin',
    senderName: 'Admin / Operations',
    messageType: 'text',
    message: text,
    isMine: false,
    isRead: isRead,
    createdAt: at ?? _today.subtract(Duration(minutes: 100 - id)),
    status: DriverChatMessageStatus.sent,
  );
}

DriverChatMessage _mine(int id, String clientMessageId, {String text = 'On my way'}) {
  return DriverChatMessage(
    messageId: id,
    conversationId: 3001,
    senderRole: 'driver',
    senderName: '',
    messageType: 'text',
    message: text,
    isMine: true,
    isRead: false,
    createdAt: _today,
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
        Future.value(_page(const <DriverChatConversation>[]));
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
    return onSendMessage?.call(message, clientMessageId) ??
        Future.value(
          DriverChatSendResult(
            message: _mine(500, clientMessageId, text: message),
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

// -----------------------------------------------------------------------------
// Harness
// -----------------------------------------------------------------------------

/// Records the routes the chat screens push, so navigation can be asserted
/// without building the destination screen.
class _RouteLog extends NavigatorObserver {
  final List<String?> pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}

Widget _host({

  required Widget child,
  required DriverChatConversationsProvider conversations,
  Locale locale = const Locale('en'),
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) {
  return ChangeNotifierProvider<DriverChatConversationsProvider>.value(
    value: conversations,
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: observers,
      home: child,
    ),
  );
}

/// A common phone width, so layout problems show up as overflow errors.
Future<void> _setPhoneSize(WidgetTester tester, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChatRepository repository;
  late DriverChatConversationsProvider conversations;

  setUp(() {
    repository = _FakeChatRepository();
    conversations = DriverChatConversationsProvider(repository: repository);
  });

  tearDown(() {
    conversations.dispose();
  });

  // ---------------------------------------------------------------------------
  // Conversations page
  // ---------------------------------------------------------------------------

  group('Conversations page', () {
    testWidgets('shows a skeleton while loading, then the list', (tester) async {
      await _setPhoneSize(tester);
      final gate = Completer<DriverChatConversationPage>();
      repository.onListConversations = (_) => gate.future;

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pump();

      expect(find.byType(DriverConversationTile), findsNothing);

      gate.complete(_page([
        _conversation(id: 3001, title: 'Operations'),
        _conversation(
          id: 3002,
          title: 'Shipment BLK-0077',
          shipmentId: 77,
          policyNum: 'BLK-0077',
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(DriverConversationTile), findsNWidgets(2));
      expect(find.text('Operations'), findsOneWidget);
      expect(find.text('Shipment: BLK-0077'), findsOneWidget);
    });

    testWidgets('shows the empty state when there is nothing', (tester) async {
      await _setPhoneSize(tester);

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(find.byType(DriverConversationTile), findsNothing);
    });

    testWidgets('shows an error with a retry that reloads', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (_) async => throw _serverError;

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Could not load conversations'), findsOneWidget);

      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001)]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverConversationTile), findsOneWidget);
    });

    testWidgets('renders an exact unread count up to 99', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001, unread: 7)]);

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(DriverChatUnreadBadge, '7'), findsOneWidget);
    });

    testWidgets('collapses an unread count above 99 to 99+', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001, unread: 250)]);
      repository.onUnreadCount = () async => 250;

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // The tile badge and the header badge both collapse.
      expect(find.text('99+'), findsNWidgets(2));
      expect(find.text('250'), findsNothing);
    });

    testWidgets('a boundary count of 99 still shows the number', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001, unread: 99)]);

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(DriverChatUnreadBadge, '99'), findsOneWidget);
    });

    testWidgets('tapping a conversation opens that thread', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (_) async => _page([
            _conversation(
              id: 3001,
              title: 'Operations',
              shipmentId: 77,
              policyNum: 'BLK-0077',
            ),
          ]);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: DriverConversationsPage(repository: repository),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DriverConversationTile));
      await tester.pumpAndSettle();

      expect(find.byType(DriverConversationPage), findsOneWidget);
      expect(find.text('Please confirm pickup'), findsOneWidget);
      // The shipment shortcut is offered because this thread has one.
      expect(find.text('Shipment details'), findsOneWidget);
    });

    testWidgets('pages replace each other rather than stacking', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (page) async => _page(
            [_conversation(id: page == 1 ? 3001 : 3002, title: 'Page $page')],
            page: page,
            totalPages: 2,
          );

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 1 / 2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 1'), findsNothing);
      expect(find.byType(DriverConversationTile), findsOneWidget);
    });

    testWidgets('a single page hides the pager', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001)]);

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('lays out in Arabic without overflowing', (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (_) async => _page([
            _conversation(
              id: 3001,
              title: 'العمليات',
              unread: 3,
              lastMessage: 'يرجى تأكيد الاستلام',
              shipmentId: 77,
              policyNum: 'BLK-0077',
            ),
          ]);

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('المحادثات'), findsOneWidget);
      expect(find.text('العمليات'), findsOneWidget);
      expect(find.text('الشحنة: BLK-0077'), findsOneWidget);
      expect(
        Directionality.of(
          tester.element(find.byType(DriverConversationTile)),
        ),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('names the driver in a preview of their own message',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (_) async => _page([
            _conversation(
              id: 3001,
              lastMessage: 'On my way',
              lastSenderRole: 'driver',
            ),
          ]);

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.text('You: On my way'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Conversation page
  // ---------------------------------------------------------------------------

  group('Conversation page', () {
    Widget conversationPage({int? shipmentId, String? policyNum}) {
      return DriverConversationPage(
        conversationId: 3001,
        title: 'Operations',
        shipmentId: shipmentId,
        policyNum: policyNum,
        repository: repository,
      );
    }

    testWidgets('renders messages oldest first', (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [
              _incoming(10, text: 'First'),
              _incoming(11, text: 'Second'),
              _incoming(12, text: 'Third'),
            ],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // Oldest at the top, newest at the bottom.
      final firstY = tester.getTopLeft(find.text('First')).dy;
      final secondY = tester.getTopLeft(find.text('Second')).dy;
      final thirdY = tester.getTopLeft(find.text('Third')).dy;
      expect(firstY, lessThan(secondY));
      expect(secondY, lessThan(thirdY));
      expect(find.byType(DriverChatMessageBubble), findsNWidgets(3));
    });

    testWidgets('renders an Arabic message unchanged', (tester) async {
      await _setPhoneSize(tester);
      const arabic = 'يرجى تأكيد الاستلام من المتجر 👍';
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10, text: arabic)],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(find.text(arabic), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('groups messages under Today and Yesterday', (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [
              _incoming(10, at: _yesterday, text: 'Old one'),
              _incoming(11, at: _yesterday, text: 'Old two'),
              _incoming(12, at: _today, text: 'New one'),
            ],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // One separator per day, never one per message.
      expect(find.byType(DriverChatDateSeparator), findsNWidgets(2));
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('distinguishes outgoing from incoming', (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [
              _incoming(10, text: 'From admin'),
              _mine(11, 'driver-chat-a', text: 'From me'),
            ],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      final incomingBubble = tester.widget<DriverChatMessageBubble>(
        find.ancestor(
          of: find.text('From admin'),
          matching: find.byType(DriverChatMessageBubble),
        ),
      );
      final mineBubble = tester.widget<DriverChatMessageBubble>(
        find.ancestor(
          of: find.text('From me'),
          matching: find.byType(DriverChatMessageBubble),
        ),
      );

      expect(incomingBubble.message.isMine, isFalse);
      expect(mineBubble.message.isMine, isTrue);
      // The sender's name only appears on incoming messages.
      expect(find.text('Admin / Operations'), findsOneWidget);
      // A stored outgoing message shows a delivery tick.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('shows a message as sending, then sent', (tester) async {
      await _setPhoneSize(tester);
      final gate = Completer<DriverChatSendResult>();
      repository.onSendMessage = (_, __) => gate.future;

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'On my way');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(find.text('On my way'), findsOneWidget);
      final pending = tester
          .widget<DriverChatMessageBubble>(find.byType(DriverChatMessageBubble));
      expect(pending.message.isPending, isTrue);

      gate.complete(
        DriverChatSendResult(
          message: _mine(500, repository.sentClientMessageIds.single),
          isDuplicate: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DriverChatMessageBubble), findsOneWidget);
      final sent = tester
          .widget<DriverChatMessageBubble>(find.byType(DriverChatMessageBubble));
      expect(sent.message.status, DriverChatMessageStatus.sent);
    });

    testWidgets('shows a failed message with a retry action', (tester) async {
      await _setPhoneSize(tester);
      repository.onSendMessage = (_, __) async => throw _serverError;

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'On my way');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('On my way'), findsOneWidget);
    });

    testWidgets('retry reuses the original id and adds no second bubble',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onSendMessage = (_, __) async => throw _serverError;

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'On my way');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final originalId = repository.sentClientMessageIds.single;

      repository.onSendMessage = (message, clientMessageId) async =>
          DriverChatSendResult(
            message: _mine(500, clientMessageId, text: message),
            isDuplicate: false,
          );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.sentClientMessageIds, [originalId, originalId]);
      expect(find.byType(DriverChatMessageBubble), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('refuses an empty composer', (tester) async {
      await _setPhoneSize(tester);

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '    ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(repository.sentClientMessageIds, isEmpty);
      expect(find.byType(DriverChatMessageBubble), findsNothing);
      expect(find.text('Write a message first.'), findsWidgets);
    });

    testWidgets('composer grows with a multiline message', (tester) async {
      await _setPhoneSize(tester);

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.minLines, 1);
      expect(field.maxLines, 5);
      expect(field.keyboardType, TextInputType.multiline);

      final singleLineHeight = tester.getSize(find.byType(TextField)).height;
      await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThan(singleLineHeight),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays usable with the keyboard open', (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: List.generate(12, (index) => _incoming(index + 1)),
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // Simulate the on-screen keyboard claiming the bottom of the screen.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final composer = tester.getRect(find.byType(TextField));
      final screenHeight = tester.getSize(find.byType(Scaffold).first).height;
      // The composer must remain on screen, above the keyboard inset.
      expect(composer.bottom, lessThanOrEqualTo(screenHeight));
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks incoming messages read and updates the unread state',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001, unread: 2)]);
      repository.onUnreadCount = () async => 2;
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10), _incoming(11)],
            hasMore: false,
          );

      await conversations.loadInitial();
      await conversations.refreshUnreadCount();
      expect(conversations.unreadCount, 2);

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(repository.markReadCursors, [11]);
      expect(conversations.conversations.single.unreadCount, 0);
      expect(conversations.unreadCount, 0);
    });

    testWidgets('does not re-mark a thread that has not moved', (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );
      repository.onGetNewMessages = (after) async => DriverChatNewMessagesPage(
            messages: const <DriverChatMessage>[],
            latestMessageId: after,
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();
      expect(repository.markReadCursors, [10]);

      // Several idle polls must not each fire a mark_read.
      final provider = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(provider, isNotNull);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();

      expect(repository.markReadCursors, [10]);
    });

    testWidgets('shows an error with retry when the thread cannot load',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => throw _serverError;

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);

      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverChatMessageBubble), findsOneWidget);
    });

    testWidgets('hides the shipment shortcut on an admin thread',
        (tester) async {
      await _setPhoneSize(tester);

      await tester.pumpWidget(_host(
        child: conversationPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Shipment details'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Older messages and scrolling
  // ---------------------------------------------------------------------------

  group('Older messages', () {
    testWidgets('prepends older messages and keeps the reading position',
        (tester) async {
      await _setPhoneSize(tester);
      // The older page is held open so the anchor message can be measured at
      // the exact moment the request is in flight, then measured again after
      // twenty messages have been inserted above it.
      final gate = Completer<DriverChatMessagesPage>();
      repository.onGetMessages = (before) {
        if (before == null) {
          return Future.value(
            DriverChatMessagesPage(
              messages: List.generate(
                20,
                (index) => _incoming(100 + index, text: 'Recent $index'),
              ),
              hasMore: true,
              nextBeforeMessageId: 100,
            ),
          );
        }
        return gate.future;
      };

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // The thread opens at the newest message, which is offset zero in a
      // reversed list.
      var position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.pixels, position.minScrollExtent);
      expect(find.text('Recent 19'), findsOneWidget);

      // Drag towards the start of the thread to trigger the older page.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
      await tester.pump();
      expect(repository.requestedBeforeIds, [null, 100]);

      // Let the overscroll bounce finish before measuring: the request fires
      // mid-gesture, so the list is still settling for a few frames after it.
      // pumpAndSettle cannot be used here — the "loading older" spinner never
      // stops animating.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      final anchorBefore = tester.getTopLeft(find.text('Recent 2')).dy;

      gate.complete(
        DriverChatMessagesPage(
          messages: List.generate(
            20,
            (index) => _incoming(50 + index, text: 'Older $index'),
          ),
          hasMore: false,
        ),
      );
      await tester.pumpAndSettle();

      // Same message, same place on screen: the list grew upwards without
      // moving what the driver was reading.
      expect(
        (tester.getTopLeft(find.text('Recent 2')).dy - anchorBefore).abs(),
        lessThan(4),
      );

      // And it neither jumped to the start of the thread nor back to the end.
      position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.pixels, greaterThan(0));
      expect(position.pixels, lessThan(position.maxScrollExtent));

      // The older page really did land in the thread: it sits just above the
      // viewport, which is exactly why the position had to be corrected.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('Older 19'), findsOneWidget);
    });

    testWidgets('does not issue two older requests at once', (tester) async {
      await _setPhoneSize(tester);
      final gate = Completer<DriverChatMessagesPage>();
      repository.onGetMessages = (before) {
        if (before == null) {
          return Future.value(
            DriverChatMessagesPage(
              messages: List.generate(
                20,
                (index) => _incoming(100 + index, text: 'Recent $index'),
              ),
              hasMore: true,
              nextBeforeMessageId: 100,
            ),
          );
        }
        return gate.future;
      };

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      final listFinder = find.byType(Scrollable).first;
      await tester.drag(listFinder, const Offset(0, 700));
      await tester.pump();
      await tester.drag(listFinder, const Offset(0, 300));
      await tester.pump();

      // One initial load plus exactly one older request, however many scroll
      // events fired.
      expect(repository.requestedBeforeIds, [null, 100]);

      gate.complete(
        DriverChatMessagesPage(
          messages: [_incoming(50, text: 'Older')],
          hasMore: false,
        ),
      );
      await tester.pumpAndSettle();
    });
  });

  // ---------------------------------------------------------------------------
  // Polling and the new-messages indicator
  // ---------------------------------------------------------------------------

  group('Polling', () {
    testWidgets('merges a polled message once and auto-scrolls at the bottom',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10, text: 'First')],
            hasMore: false,
          );
      repository.onGetNewMessages = (after) async => DriverChatNewMessagesPage(
            messages: [_incoming(11, text: 'Polled')],
            latestMessageId: 11,
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // Two polls deliver the same message; it must still appear once.
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();

      expect(find.text('Polled'), findsOneWidget);
      expect(find.byType(DriverChatMessageBubble), findsNWidgets(2));
      // Already at the newest message, so no catch-up button is needed.
      expect(find.text('New messages'), findsNothing);
    });

    testWidgets('offers a catch-up button when reading older messages',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: List.generate(
              25,
              (index) => _incoming(100 + index, text: 'Message $index'),
            ),
            hasMore: false,
          );
      repository.onGetNewMessages = (after) async => DriverChatNewMessagesPage(
            messages: after < 200
                ? [_incoming(200, text: 'Fresh news')]
                : const <DriverChatMessage>[],
            latestMessageId: 200,
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();

      // Scroll well away from the newest message.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();

      expect(find.text('New messages'), findsOneWidget);

      await tester.tap(find.text('New messages'));
      await tester.pumpAndSettle();

      expect(find.text('New messages'), findsNothing);
      expect(find.text('Fresh news'), findsOneWidget);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      // Parked on the newest message.
      expect(position.pixels, position.minScrollExtent);
    });

    testWidgets('stops polling once the page is disposed', (tester) async {
      await _setPhoneSize(tester);

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();

      final polledWhileOpen = repository.requestedAfterIds.length;
      expect(polledWhileOpen, greaterThan(0));

      await tester.pumpWidget(_host(
        child: const SizedBox.shrink(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 40));
      await tester.pumpAndSettle();

      expect(repository.requestedAfterIds.length, polledWhileOpen);
    });
  });

  // ---------------------------------------------------------------------------
  // Session safety
  // ---------------------------------------------------------------------------

  group('Session safety', () {
    testWidgets('a session change clears the thread and stops polling',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10, text: 'Driver A message')],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Driver A message'), findsOneWidget);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      final polledBefore = repository.requestedAfterIds.length;

      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pump();
      await tester.pump();

      expect(find.text('Driver A message'), findsNothing);
      expect(find.byType(DriverChatMessageBubble), findsNothing);

      await tester.pump(const Duration(seconds: 40));
      await tester.pump();
      expect(repository.requestedAfterIds.length, polledBefore);
    });

    testWidgets('a session change clears the conversation list and badge',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (_) async => _page([
            _conversation(id: 3001, title: 'Driver A thread', unread: 4),
          ]);
      repository.onUnreadCount = () async => 4;

      await tester.pumpWidget(_host(
        child: const DriverConversationsPage(),
        conversations: conversations,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Driver A thread'), findsOneWidget);

      UserSessionState.reset(SessionResetReason.logout);
      await tester.pump();
      await tester.pump();

      expect(find.text('Driver A thread'), findsNothing);
      expect(conversations.unreadCount, 0);
      expect(find.byType(DriverConversationTile), findsNothing);
    });

    testWidgets("a late reply never lands in the next driver's screen",
        (tester) async {
      await _setPhoneSize(tester);
      final gate = Completer<DriverChatMessagesPage>();
      repository.onGetMessages = (_) => gate.future;

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Operations',
          repository: repository,
        ),
        conversations: conversations,
      ));
      await tester.pump();

      UserSessionState.reset(SessionResetReason.invalidSession);
      gate.complete(
        DriverChatMessagesPage(
          messages: [_incoming(10, text: 'Belongs to driver A')],
          hasMore: false,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Belongs to driver A'), findsNothing);
    });
  });
  // ---------------------------------------------------------------------------
  // Shipment linkage
  // ---------------------------------------------------------------------------

  group('Shipment linkage', () {
    testWidgets('the shipment shortcut pushes the shipment screen',
        (tester) async {
      await _setPhoneSize(tester);
      final routes = _RouteLog();
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: DriverConversationPage(
          conversationId: 3001,
          title: 'Shipment BLK-0077',
          shipmentId: 77,
          policyNum: 'BLK-0077',
          repository: repository,
        ),
        conversations: conversations,
        observers: [routes],
      ));
      await tester.pumpAndSettle();
      routes.pushed.clear();

      // Not pumped afterwards on purpose: the destination screen is the real
      // shipment page and needs the whole shipment provider tree. What this
      // asserts is the linkage — that the tap pushes that route.
      await tester.tap(find.text('Shipment details'));

      expect(routes.pushed, ['driver-chat/shipment']);
    });

    testWidgets('leaving the thread for the shipment pauses polling',
        (tester) async {
      await _setPhoneSize(tester);
      late DriverChatConversationProvider provider;
      repository.onGetMessages = (_) async => DriverChatMessagesPage(
            messages: [_incoming(10)],
            hasMore: false,
          );

      await tester.pumpWidget(_host(
        child: Builder(
          builder: (context) => DriverConversationPage(
            conversationId: 3001,
            title: 'Shipment BLK-0077',
            shipmentId: 77,
            policyNum: 'BLK-0077',
            repository: repository,
          ),
        ),
        conversations: conversations,
        observers: [_RouteLog()],
      ));
      await tester.pumpAndSettle();

      provider = tester
          .element(find.byType(DriverChatMessageBubble))
          .read<DriverChatConversationProvider>();
      expect(provider.isPolling, isTrue);

      await tester.tap(find.text('Shipment details'));

      expect(provider.isPolling, isFalse);
      expect(provider.isPollingPaused, isTrue);
    });

    testWidgets('the same thread is not pushed twice', (tester) async {
      await _setPhoneSize(tester);
      final routes = _RouteLog();
      repository.onListConversations =
          (_) async => _page([_conversation(id: 3001, title: 'Operations')]);

      await tester.pumpWidget(_host(
        child: DriverConversationsPage(repository: repository),
        conversations: conversations,
        observers: [routes],
      ));
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await tester.tap(find.byType(DriverConversationTile));
      await tester.pumpAndSettle();
      expect(routes.pushed, ['driver-chat/conversation/3001']);

      // The tile is now behind the thread; opening it again from the same
      // route must not stack a second copy.
      await DriverChatNavigation.openConversation(
        tester.element(find.byType(DriverConversationPage)),
        conversation: _conversation(id: 3001, title: 'Operations'),
        repository: repository,
      );
      await tester.pumpAndSettle();

      expect(routes.pushed, ['driver-chat/conversation/3001']);
    });
  });

  // ---------------------------------------------------------------------------
  // Layout at common phone widths
  // ---------------------------------------------------------------------------

  group('Phone widths', () {
    // Small Android, iPhone 14/15, and a large handset.
    const sizes = <Size>[
      Size(360, 640),
      Size(390, 844),
      Size(430, 932),
    ];

    for (final size in sizes) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets(
            'both screens fit ${size.width.toInt()}x${size.height.toInt()} '
            'in ${locale.languageCode}', (tester) async {
          await _setPhoneSize(
            tester,
            size: Size(size.width * 3, size.height * 3),
          );

          repository.onListConversations = (_) async => _page([
                _conversation(
                  id: 3001,
                  title: locale.languageCode == 'ar'
                      ? 'شحنة رقم BLK-0077 إلى منطقة عبدون'
                      : 'Shipment BLK-0077 to Abdoun district',
                  unread: 128,
                  shipmentId: 77,
                  policyNum: 'BLK-0077-LONG-POLICY',
                  lastMessage: locale.languageCode == 'ar'
                      ? 'يرجى تأكيد الاستلام من المتجر قبل الساعة الخامسة'
                      : 'Please confirm pickup from the store before 5 pm',
                ),
              ]);
          repository.onUnreadCount = () async => 128;

          await tester.pumpWidget(_host(
            child: DriverConversationsPage(repository: repository),
            conversations: conversations,
            locale: locale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          repository.onGetMessages = (_) async => DriverChatMessagesPage(
                messages: [
                  _incoming(
                    10,
                    text: locale.languageCode == 'ar'
                        ? 'يرجى تأكيد الاستلام من المتجر قبل الساعة الخامسة مساءً 👍'
                        : 'Please confirm pickup from the store before 5 pm 👍',
                  ),
                  _mine(
                    11,
                    'driver-chat-a',
                    text: 'On my way to the store now, about ten minutes out.',
                  ),
                ],
                hasMore: false,
              );

          await tester.pumpWidget(_host(
            child: DriverConversationPage(
              conversationId: 3001,
              title: 'Shipment BLK-0077',
              shipmentId: 77,
              policyNum: 'BLK-0077-LONG-POLICY',
              repository: repository,
            ),
            conversations: conversations,
            locale: locale,
          ));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsOneWidget);
          expect(find.byIcon(Icons.send_rounded), findsOneWidget);
        });
      }
    }
  });
  // ---------------------------------------------------------------------------
  // Opening chat from shipment details
  // ---------------------------------------------------------------------------

  group('Shipment chat action', () {
    Widget action(_RouteLog routes, {int shipmentId = 77}) {
      return _host(
        child: Scaffold(
          body: Center(
            child: DriverShipmentChatAction(
              shipmentId: shipmentId,
              repository: repository,
            ),
          ),
        ),
        conversations: conversations,
        observers: [routes],
      );
    }

    testWidgets('opens a thread that is not in the loaded page',
        (tester) async {
      await _setPhoneSize(tester);
      final routes = _RouteLog();
      // Nothing has ever been listed, so nothing could have been resolved
      // locally. The button must still work.
      repository.onGetOrCreateShipmentConversation = (shipmentId) async =>
          DriverChatConversationResult(
            conversation: _conversation(
              id: 9001,
              shipmentId: shipmentId,
              policyNum: 'BLK-0077',
            ),
            isCreated: true,
          );

      await tester.pumpWidget(action(routes));
      await tester.pumpAndSettle();
      expect(conversations.conversations, isEmpty);
      routes.pushed.clear();

      await tester.tap(find.byType(DriverShipmentChatAction));
      await tester.pumpAndSettle();

      expect(repository.resolvedShipmentIds, [77]);
      // [24] the route is the exact conversation the server returned.
      expect(routes.pushed, ['driver-chat/conversation/9001']);
      expect(find.byType(DriverConversationPage), findsOneWidget);
    });

    testWidgets('shows a spinner while resolving', (tester) async {
      await _setPhoneSize(tester);
      final gate = Completer<DriverChatConversationResult>();
      repository.onGetOrCreateShipmentConversation = (_) => gate.future;

      await tester.pumpWidget(action(_RouteLog()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DriverShipmentChatAction));
      await tester.pump();

      expect(find.text('Opening chat…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete(
        DriverChatConversationResult(
          conversation: _conversation(id: 9001, shipmentId: 77),
          isCreated: false,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a double tap resolves once and pushes once', (tester) async {
      await _setPhoneSize(tester);
      final routes = _RouteLog();
      final gate = Completer<DriverChatConversationResult>();
      repository.onGetOrCreateShipmentConversation = (_) => gate.future;

      await tester.pumpWidget(action(routes));
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await tester.tap(find.byType(DriverShipmentChatAction));
      await tester.pump();
      await tester.tap(find.byType(DriverShipmentChatAction), warnIfMissed: false);
      await tester.pump();

      expect(repository.resolvedShipmentIds, [77]);

      gate.complete(
        DriverChatConversationResult(
          conversation: _conversation(id: 9001, shipmentId: 77),
          isCreated: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.resolvedShipmentIds, [77]);
      expect(routes.pushed, ['driver-chat/conversation/9001']);
    });

    testWidgets('a failure shows an error and pushes nothing', (tester) async {
      await _setPhoneSize(tester);
      final routes = _RouteLog();
      repository.onGetOrCreateShipmentConversation =
          (_) async => throw const ChatAuthorizationException(
                code: 'CHAT_ACCESS_DENIED',
              );

      await tester.pumpWidget(action(routes));
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await tester.tap(find.byType(DriverShipmentChatAction));
      await tester.pumpAndSettle();

      expect(routes.pushed, isEmpty);
      expect(find.byType(DriverConversationPage), findsNothing);
      expect(
        find.text('You no longer have access to this conversation.'),
        findsOneWidget,
      );
      // The button is usable again rather than stuck on the spinner.
      expect(find.text('Shipment Chat'), findsOneWidget);
    });

    testWidgets('a session switch mid-resolution opens nothing',
        (tester) async {
      await _setPhoneSize(tester);
      final routes = _RouteLog();
      final gate = Completer<DriverChatConversationResult>();
      repository.onGetOrCreateShipmentConversation = (_) => gate.future;

      await tester.pumpWidget(action(routes));
      await tester.pumpAndSettle();
      routes.pushed.clear();

      await tester.tap(find.byType(DriverShipmentChatAction));
      await tester.pump();

      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete(
        DriverChatConversationResult(
          conversation: _conversation(id: 9001, shipmentId: 77),
          isCreated: true,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(routes.pushed, isEmpty);
      expect(find.byType(DriverConversationPage), findsNothing);
    });

    testWidgets('an unknown shipment renders no action', (tester) async {
      await _setPhoneSize(tester);

      await tester.pumpWidget(action(_RouteLog(), shipmentId: 0));
      await tester.pumpAndSettle();

      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('an unread badge is shown when the list already has the row',
        (tester) async {
      await _setPhoneSize(tester);
      repository.onListConversations = (_) async => _page([
            _conversation(id: 3001, shipmentId: 77, unread: 4),
          ]);

      await conversations.loadInitial();
      await tester.pumpWidget(action(_RouteLog()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(DriverChatUnreadBadge, '4'), findsOneWidget);
    });
  });
}
