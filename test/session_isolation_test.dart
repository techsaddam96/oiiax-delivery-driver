// Verifies the driver session boundary: user-scoped providers reset on logout,
// and work started under a previous driver cannot write into the next session.

import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/provider/filter.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/orders.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/requests_provider.dart';
import 'package:blockatie/provider/settlements/driver_settlement_details_provider.dart';
import 'package:blockatie/provider/settlements/driver_settlements_provider.dart';
import 'package:blockatie/provider/shipment.dart';
import 'package:blockatie/provider/shipment_instsnt.dart';
import 'package:blockatie/provider/wallet.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/services/request_id_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in used to assert the generic contract without touching HTTP.
class _FakeUserProvider extends UserScopedNotifier {
  String? driverOwnedValue = 'driver-a-value';
  int clearCount = 0;

  @override
  void clearUserState() {
    clearCount++;
    driverOwnedValue = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserSessionState boundary', () {
    test('reset increments the generation and invalidates the old one', () {
      final before = UserSessionState.generation;

      UserSessionState.reset(SessionResetReason.logout);

      expect(UserSessionState.generation, greaterThan(before));
      expect(UserSessionState.isCurrent(before), isFalse);
      expect(UserSessionState.isCurrent(UserSessionState.generation), isTrue);
      expect(UserSessionState.lastReason, SessionResetReason.logout);
    });

    test('registered providers are cleared on reset', () {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.clearCount, 1);
      expect(provider.driverOwnedValue, isNull);
    });

    test('account change clears state the same way as logout', () {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.accountChanged);

      expect(provider.clearCount, 1);
      expect(UserSessionState.lastReason, SessionResetReason.accountChanged);
    });

    test('a disposed provider is no longer reset', () {
      final provider = _FakeUserProvider();
      provider.dispose();

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.clearCount, 0);
    });
  });

  group('late response protection', () {
    test('a generation captured before logout is refused afterwards', () {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      final generation = provider.stateGeneration;
      expect(provider.acceptsState(generation), isTrue);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.acceptsState(generation), isFalse);
    });

    test('guardSession discards a Driver A response that lands late', () async {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      final generation = provider.stateGeneration;

      // Driver A's request is still in flight when the account switches.
      final inFlight = Future<String>.delayed(
        const Duration(milliseconds: 20),
        () => 'driver-a-shipments',
      );
      UserSessionState.reset(SessionResetReason.accountChanged);

      await expectLater(
        provider.guardSession(inFlight, generation),
        throwsA(isA<SessionChanged>()),
      );
      expect(provider.driverOwnedValue, isNull);
    });

    test('guardSession converts a late failure into SessionChanged', () async {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      final generation = provider.stateGeneration;
      final failing = Future<String>.delayed(
        const Duration(milliseconds: 20),
        () => throw StateError('network failed'),
      );
      UserSessionState.reset(SessionResetReason.logout);

      await expectLater(
        provider.guardSession(failing, generation),
        throwsA(isA<SessionChanged>()),
      );
    });

    test(
      'guardSession still returns a response for the current session',
      () async {
        final provider = _FakeUserProvider();
        addTearDown(provider.dispose);

        final result = await provider.guardSession(
          Future<String>.value('driver-b-shipments'),
          provider.stateGeneration,
        );

        expect(result, 'driver-b-shipments');
      },
    );

    test('re-login after logout accepts work again (A then B then A)', () {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);
      final afterLogout = provider.stateGeneration;
      expect(provider.acceptsState(afterLogout), isTrue);

      UserSessionState.reset(SessionResetReason.accountChanged);
      expect(provider.acceptsState(afterLogout), isFalse);
      expect(provider.acceptsState(provider.stateGeneration), isTrue);
    });

    test('rapid consecutive resets keep invalidating older generations', () {
      final provider = _FakeUserProvider();
      addTearDown(provider.dispose);

      final first = provider.stateGeneration;
      UserSessionState.reset(SessionResetReason.logout);
      final second = provider.stateGeneration;
      UserSessionState.reset(SessionResetReason.accountChanged);

      expect(provider.acceptsState(first), isFalse);
      expect(provider.acceptsState(second), isFalse);
      expect(provider.clearCount, 2);
    });
  });

  group('idempotency leases are session scoped', () {
    test('the same payload gets a new request id in a new session', () {
      final payload = {'shipment_id': 1, 'status_id': 6};

      final first = RequestIdService.acquire(
        operation: 'driver.updateShipmentStatus',
        payload: payload,
      );
      UserSessionState.reset(SessionResetReason.accountChanged);
      RequestIdService.clearUserState();

      final second = RequestIdService.acquire(
        operation: 'driver.updateShipmentStatus',
        payload: payload,
      );

      expect(second.requestId, isNot(first.requestId));
      second.complete();
    });
  });

  group('real providers clear driver-owned state', () {
    test('shipment lists are emptied', () {
      final provider = ShipmentProvider();
      addTearDown(provider.dispose);

      // The page indicator advances only when a page actually arrives, so a
      // tap on its own must not move it.
      provider.setPage(3);
      expect(provider.currentPage, 1);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.currentPage, 1);
      expect(provider.shipmentsResponse, isNull);
      expect(provider.hasLoaded, isFalse);
      expect(provider.paginatedShipments, isEmpty);
      expect(provider.totalCount, 0);
    });

    test('instant shipment cache and its driver id are dropped', () {
      final provider = ShipmentInstantprovider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.shipmentInstantResponse, isNull);
      expect(provider.hasLoaded, isFalse);
      expect(provider.allShipments, isEmpty);
      expect(provider.currentPage, 1);
      expect(provider.searchQuery, '');
    });

    test('financial state is cleared', () {
      final provider = WithdrawalProvider();
      addTearDown(provider.dispose);

      provider.updateAmount('250.00 JOD');
      provider.toggleAgreement();
      expect(provider.amount, '250.00 JOD');
      expect(provider.agreedToTerms, isTrue);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.amount, '00.00 JOD');
      expect(provider.agreedToTerms, isFalse);
      expect(provider.withdrwalRes, isNull);
      expect(provider.paginatedRequests, isEmpty);
      expect(provider.totalPages, 0);
    });

    test('settlement list and summaries are cleared', () {
      final provider = DriverSettlementsProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.items, isEmpty);
      expect(provider.financialSummary, isNull);
      expect(provider.performanceSummary, isNull);
      expect(provider.listError, isNull);
      expect(provider.statusFilter, isNull);
    });

    test('settlement detail is cleared', () {
      final provider = DriverSettlementDetailsProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.settlement, isNull);
      expect(provider.lines, isEmpty);
      expect(provider.hasMore, isFalse);
    });

    test('withdrawal request history is cleared', () {
      final provider = RequestsProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.requests, isEmpty);
      expect(provider.currentPage, 1);
      expect(provider.error, isNull);
    });

    test('home statistics and driver name are cleared', () {
      final provider = HomeProvider();
      addTearDown(provider.dispose);

      provider.setQuery('AMM-123');
      expect(provider.query, 'amm-123');

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.driverStats, isNull);
      expect(provider.driverName, isNull);
      expect(provider.orderStatusData, isNull);
      expect(provider.query, '');
    });

    test('profile identity is cleared but language is not', () {
      final provider = ProfileProvider();
      addTearDown(provider.dispose);

      provider.setLanguage('Arabic');
      provider.nameController.text = 'Driver A';

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.profileInfo, isNull);
      expect(provider.ratingInfo, isNull);
      expect(provider.profileImage, isNull);
      expect(provider.nameController.text, isEmpty);
      // Language is a device preference and must survive the account boundary.
      expect(provider.selectedLanguage, 'Arabic');
    });

    test('notification list and unread badge are cleared', () {
      final provider = NotificationProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.notificationData, isNull);
      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.error, isNull);
    });

    test('filter results and the store list are cleared', () {
      final provider = FilterProvider();
      addTearDown(provider.dispose);

      provider.selectStatusId(6);

      UserSessionState.reset(SessionResetReason.logout);

      // The draft, the applied query and its results all belong to one driver.
      expect(provider.draft.statusId, 0);
      expect(provider.draft.date, isNull);
      expect(provider.draft.storeId, isNull);
      expect(provider.activeCriteria.hasAny, isFalse);
      expect(provider.selectedClient, isNull);
      expect(provider.clientList, isEmpty);
      expect(provider.shipments, isEmpty);
      expect(provider.pagination, isNull);
      expect(provider.queryState, FilterQueryState.idle);
      expect(provider.statusState, FilterOptionsState.idle);
    });

    test('order status view is cleared', () {
      final provider = OrderStatusProvider();
      addTearDown(provider.dispose);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.status, isNull);
      expect(provider.statusMsg, isNull);
    });

    test('navigation returns to the first tab for the next driver', () {
      final provider = BottomNavProvider();
      addTearDown(provider.dispose);

      provider.setIndex(4);
      expect(provider.selectedIndex, 4);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.selectedIndex, 0);
      expect(provider.overlayPage, isNull);
    });

    test('wallet tab selection is cleared', () {
      final provider = WalletProvider();
      addTearDown(provider.dispose);

      provider.setSelectedTab(2);
      expect(provider.selectedTabIndex, 2);

      UserSessionState.reset(SessionResetReason.logout);

      expect(provider.selectedTabIndex, -1);
    });
  });
}
