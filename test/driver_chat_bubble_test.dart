// Tests for the persistent floating chat launcher and the global unread badge.
//
// The harness reproduces the real wiring from main.dart — the launcher provider,
// the navigation observer and the MaterialApp.builder stack — so what is being
// checked is the shipped integration, not a stand-in for it.

import 'dart:async';

import 'package:blockatie/models/chat/driver_chat_conversation.dart';
import 'package:blockatie/models/chat/driver_chat_message.dart';
import 'package:blockatie/models/chat/driver_chat_pagination.dart';
import 'package:blockatie/provider/chat/driver_chat_conversations_provider.dart';
import 'package:blockatie/provider/chat/driver_chat_launcher_provider.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/driver_chat_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/driver_chat_launcher_observer.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/chat/driver_chat_navigation.dart';
import 'package:blockatie/views/pages/chat/driver_conversation_page.dart';
import 'package:blockatie/views/pages/chat/driver_conversations_page.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// -----------------------------------------------------------------------------
// Fakes
// -----------------------------------------------------------------------------

DriverChatConversation _conversation({required int id, int unread = 0}) {
  return DriverChatConversation(
    conversationId: id,
    conversationType: 'shipment_driver',
    title: 'Shipment $id',
    lastMessage: 'Please confirm pickup',
    lastMessageType: 'text',
    unreadCount: unread,
    shipmentId: id,
    policyNum: 'BLK-$id',
    shipmentStatusId: 4,
    lastMessageSenderRole: 'admin',
    lastMessageAt: DateTime(2026, 9, 15, 9, 30),
  );
}

class _FakeChatRepository implements DriverChatRepository {
  int unreadCountCalls = 0;
  Future<int> Function()? onUnreadCount;
  Future<DriverChatConversationPage> Function(int page)? onListConversations;
  Future<DriverChatMessagesPage> Function(int? beforeMessageId)? onGetMessages;

  @override
  Future<int> getUnreadCount({CancelToken? cancelToken}) {
    unreadCountCalls++;
    return onUnreadCount?.call() ?? Future.value(0);
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
  Future<DriverChatMessagesPage> getMessages({
    required int conversationId,
    int? beforeMessageId,
    int limit = 30,
    CancelToken? cancelToken,
  }) {
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
    return Future.value(
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
    throw UnimplementedError();
  }

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
  }) {
    return Future.value(
      DriverChatConversationResult(
        conversation: _conversation(id: shipmentId),
        isCreated: false,
      ),
    );
  }
}

/// Stands in for secure storage: the tests decide whether a driver is signed in.
class _FakeSession {
  bool signedIn = true;
  Completer<DriverSession>? gate;

  Future<DriverSession> read() {
    final held = gate;
    if (held != null) {
      return held.future;
    }
    return Future.value(
      signedIn
          ? const DriverSession(apiKey: 'key-a', driverId: '901')
          : const DriverSession(),
    );
  }
}

// -----------------------------------------------------------------------------
// Harness — mirrors main.dart's wiring
// -----------------------------------------------------------------------------

class _Harness {
  _Harness({Duration pollingInterval = const Duration(milliseconds: 40)})
    : repository = _FakeChatRepository(),
      session = _FakeSession() {
    conversations = DriverChatConversationsProvider(
      repository: repository,
      unreadPollingInterval: pollingInterval,
    );
    launcher = DriverChatLauncherProvider(sessionReader: session.read);
  }

  final _FakeChatRepository repository;
  final _FakeSession session;
  late final DriverChatConversationsProvider conversations;
  late final DriverChatLauncherProvider launcher;

  void dispose() {
    conversations.dispose();
    launcher.dispose();
  }

  Widget app({Locale locale = const Locale('en'), Widget? home}) {
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
        navigatorObservers: [DriverChatLauncherObserver(launcher)],
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder:
            (context, child) => Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const DriverChatBubble(),
              ],
            ),
        home: home ?? const _ShellStub(),
      ),
    );
  }
}

/// Stands in for CustomBottomNavBar: reports the authenticated shell the same
/// way, and reserves the same bottom strip the real nav pill occupies.
class _ShellStub extends StatefulWidget {
  const _ShellStub();

  @override
  State<_ShellStub> createState() => _ShellStubState();
}

class _ShellStubState extends State<_ShellStub> {
  static const double navHeight = 110;
  DriverChatLauncherProvider? _launcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _launcher = context.read<DriverChatLauncherProvider>();
      _launcher?.setAuthenticatedShellVisible(true);
      _launcher?.syncSession();
    });
  }

  @override
  void dispose() {
    _launcher?.setAuthenticatedShellVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Center(child: Text('Driver home')),
      bottomNavigationBar: Container(
        key: const Key('bottom-nav-stub'),
        height: navHeight,
        color: Colors.white,
      ),
    );
  }
}

/// An ordinary pushed Driver screen — nothing to do with chat.
class _PlainPage extends StatelessWidget {
  const _PlainPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

Future<void> _setSize(
  WidgetTester tester, {
  Size? size,
  double bottomPad = 0,
}) async {
  tester.view.physicalSize = (size ?? const Size(390, 844)) * 3;
  tester.view.devicePixelRatio = 3;
  if (bottomPad > 0) {
    tester.view.padding = FakeViewPadding(bottom: bottomPad * 3);
    addTearDown(tester.view.resetPadding);
  }
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder get _bubble => find.byType(DriverChatBubble);
Finder get _bubbleVisual => find.byIcon(Icons.chat_bubble_rounded);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  // ---------------------------------------------------------------------------
  // Visibility
  // ---------------------------------------------------------------------------

  group('Visibility', () {
    testWidgets('appears once the authenticated shell is up', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      expect(_bubble, findsOneWidget);
      expect(_bubbleVisual, findsOneWidget);
      expect(harness.launcher.shouldShow, isTrue);
    });

    testWidgets('is absent on an auth screen', (tester) async {
      await _setSize(tester);
      harness.session.signedIn = false;

      // No shell reports itself, and no session exists: the launcher widget is
      // still mounted but draws nothing.
      await tester.pumpWidget(
        harness.app(home: const _PlainPage(label: 'Login')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
      expect(_bubbleVisual, findsNothing);
      expect(harness.launcher.shouldShow, isFalse);
    });

    testWidgets('a signed-out driver never sees it even inside the shell', (
      tester,
    ) async {
      await _setSize(tester);
      harness.session.signedIn = false;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      expect(harness.launcher.isAuthenticatedShellVisible, isTrue);
      expect(harness.launcher.isAuthenticated, isFalse);
      expect(_bubbleVisual, findsNothing);
    });

    testWidgets('persists across ordinary route pushes, exactly once', (
      tester,
    ) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);

      for (var index = 1; index <= 3; index++) {
        Nav.key.currentState!.push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: 'plain/$index'),
            builder: (_) => _PlainPage(label: 'Screen $index'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Screen $index'), findsOneWidget);
        // One launcher, still there, after every push.
        expect(_bubble, findsOneWidget);
        expect(_bubbleVisual, findsOneWidget);
      }

      Nav.key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);
    });

    testWidgets('hides while the conversations screen is on top', (
      tester,
    ) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);

      // Not awaited: a push Future only completes when the route is popped.
      unawaited(
        DriverChatNavigation.openConversations(
          Nav.key.currentState!,
          repository: harness.repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DriverConversationsPage), findsOneWidget);
      expect(_bubbleVisual, findsNothing);

      Nav.key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);
    });

    testWidgets('hides on a conversation thread', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      unawaited(
        DriverChatNavigation.openConversation(
          Nav.key.currentState!.overlay!.context,
          conversation: _conversation(id: 3001),
          repository: harness.repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DriverConversationPage), findsOneWidget);
      expect(_bubbleVisual, findsNothing);
    });

    testWidgets('stays visible on the shipment screen opened from a thread', (
      tester,
    ) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // A nested push over the shell must not hide the launcher; only chat
      // screens do.
      Nav.key.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: DriverChatRoutes.shipment),
          builder: (_) => const _PlainPage(label: 'Shipment details'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shipment details'), findsOneWidget);
      expect(_bubbleVisual, findsOneWidget);
    });

    testWidgets('hides while the keyboard is up', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 320 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(_bubbleVisual, findsNothing);
    });

    testWidgets('hides for dialogs and modal sheets, then returns', (
      tester,
    ) async {
      await _setSize(tester);
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);

      unawaited(
        showDialog<void>(
          context: Nav.key.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Active dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsNothing);

      Navigator.of(Nav.key.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);

      unawaited(
        showModalBottomSheet<void>(
          context: Nav.key.currentContext!,
          builder: (_) => const SizedBox(height: 160, child: Text('Sheet')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsNothing);

      Navigator.of(Nav.key.currentContext!).pop();
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Badge
  // ---------------------------------------------------------------------------

  group('Unread badge', () {
    Future<void> pumpWithUnread(WidgetTester tester, int unread) async {
      await _setSize(tester);
      harness.repository.onUnreadCount = () async => unread;
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
    }

    testWidgets('zero shows no badge', (tester) async {
      await pumpWithUnread(tester, 0);

      expect(_bubbleVisual, findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(harness.conversations.globalUnreadCount, 0);
    });

    testWidgets('one shows an exact count', (tester) async {
      await pumpWithUnread(tester, 1);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('ninety-nine shows an exact count', (tester) async {
      await pumpWithUnread(tester, 99);
      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('one hundred collapses to 99+', (tester) async {
      await pumpWithUnread(tester, 100);
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('digits stay left-to-right in Arabic', (tester) async {
      await _setSize(tester);
      harness.repository.onUnreadCount = () async => 128;

      await tester.pumpWidget(harness.app(locale: const Locale('ar')));
      await tester.pumpAndSettle();

      final badge = tester.widget<Text>(find.text('99+'));
      expect(badge.textDirection, TextDirection.ltr);
      // The layout itself is RTL.
      expect(
        Directionality.of(tester.element(_bubbleVisual)),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refresh moves the badge to the server figure', (
      tester,
    ) async {
      await pumpWithUnread(tester, 3);
      expect(find.text('3'), findsOneWidget);

      harness.repository.onUnreadCount = () async => 7;
      await harness.conversations.refreshUnreadCount();
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });

    testWidgets('a mark-read result lowers the badge by the server delta', (
      tester,
    ) async {
      await _setSize(tester);
      harness.repository.onListConversations =
          (_) async => DriverChatConversationPage(
            conversations: [_conversation(id: 3001, unread: 4)],
            pagination: const DriverChatPagination(
              page: 1,
              limit: 15,
              total: 1,
              totalPages: 1,
            ),
          );
      harness.repository.onUnreadCount = () async => 4;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await harness.conversations.loadInitial();
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);

      // mark_read cleared it server-side, and the conversation page feeds the
      // server's own figure back.
      harness.repository.onUnreadCount = () async => 0;
      harness.conversations.applyConversationUnread(3001, 0);
      await tester.pumpAndSettle();

      expect(find.text('4'), findsNothing);
      expect(harness.conversations.globalUnreadCount, 0);
      expect(harness.conversations.conversations.single.unreadCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  group('Navigation', () {
    testWidgets('tapping opens the conversations page', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      await tester.tap(_bubbleVisual);
      await tester.pumpAndSettle();

      expect(find.byType(DriverConversationsPage), findsOneWidget);
    });

    testWidgets('it cannot be tapped into a second chat route', (tester) async {
      await _setSize(tester);
      final pushed = <String?>[];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DriverChatConversationsProvider>.value(
              value: harness.conversations,
            ),
            ChangeNotifierProvider<DriverChatLauncherProvider>.value(
              value: harness.launcher,
            ),
          ],
          child: MaterialApp(
            navigatorKey: Nav.key,
            navigatorObservers: [
              DriverChatLauncherObserver(harness.launcher),
              _RouteLog(pushed),
            ],
            builder:
                (context, child) => Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const DriverChatBubble(),
                  ],
                ),
            home: const _ShellStub(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      pushed.clear();

      await tester.tap(_bubbleVisual);
      await tester.pumpAndSettle();
      expect(pushed, [DriverChatRoutes.conversations]);

      // The launcher is gone now, so there is nothing left to tap: one route,
      // never two.
      expect(_bubbleVisual, findsNothing);
      expect(pushed, [DriverChatRoutes.conversations]);
    });

    testWidgets('returning re-reads the badge from the server', (tester) async {
      await _setSize(tester);
      harness.repository.onUnreadCount = () async => 5;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      await tester.tap(_bubbleVisual);
      await tester.pumpAndSettle();

      final callsBeforeReturn = harness.repository.unreadCountCalls;
      harness.repository.onUnreadCount = () async => 2;
      Nav.key.currentState!.pop();
      await tester.pumpAndSettle();

      expect(
        harness.repository.unreadCountCalls,
        greaterThan(callsBeforeReturn),
      );
      expect(find.text('2'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  group('Layout', () {
    testWidgets('clears the bottom navigation', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      final bubbleRect = tester.getRect(_bubbleVisual);
      final navRect = tester.getRect(find.byKey(const Key('bottom-nav-stub')));

      expect(
        bubbleRect.bottom,
        lessThanOrEqualTo(navRect.top),
        reason: 'the launcher must sit above the bottom navigation',
      );
    });

    testWidgets('respects the bottom safe area', (tester) async {
      await _setSize(tester);
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final withoutInset = tester.getRect(_bubbleVisual).bottom;

      await _setSize(tester, bottomPad: 34);
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final withInset = tester.getRect(_bubbleVisual).bottom;

      // A home-indicator inset lifts the launcher by the same amount.
      expect(withoutInset - withInset, closeTo(34, 1));
    });

    testWidgets('sits on the trailing edge in both directions', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      final ltrCentre = tester.getCenter(_bubbleVisual).dx;
      final width = tester.getSize(find.byType(MaterialApp)).width;
      expect(ltrCentre, greaterThan(width / 2));

      await tester.pumpWidget(harness.app(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(_bubbleVisual).dx, lessThan(width / 2));
    });

    testWidgets('renders one rounded-square surface without a halo', (
      tester,
    ) async {
      await _setSize(tester);
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      final surface = find.byKey(
        const ValueKey<String>('driver-chat-launcher-surface'),
      );
      expect(surface, findsOneWidget);
      expect(_bubbleVisual, findsOneWidget);

      final decoration =
          tester.widget<Ink>(surface).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isA<BorderRadius>());
      expect(decoration.boxShadow, hasLength(1));
      expect(decoration.boxShadow!.single.color, const Color(0x260F172A));
    });

    for (final size in const [
      Size(320, 568),
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
      Size(768, 1024),
      Size(1024, 768),
    ]) {
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} in '
            '${locale.languageCode}', (tester) async {
          await _setSize(tester, size: size);
          harness.repository.onUnreadCount = () async => 128;

          await tester.pumpWidget(harness.app(locale: locale));
          await tester.pumpAndSettle();

          final rect = tester.getRect(_bubbleVisual);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          expect(find.text('99+'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // Polling and lifecycle
  // ---------------------------------------------------------------------------

  group('Polling', () {
    testWidgets('starts exactly one poller on entry', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      expect(harness.conversations.isPollingUnread, isTrue);
      // The entry refresh already happened.
      expect(harness.repository.unreadCountCalls, greaterThan(0));

      // It really is ticking.
      final afterEntry = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(harness.repository.unreadCountCalls, greaterThan(afterEntry));

      // And one cancel silences it completely, which is only true if there is
      // a single timer rather than several.
      harness.conversations.stopUnreadPolling();
      expect(harness.conversations.isPollingUnread, isFalse);
      final afterStop = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(harness.repository.unreadCountCalls, afterStop);
    });

    testWidgets('repeated starts never stack a second timer', (tester) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      harness.conversations.startUnreadPolling(immediate: false);
      harness.conversations.startUnreadPolling(immediate: false);
      harness.conversations.startUnreadPolling(immediate: false);

      final before = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(harness.repository.unreadCountCalls, greaterThan(before));

      // One cancel silences everything. Had those three calls each made a
      // timer, the two orphans would keep firing past this point.
      harness.conversations.stopUnreadPolling();
      expect(harness.conversations.isPollingUnread, isFalse);
      final afterStop = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(harness.repository.unreadCountCalls, afterStop);
    });

    testWidgets('backgrounding pauses and foregrounding resumes', (
      tester,
    ) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(harness.conversations.isPollingUnread, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(harness.conversations.isPollingUnread, isFalse);
      expect(harness.conversations.isUnreadPollingPaused, isTrue);

      final whileBackgrounded = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(harness.repository.unreadCountCalls, whileBackgrounded);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(harness.conversations.isPollingUnread, isTrue);
      expect(
        harness.repository.unreadCountCalls,
        greaterThan(whileBackgrounded),
      );
    });

    testWidgets('repeated foreground events do not stack timers', (
      tester,
    ) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      for (var cycle = 0; cycle < 4; cycle++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }

      final before = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(harness.repository.unreadCountCalls, greaterThan(before));

      // Still exactly one timer after four cycles: one cancel ends all polling.
      harness.conversations.stopUnreadPolling();
      expect(harness.conversations.isPollingUnread, isFalse);
      final afterStop = harness.repository.unreadCountCalls;
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(harness.repository.unreadCountCalls, afterStop);
    });

    testWidgets('a foreground event after logout does not restart it', (
      tester,
    ) async {
      await _setSize(tester);

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      UserSessionState.reset(SessionResetReason.logout);
      await tester.pumpAndSettle();
      expect(harness.conversations.isPollingUnread, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(harness.conversations.isPollingUnread, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Session safety
  // ---------------------------------------------------------------------------

  group('Session safety', () {
    testWidgets('logout clears the badge and removes the launcher', (
      tester,
    ) async {
      await _setSize(tester);
      harness.repository.onUnreadCount = () async => 6;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(find.text('6'), findsOneWidget);

      harness.session.signedIn = false;
      UserSessionState.reset(SessionResetReason.logout);
      await tester.pumpAndSettle();

      expect(harness.conversations.globalUnreadCount, 0);
      expect(harness.conversations.isPollingUnread, isFalse);
      expect(_bubbleVisual, findsNothing);
      expect(find.text('6'), findsNothing);
    });

    testWidgets('DRIVER_INACTIVE removes the launcher through session reset', (
      tester,
    ) async {
      await _setSize(tester);
      harness.repository.onUnreadCount = () async => 2;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(_bubbleVisual, findsOneWidget);

      harness.session.signedIn = false;
      UserSessionState.reset(SessionResetReason.accountInactive);
      await tester.pumpAndSettle();

      expect(_bubbleVisual, findsNothing);
      expect(harness.conversations.isPollingUnread, isFalse);
    });

    testWidgets("driver B never inherits driver A's count", (tester) async {
      await _setSize(tester);
      harness.repository.onUnreadCount = () async => 9;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(find.text('9'), findsOneWidget);

      // A logs out, B signs in on the same device.
      UserSessionState.reset(SessionResetReason.accountChanged);
      await tester.pumpAndSettle();
      expect(harness.conversations.globalUnreadCount, 0);

      harness.repository.onUnreadCount = () async => 1;
      harness.launcher.setAuthenticatedShellVisible(true);
      await harness.launcher.syncSession();
      harness.conversations.startUnreadPolling();
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('9'), findsNothing);
    });

    testWidgets("a late count from driver A is discarded", (tester) async {
      await _setSize(tester);
      final gate = Completer<int>();
      harness.repository.onUnreadCount = () => gate.future;

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      expect(harness.repository.unreadCountCalls, greaterThan(0));

      UserSessionState.reset(SessionResetReason.accountChanged);
      gate.complete(42);
      await tester.pumpAndSettle();

      expect(harness.conversations.globalUnreadCount, 0);
      expect(find.text('42'), findsNothing);
    });

    testWidgets('a late session read cannot resurrect the launcher', (
      tester,
    ) async {
      await _setSize(tester);
      final gate = Completer<DriverSession>();

      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      harness.session.gate = gate;
      unawaited(harness.launcher.syncSession());
      UserSessionState.reset(SessionResetReason.invalidSession);
      gate.complete(const DriverSession(apiKey: 'key-a', driverId: '901'));
      await tester.pumpAndSettle();

      expect(harness.launcher.isAuthenticated, isFalse);
      expect(_bubbleVisual, findsNothing);
    });
  });
}

/// Records pushed route names.
class _RouteLog extends NavigatorObserver {
  _RouteLog(this.pushed);

  final List<String?> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}
