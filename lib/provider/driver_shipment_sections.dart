import 'dart:async';
import 'dart:developer';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The three mutually exclusive list contracts provided by
/// `api_driver_shipment_sections.php`.  Do not derive these categories in the
/// app: custody and finality are server-owned workflow rules.
enum DriverShipmentSection { activeWork, history, availableInstant }

extension DriverShipmentSectionWireValue on DriverShipmentSection {
  String get wireValue => switch (this) {
    DriverShipmentSection.activeWork => 'active_work',
    DriverShipmentSection.history => 'history',
    DriverShipmentSection.availableInstant => 'available_instant',
  };
}

/// Only categories the client can establish safely. Server messages can carry
/// operational detail, so they intentionally are not rendered to a driver.
enum DriverShipmentSectionFailure { network, generic, missingSession, contract }

/// One independently paginated response. Keeping the snapshot on the response
/// that supplied it prevents a page of rows, a count, and a capability proof
/// from being accidentally mixed across legacy endpoints or driver sessions.
class DriverShipmentSectionState {
  const DriverShipmentSectionState({
    required this.section,
    this.shipments = const <Shipment>[],
    this.pagination,
    this.snapshot,
    this.isLoading = false,
    this.hasLoaded = false,
    this.failure,
    this.page = 1,
    this.searchQuery = '',
  });

  final DriverShipmentSection section;
  final List<Shipment> shipments;
  final ShipmentsPagination? pagination;
  final DriverWorkloadSnapshot? snapshot;
  final bool isLoading;
  final bool hasLoaded;
  final DriverShipmentSectionFailure? failure;
  final int page;
  final String searchQuery;

  int get total => pagination?.total ?? shipments.length;
  int get totalPages => pagination?.totalPages ?? (shipments.isEmpty ? 0 : 1);
  bool get hasError => failure != null;
  bool get isPageChanging => isLoading && hasLoaded;

  DriverShipmentSectionState copyWith({
    List<Shipment>? shipments,
    ShipmentsPagination? pagination,
    DriverWorkloadSnapshot? snapshot,
    bool clearSnapshot = false,
    bool? isLoading,
    bool? hasLoaded,
    DriverShipmentSectionFailure? failure,
    bool clearFailure = false,
    int? page,
    String? searchQuery,
  }) {
    return DriverShipmentSectionState(
      section: section,
      shipments: shipments ?? this.shipments,
      pagination: pagination ?? this.pagination,
      snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
      isLoading: isLoading ?? this.isLoading,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      failure: clearFailure ? null : (failure ?? this.failure),
      page: page ?? this.page,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// Driver-facing source of truth for the three shipment sections.
///
/// It deliberately does not wrap or filter legacy pages.  Every list, total
/// and workload proof comes from the category endpoint, and every response is
/// tied to the authenticated driver before it can be rendered.
class DriverShipmentSectionsProvider extends UserScopedNotifier {
  static const int itemsPerPage = 10;
  static const Duration _searchDebounce = Duration(milliseconds: 400);

  final Map<DriverShipmentSection, DriverShipmentSectionState> _states = {
    for (final section in DriverShipmentSection.values)
      section: DriverShipmentSectionState(section: section),
  };
  final Map<DriverShipmentSection, bool> _inFlight = {
    for (final section in DriverShipmentSection.values) section: false,
  };
  final Map<DriverShipmentSection, int> _requestVersions = {
    for (final section in DriverShipmentSection.values) section: 0,
  };
  final Map<DriverShipmentSection, Timer?> _searchTimers = {
    for (final section in DriverShipmentSection.values) section: null,
  };

  int? _authenticatedDriverId;
  Timer? _snapshotExpiryTimer;

  DriverShipmentSectionState stateFor(DriverShipmentSection section) =>
      _states[section]!;

  /// This is a capability gate, not an empty-list check. It requires both the
  /// active-work and available-offer reads to independently prove zero current
  /// work for this exact driver. A failure, expiry, reassignment, concurrent
  /// acceptance or unsupported backend contract therefore fails closed.
  bool get canShowAvailableInstantOffers {
    final driverId = _authenticatedDriverId;
    final active = stateFor(DriverShipmentSection.activeWork);
    final available = stateFor(DriverShipmentSection.availableInstant);
    if (driverId == null || active.isLoading || available.isLoading) {
      return false;
    }
    if (!active.hasLoaded ||
        !available.hasLoaded ||
        active.hasError ||
        available.hasError) {
      return false;
    }
    final now = DateTime.now();
    return active.snapshot?.provesNoActiveOperationalWorkFor(driverId, now) ==
            true &&
        available.snapshot?.provesNoActiveOperationalWorkFor(driverId, now) ==
            true;
  }

  /// The page can state a verification problem rather than pretending that a
  /// missing snapshot means no work. The Available tab itself remains hidden.
  bool get availabilityVerificationPending {
    final active = stateFor(DriverShipmentSection.activeWork);
    final available = stateFor(DriverShipmentSection.availableInstant);
    return active.isLoading ||
        available.isLoading ||
        (!active.hasLoaded && !active.hasError) ||
        (!available.hasLoaded && !available.hasError);
  }

  bool get availabilityVerificationFailed {
    final active = stateFor(DriverShipmentSection.activeWork);
    final available = stateFor(DriverShipmentSection.availableInstant);
    if (active.hasError || available.hasError) return true;
    if (!active.hasLoaded || !available.hasLoaded) return false;
    // A non-null snapshot can still be unsupported, stale, incomplete or for
    // another driver. Those cases are just as unsafe as a missing snapshot;
    // word them as a verification failure rather than misleadingly as zero.
    return !hasActiveOperationalWork && !canShowAvailableInstantOffers;
  }

  /// A server-confirmed positive workload is not an error: only Section 3 is
  /// withheld while the always-available Active and History lists remain live.
  bool get hasActiveOperationalWork {
    final snapshot = stateFor(DriverShipmentSection.activeWork).snapshot;
    final driverId = _authenticatedDriverId;
    if (snapshot == null || driverId == null || snapshot.driverId != driverId) {
      return false;
    }
    return snapshot.contractVersion == 1 &&
        snapshot.isComplete &&
        snapshot.expiresAt != null &&
        DateTime.now().toUtc().isBefore(snapshot.expiresAt!) &&
        snapshot.activeOperationalTotal > 0;
  }

  Future<void> refreshAll({bool force = true}) async {
    await Future.wait([
      fetch(DriverShipmentSection.activeWork, force: force, page: 1),
      fetch(DriverShipmentSection.history, force: force, page: 1),
      fetch(DriverShipmentSection.availableInstant, force: force, page: 1),
    ]);
  }

  Future<void> fetch(
    DriverShipmentSection section, {
    bool force = true,
    int? page,
  }) async {
    if (_inFlight[section] == true) return;

    final before = stateFor(section);
    final requestedPage = page ?? before.page;
    if (requestedPage < 1) return;
    if (!force &&
        before.hasLoaded &&
        !before.hasError &&
        requestedPage == before.page) {
      return;
    }

    final generation = stateGeneration;
    final requestVersion = (_requestVersions[section] ?? 0) + 1;
    _requestVersions[section] = requestVersion;
    _inFlight[section] = true;
    _states[section] = before.copyWith(
      isLoading: true,
      clearFailure: true,
      // A snapshot has a short lifetime and must not authorize visibility
      // while a newer current-driver read is unresolved.
      clearSnapshot: section != DriverShipmentSection.history,
    );
    _scheduleSnapshotExpiryCheck();
    notifyListeners();

    try {
      final driverIdValue = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();
      if (!acceptsState(generation) ||
          _requestVersions[section] != requestVersion) {
        return;
      }
      final driverId = int.tryParse(driverIdValue?.toString() ?? '');
      if (driverIdValue == null ||
          driverId == null ||
          driverId <= 0 ||
          apiKey == null ||
          apiKey.trim().isEmpty) {
        _applyFailure(
          section,
          requestVersion,
          generation,
          DriverShipmentSectionFailure.missingSession,
        );
        return;
      }

      // Responses are accepted only when the authenticated identity stays the
      // same. UserSessionState normally invalidates first; this is an extra
      // guard for a changed secure-storage value between concurrent requests.
      if (_authenticatedDriverId != null &&
          _authenticatedDriverId != driverId) {
        resetUserState();
      }
      if (!acceptsState(generation)) return;
      _authenticatedDriverId = driverId;

      final response = await sessionDio().post(
        AppUrls.driverShipmentSections,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {
          'driver_id': driverIdValue,
          'section': section.wireValue,
          'page': requestedPage,
          'limit': itemsPerPage,
          if (before.searchQuery.isNotEmpty) 'search': before.searchQuery,
        },
      );
      if (!acceptsState(generation) ||
          _requestVersions[section] != requestVersion) {
        return;
      }

      if (response.statusCode != 200 ||
          !_isSuccess(response.data) ||
          response.data is! Map) {
        log(
          'Driver shipment section ${section.wireValue} rejected: '
          'status=${response.statusCode ?? 'none'} '
          'code=${_safeResponseCode(response.data) ?? 'none'}',
        );
        _applyFailure(
          section,
          requestVersion,
          generation,
          DriverShipmentSectionFailure.generic,
        );
        return;
      }

      final parsed = ShipmentsResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      // The contract includes driver_id outside the row list. Never accept a
      // page whose envelope cannot be bound to the current authenticated user.
      if (parsed.driverId != driverId) {
        _applyFailure(
          section,
          requestVersion,
          generation,
          DriverShipmentSectionFailure.contract,
        );
        return;
      }
      _applySuccess(
        section,
        parsed,
        requestedPage: requestedPage,
        requestVersion: requestVersion,
        generation: generation,
      );
    } catch (error) {
      if (acceptsState(generation) &&
          _requestVersions[section] == requestVersion) {
        _applyFailure(section, requestVersion, generation, _failureFor(error));
      }
      final response = error is DioException ? error.response : null;
      log(
        'Driver shipment section ${section.wireValue} failed: '
        'type=${error.runtimeType} '
        'status=${response?.statusCode ?? 'none'} '
        'code=${_safeResponseCode(response?.data) ?? 'none'}',
      );
    } finally {
      if (acceptsState(generation) &&
          _requestVersions[section] == requestVersion) {
        _inFlight[section] = false;
        final current = stateFor(section);
        _states[section] = current.copyWith(isLoading: false);
        _scheduleSnapshotExpiryCheck();
        notifyListeners();
      }
    }
  }

  void setPage(DriverShipmentSection section, int page) {
    final current = stateFor(section);
    if (page < 1 ||
        page == current.page ||
        (current.totalPages > 0 && page > current.totalPages)) {
      return;
    }
    unawaited(fetch(section, page: page));
  }

  void setSearchQuery(DriverShipmentSection section, String value) {
    final normalized = value.trim();
    final current = stateFor(section);
    if (normalized == current.searchQuery) return;
    _states[section] = current.copyWith(searchQuery: normalized, page: 1);
    notifyListeners();
    _searchTimers[section]?.cancel();
    _searchTimers[section] = Timer(_searchDebounce, () {
      unawaited(fetch(section, page: 1));
    });
  }

  /// Applies a successful synthetic category response without networking. It
  /// mirrors the production identity and snapshot checks for focused tests.
  @visibleForTesting
  void applyServerResponseForTest(
    DriverShipmentSection section,
    ShipmentsResponse response, {
    required int authenticatedDriverId,
    int requestedPage = 1,
  }) {
    _authenticatedDriverId = authenticatedDriverId;
    if (response.driverId != authenticatedDriverId) {
      _states[section] = stateFor(section).copyWith(
        isLoading: false,
        hasLoaded: false,
        failure: DriverShipmentSectionFailure.contract,
        clearSnapshot: true,
      );
    } else {
      _states[section] = DriverShipmentSectionState(
        section: section,
        shipments: response.shipments,
        pagination: response.pagination,
        snapshot: response.driverWorkloadSnapshot,
        isLoading: false,
        hasLoaded: true,
        page: response.pagination?.page ?? requestedPage,
        searchQuery: stateFor(section).searchQuery,
      );
    }
    _scheduleSnapshotExpiryCheck();
    notifyListeners();
  }

  @visibleForTesting
  void applyFailureForTest(
    DriverShipmentSection section,
    DriverShipmentSectionFailure failure,
  ) {
    _states[section] = stateFor(
      section,
    ).copyWith(isLoading: false, failure: failure, clearSnapshot: true);
    _scheduleSnapshotExpiryCheck();
    notifyListeners();
  }

  void _applySuccess(
    DriverShipmentSection section,
    ShipmentsResponse response, {
    required int requestedPage,
    required int requestVersion,
    required int generation,
  }) {
    if (!acceptsState(generation) ||
        _requestVersions[section] != requestVersion) {
      return;
    }
    final page = response.pagination?.page ?? requestedPage;
    _states[section] = DriverShipmentSectionState(
      section: section,
      shipments: response.shipments,
      pagination: response.pagination,
      snapshot: response.driverWorkloadSnapshot,
      isLoading: true,
      hasLoaded: true,
      page: page,
      searchQuery: stateFor(section).searchQuery,
    );
  }

  void _applyFailure(
    DriverShipmentSection section,
    int requestVersion,
    int generation,
    DriverShipmentSectionFailure failure,
  ) {
    if (!acceptsState(generation) ||
        _requestVersions[section] != requestVersion) {
      return;
    }
    final current = stateFor(section);
    _states[section] = current.copyWith(
      isLoading: true,
      failure: failure,
      clearSnapshot: section != DriverShipmentSection.history,
    );
  }

  void _scheduleSnapshotExpiryCheck() {
    _snapshotExpiryTimer?.cancel();
    final snapshots = <DriverWorkloadSnapshot?>[
      stateFor(DriverShipmentSection.activeWork).snapshot,
      stateFor(DriverShipmentSection.availableInstant).snapshot,
    ];
    final expiries =
        snapshots
            .map((snapshot) => snapshot?.expiresAt)
            .whereType<DateTime>()
            .toList();
    if (expiries.isEmpty) return;
    expiries.sort();
    final wait = expiries.first.difference(DateTime.now().toUtc());
    _snapshotExpiryTimer = Timer(
      wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 1),
      () {
        if (!canShowAvailableInstantOffers) notifyListeners();
      },
    );
  }

  DriverShipmentSectionFailure _failureFor(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return DriverShipmentSectionFailure.network;
        default:
          return DriverShipmentSectionFailure.generic;
      }
    }
    return DriverShipmentSectionFailure.generic;
  }

  bool _isSuccess(dynamic data) {
    if (data is! Map) return false;
    final success = data['success']?.toString().toLowerCase();
    final status = data['status']?.toString().toLowerCase();
    return data['success'] == true ||
        success == 'true' ||
        success == '1' ||
        status == 'success';
  }

  /// Keep diagnostics actionable without writing response messages, shipment
  /// rows, session data, or customer data to device logs.
  String? _safeResponseCode(dynamic data) {
    if (data is! Map) return null;
    final code = data['code'];
    if (code is! String || !RegExp(r'^[A-Z0-9_]{1,80}$').hasMatch(code)) {
      return null;
    }
    return code;
  }

  @override
  void clearUserState() {
    _snapshotExpiryTimer?.cancel();
    _snapshotExpiryTimer = null;
    for (final timer in _searchTimers.values) {
      timer?.cancel();
    }
    for (final section in DriverShipmentSection.values) {
      _states[section] = DriverShipmentSectionState(section: section);
      _inFlight[section] = false;
      _requestVersions[section] = (_requestVersions[section] ?? 0) + 1;
    }
    _authenticatedDriverId = null;
  }

  @override
  void dispose() {
    _snapshotExpiryTimer?.cancel();
    for (final timer in _searchTimers.values) {
      timer?.cancel();
    }
    super.dispose();
  }
}
