import 'dart:async';
import 'dart:developer';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/services/request_id_service.dart';
import 'package:blockatie/utils/app_utils.dart';
import 'package:blockatie/utils/driver_shipment_list_rules.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/dialoges/alert_dialoge.dart';
import 'package:blockatie/views/dialoges/shipment_accept_dialog.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ShipmentActionResult {
  const ShipmentActionResult({
    required this.success,
    required this.message,
    this.code,
    this.httpStatus,
    this.unconfirmed = false,
  });

  final bool success;
  final String message;

  /// The server's stable outcome code, when it sent one. The UI reconciles on
  /// this rather than on wording, which is localized and may change.
  final String? code;

  /// The HTTP status of the server's reply, or null when none arrived.
  final int? httpStatus;

  /// True when the request may have reached the server but no reply came back
  /// (timeout, dropped connection). The outcome is unknown: the caller has to
  /// read the shipment again rather than assume success or failure, and must
  /// not resend on its own.
  final bool unconfirmed;

  /// Outcomes that mean the shipment is gone: whatever is on screen for it is
  /// already wrong and has to be refetched rather than left for the driver to
  /// tap again.
  bool get shipmentNoLongerAvailable =>
      code == 'SHIPMENT_ALREADY_ACCEPTED' || code == 'SHIPMENT_NOT_AVAILABLE';

  /// The shipment changed on the server between what this screen shows and
  /// the request (complete_shipment_driver.php answers 409, or 200 with these
  /// codes on a server older than release B1).
  bool get isStateConflict =>
      httpStatus == 409 ||
      code == 'INVALID_STATUS' ||
      code == 'SHIPMENT_STATE_CONFLICT' ||
      code == 'REQUEST_IN_PROGRESS' ||
      code == 'REQUEST_ID_CONFLICT';
}

class ShipmentInstantprovider extends UserScopedNotifier with Helper {
  static const Duration _arrivalPositionTimeout = Duration(seconds: 8);
  static const Duration _arrivalRequestTimeout = Duration(seconds: 12);
  static const Duration _cacheDuration = Duration(seconds: 20);
  static const Duration _searchDebounce = Duration(milliseconds: 400);
  static const Set<int> _finalStatusIds = <int>{6, 7, 8, 11};

  /// `_currentDriverId` is the identity this cache was built for, so it must be
  /// dropped with the data it describes. The page rows carry recipient PII, and
  /// clearing `_lastFetchAt`/`_lastFetchKey` drops the cache window too, so the
  /// next driver can never be served the previous one's page.
  @override
  void clearUserState() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    _workloadSnapshotExpiryTimer?.cancel();
    _workloadSnapshotExpiryTimer = null;
    shipmentInstantResponse = null;
    _pageShipments = <Shipment>[];
    _serverActiveInstant = null;
    _pinnedActiveInstantOverride = null;
    _currentDriverId = null;
    _currentPage = 1;
    _totalCount = 0;
    _totalPages = 0;
    _searchQuery = '';
    _isFetchingShipments = false;
    _lastFetchAt = null;
    _lastFetchKey = null;
    _driverWorkloadSnapshot = null;
    _busyShipmentIds.clear();
    isLoading = false;
    isshipmentArrived = null;
    errorMessage = null;
    isPageChanging = false;
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _workloadSnapshotExpiryTimer?.cancel();
    super.dispose();
  }

  String _shipmentScope = 'all';
  String get shipmentScope => _shipmentScope;
  Future<void> selectShipmentScope(String scope) async {
    if (!const {'all', 'instant', 'scheduled', 'other'}.contains(scope)) return;
    if (_shipmentScope != scope) {
      resetUserState();
      _shipmentScope = scope;
    }
    await getShipmentsInstant(force: true);
  }

  ShipmentsResponse? shipmentInstantResponse;

  /// Rows for the page currently on screen. The backend decides what a page
  /// contains; nothing is sliced locally any more.
  List<Shipment> _pageShipments = <Shipment>[];

  /// The driver's live instant job, delivered outside pagination so the pinned
  /// card survives page navigation.
  Shipment? _serverActiveInstant;

  Shipment? _pinnedActiveInstantOverride;
  int? _currentDriverId;

  int _currentPage = 1;

  /// Rows requested per page. Matches the normal shipments list, and is well
  /// inside the backend's 50-row cap.
  final int _itemsPerPage = 5;

  /// Populated from the server's pagination block.
  int _totalCount = 0;
  int _totalPages = 0;

  String _searchQuery = '';
  Timer? _searchDebounceTimer;
  Timer? _workloadSnapshotExpiryTimer;
  bool _isFetchingShipments = false;
  DateTime? _lastFetchAt;

  /// Cache is keyed by what was actually requested, so changing page or search
  /// always refetches instead of re-showing the previous page.
  String? _lastFetchKey;
  final Set<int> _busyShipmentIds = <int>{};

  DriverWorkloadSnapshot? _driverWorkloadSnapshot;

  bool isLoading = false;
  bool? isshipmentArrived;
  String? errorMessage;

  int get itemsPerPage => _itemsPerPage;
  int get currentPage => _currentPage;
  String get searchQuery => _searchQuery;
  bool get hasLoaded => shipmentInstantResponse != null;
  bool get hasError => errorMessage != null && errorMessage!.trim().isNotEmpty;

  /// The offer surface is a server-authorized capability, not a conclusion
  /// from the rows currently on screen. This is false for loading, failures,
  /// old responses and backends that have not yet supplied the full-workload
  /// snapshot contract.
  bool get canShowAvailableInstantOffers {
    final driverId = _currentDriverId;
    final snapshot = _driverWorkloadSnapshot;
    return !isLoading &&
        driverId != null &&
        snapshot != null &&
        snapshot.provesNoActiveOperationalWorkFor(driverId, DateTime.now());
  }

  /// The endpoint currently returns a mixed page (offers and this driver's
  /// already-assigned rows), so its `pagination.total` is not an Available
  /// aggregate. Count only the offers this page can prove are actionable rather
  /// than present a misleading total to the driver.
  int get totalCount => availableInstantShipments.length;

  int get totalPages => _totalPages == 0 ? 1 : _totalPages;

  /// The page rows plus the pinned job, so accept/status bookkeeping can still
  /// look a shipment up by id regardless of which list it came from.
  List<Shipment> get allShipments => <Shipment>[
    if (_serverActiveInstant != null) _serverActiveInstant!,
    ..._pageShipments,
  ];

  /// The server sends the pinned job in its own field, so it no longer depends
  /// on the whole dataset being loaded. An action contract is required even for
  /// a pinned row: a stale response must not keep an old assignment active.
  Shipment? get activeInstantShipment {
    final fromServer = _serverActiveInstant;
    if (fromServer != null && _isActiveInstantShipment(fromServer)) {
      return fromServer;
    }

    final localPinned = _pinnedActiveInstantOverride;
    if (localPinned != null && _isActiveInstantShipment(localPinned)) {
      return localPinned;
    }

    return null;
  }

  bool get hasActiveInstantShipment => activeInstantShipment != null;

  /// This driver's additional instant assignments from the current response.
  /// The pinned assignment is rendered separately. A direct Admin assignment
  /// therefore never falls through to the Available section.
  List<Shipment> get activeInstantShipments {
    final activeInstant = activeInstantShipment;
    return _pageShipments
        .where(_isActiveInstantShipment)
        .where((shipment) => shipment.id != activeInstant?.id)
        .toList();
  }

  /// The current page's genuinely claimable instant offers. The backend's
  /// signed action contract covers expiry, withdrawal, dispatch reservation,
  /// subscription and concurrent-acceptance policy; absent or stale contracts
  /// fail closed.
  List<Shipment> get availableInstantShipments =>
      _pageShipments
          .where(DriverShipmentListRules.isAvailableInstantOffer)
          .toList();

  /// Backwards-compatible name consumed by the Available list UI.
  List<Shipment> get displayShipments => availableInstantShipments;

  bool _isActiveInstantShipment(Shipment shipment) {
    return shipment.deliveryTypeId == 1 &&
        DriverShipmentListRules.isActiveForCurrentDriver(
          shipment,
          _currentDriverId,
        );
  }

  bool _isFinalStatus(Shipment shipment) {
    final statusId =
        shipment.shipmentStatusId != 0
            ? shipment.shipmentStatusId
            : shipment.shipmentStatus;
    return _finalStatusIds.contains(statusId);
  }

  /// Already one server page. Nothing is sliced here.
  List<Shipment> get paginatedShipments => displayShipments;

  List<Shipment> get currentShipments => paginatedShipments;

  /// Search runs on the backend so it still spans every available shipment
  /// rather than just the loaded page. Debounced because the search field fires
  /// this on every keystroke.
  void setSearchQuery(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == _searchQuery) return;

    _searchQuery = normalized;
    _currentPage = 1;
    notifyListeners();

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      unawaited(getShipmentsInstant(force: true, page: 1));
    });
  }

  /// === PAGINATION ===
  /// Each of these fetches the target page; pages are never sliced locally.

  /// True only while an already-loaded page is being replaced by another. The
  /// rows stay on screen and the pager is disabled, rather than blanking a
  /// list the driver is reading.
  bool isPageChanging = false;

  void setPage(int page) {
    if (page < 1 || page == _currentPage) return;
    if (_totalPages > 0 && page > _totalPages) return;
    // A second tap while a page is in flight would be dropped by the fetch
    // guard anyway, but silently: refusing here keeps `currentPage` and the
    // rows on screen describing the same page throughout.
    if (_isFetchingShipments) return;

    // `_currentPage` is advanced by the response, not by the tap.
    unawaited(getShipmentsInstant(page: page, force: true));
  }

  void setCurrentPage(int page) => setPage(page);

  void goToNextPage() {
    if (_currentPage < totalPages) {
      setPage(_currentPage + 1);
    }
  }

  void goToPreviousPage() => goToPrevPage();

  void goToPrevPage() {
    if (_currentPage > 1) {
      setPage(_currentPage - 1);
    }
  }

  bool isShipmentBusy(int? shipmentId) {
    return shipmentId != null && _busyShipmentIds.contains(shipmentId);
  }

  /// Pull-to-refresh: always returns the driver to page 1 of the current
  /// search, matching the normal shipments list.
  Future<void> refresh() async {
    _currentPage = 1;
    await getShipmentsInstant(force: true, page: 1);
  }

  /// Loads one page from the backend.
  ///
  /// [page] defaults to [currentPage], so existing callers keep working and
  /// simply refresh whatever page is on screen.
  Future<void> getShipmentsInstant({bool force = false, int? page}) async {
    if (_isFetchingShipments) return;

    final requestedPage = page ?? _currentPage;
    final fetchKey = '$_shipmentScope|$requestedPage|$_searchQuery';
    if (!force && hasLoaded && _isCacheFresh && _lastFetchKey == fetchKey) {
      return;
    }

    // Guard the write-back: a response from the previous driver, or from a page
    // the user has already navigated away from, must not land.
    final generation = stateGeneration;

    // The page the driver is looking at right now. It stays authoritative
    // until the new one actually arrives, so a failed page change can never
    // leave the pager pointing at a page whose rows are not on screen.
    final previousPage = _currentPage;
    final hadWorkloadSnapshot = _driverWorkloadSnapshot != null;

    // A work snapshot is valid only for the response that supplied it. Never
    // carry it across a refresh, failed request, scope change or session
    // change and accidentally make offers visible from stale state.
    _clearDriverWorkloadSnapshot();

    _isFetchingShipments = true;
    isLoading = !hasLoaded || _lastFetchKey != fetchKey;
    isPageChanging = isLoading && hasLoaded;
    errorMessage = null;
    if (isLoading || hadWorkloadSnapshot) {
      notifyListeners();
    }

    try {
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();
      if (!acceptsState(generation)) return;
      _currentDriverId = int.tryParse(driverId?.toString() ?? '');

      if (driverId == null || apiKey == null || apiKey.trim().isEmpty) {
        errorMessage = 'Missing driver session';
        _currentPage = previousPage;
        return;
      }

      final response = await sessionDio().post(
        AppUrls.getShipmentinstant,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {
          'driver_id': driverId,
          'shipment_scope': _shipmentScope,
          'page': requestedPage,
          'limit': _itemsPerPage,
          if (_searchQuery.isNotEmpty) 'search': _searchQuery,
        },
      );

      // The session may have ended while this request was in flight; a reply
      // addressed to the previous driver must never populate the next one.
      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 && _isSuccess(data)) {
        if (data is! Map) {
          errorMessage = 'Invalid server response';
          _currentPage = previousPage;
          return;
        }

        final parsed = ShipmentsResponse.fromJson(
          Map<String, dynamic>.from(data),
        );
        shipmentInstantResponse = parsed;
        _pageShipments = parsed.shipments;
        _serverActiveInstant = parsed.activeInstant;
        _setDriverWorkloadSnapshot(parsed.driverWorkloadSnapshot);
        _applyPagination(parsed.pagination, requestedPage);

        _reconcilePinnedActiveInstantOverride();
        _lastFetchAt = DateTime.now();
        _lastFetchKey = '$_shipmentScope|$_currentPage|$_searchQuery';
      } else {
        // Kept for logs only; the page words the failure itself so nothing
        // server-generated can reach the driver.
        errorMessage =
            _messageFrom(data) ?? 'Unable to load available instant shipments';
        _currentPage = previousPage;
      }
    } catch (e) {
      if (!acceptsState(generation)) return;
      errorMessage = 'Unable to load available instant shipments';
      _currentPage = previousPage;
      log('Instant shipments fetch failed: ${e.runtimeType}');
    } finally {
      if (acceptsState(generation)) {
        isLoading = false;
        isPageChanging = false;
        _isFetchingShipments = false;
        notifyListeners();
      } else {
        // clearUserState() already reset these for the new session.
        _isFetchingShipments = false;
      }
    }
  }

  /// Applies a parsed server page exactly as [getShipmentsInstant] does on a
  /// successful reply, minus the HTTP call.
  ///
  /// [generation] lets a test hand in a stale session generation to prove that
  /// a response belonging to a previous driver is refused.
  @visibleForTesting
  void applyServerPageForTest(
    ShipmentsResponse response, {
    required int requestedPage,
    int? driverId,
    int? generation,
  }) {
    if (generation != null && !acceptsState(generation)) return;

    _currentDriverId = driverId;
    shipmentInstantResponse = response;
    _pageShipments = response.shipments;
    _serverActiveInstant = response.activeInstant;
    _setDriverWorkloadSnapshot(response.driverWorkloadSnapshot);
    _applyPagination(response.pagination, requestedPage);
    _reconcilePinnedActiveInstantOverride();
    _lastFetchAt = DateTime.now();
    _lastFetchKey = '$_shipmentScope|$_currentPage|$_searchQuery';
    notifyListeners();
  }

  /// Adopts the server's page/total figures. Falls back to the requested page
  /// and the row count if an older backend omits the block.
  void _applyPagination(ShipmentsPagination? pagination, int requestedPage) {
    if (pagination != null) {
      _currentPage = pagination.page > 0 ? pagination.page : requestedPage;
      _totalCount = pagination.total;
      _totalPages =
          pagination.totalPages > 0
              ? pagination.totalPages
              : (_totalCount / _itemsPerPage).ceil();
      return;
    }

    _currentPage = requestedPage;
    _totalCount = _pageShipments.length;
    _totalPages = _pageShipments.isEmpty ? 0 : 1;
  }

  void _setDriverWorkloadSnapshot(DriverWorkloadSnapshot? snapshot) {
    _clearDriverWorkloadSnapshot();
    _driverWorkloadSnapshot = snapshot;

    final expiresAt = snapshot?.expiresAt;
    if (expiresAt == null) return;
    final untilExpiry = expiresAt.difference(DateTime.now().toUtc());
    if (untilExpiry <= Duration.zero) return;

    // Rebuild at expiry even if the driver leaves this page open. A cached
    // "no active work" answer must not keep the acceptance surface visible.
    _workloadSnapshotExpiryTimer = Timer(untilExpiry, () {
      if (identical(_driverWorkloadSnapshot, snapshot)) {
        _clearDriverWorkloadSnapshot();
        notifyListeners();
      }
    });
  }

  void _clearDriverWorkloadSnapshot() {
    _workloadSnapshotExpiryTimer?.cancel();
    _workloadSnapshotExpiryTimer = null;
    _driverWorkloadSnapshot = null;
  }

  bool get _isCacheFresh {
    final lastFetchAt = _lastFetchAt;
    if (lastFetchAt == null) return false;
    return DateTime.now().difference(lastFetchAt) < _cacheDuration;
  }

  Future<ShipmentActionResult> acceptShipment(
    int? shipmentId, {
    Shipment? acceptedShipment,
    String languageCode = 'en',
  }) async {
    final readinessFailure = _operationalReadinessFailure(languageCode);
    if (readinessFailure != null) return readinessFailure;
    final driverIdValue = await AuthService.getuserId();
    final driverId = int.tryParse(driverIdValue?.toString() ?? '');
    _currentDriverId = driverId ?? _currentDriverId;
    final result = await _postShipmentAction(
      shipmentId: shipmentId,
      endpoint: AppUrls.acceptShipment,
      fallbackFailure: _fallbackMessage(
        languageCode,
        en: 'Failed to accept shipment',
        ar: 'فشل قبول الشحنة',
      ),
      languageCode: languageCode,
    );

    if (result.success) {
      if (acceptedShipment != null && driverId != null) {
        _removeAcceptedOfferLocally(acceptedShipment);
      }
      unawaited(getShipmentsInstant(force: true));
      return ShipmentActionResult(
        success: true,
        code: result.code,
        message:
            result.message.trim().isEmpty
                ? _fallbackMessage(
                  languageCode,
                  en: 'Shipment accepted successfully',
                  ar: 'تم قبول الشحنة بنجاح',
                )
                : result.message,
      );
    }

    // The server has spoken: this shipment is gone. Refetch so the card the
    // driver just tapped cannot sit there inviting another attempt. Nothing is
    // assigned locally — the next response is the authority.
    if (result.shipmentNoLongerAvailable) {
      unawaited(getShipmentsInstant(force: true));
    }

    return result;
  }

  void _removeAcceptedOfferLocally(Shipment shipment) {
    if (shipment.id <= 0) return;

    // Acceptance is confirmed by its dedicated endpoint, but the next action
    // contract must still come from a fresh shipment response. Remove the
    // offer immediately so it cannot be claimed twice; do not manufacture an
    // active contract/status locally.
    _pageShipments.removeWhere((item) => item.id == shipment.id);
    _clearDriverWorkloadSnapshot();

    notifyListeners();
  }

  void _reconcilePinnedActiveInstantOverride() {
    final pinned = _pinnedActiveInstantOverride;
    if (pinned == null) return;

    Shipment? matchingServerShipment;
    for (final shipment in allShipments) {
      if (shipment.id == pinned.id) {
        matchingServerShipment = shipment;
        break;
      }
    }

    if (matchingServerShipment == null) return;

    if (_isActiveInstantShipment(matchingServerShipment)) {
      _pinnedActiveInstantOverride = null;
      return;
    }

    if (_isFinalStatus(matchingServerShipment)) {
      _pinnedActiveInstantOverride = null;
    }
  }

  void _updateAcceptedShipmentStatus(int shipmentId, int statusId) {
    _updatePinnedActiveInstantStatus(shipmentId, statusId);

    // The pinned job lives outside the page list, so keep it in step too.
    final serverActive = _serverActiveInstant;
    if (serverActive != null && serverActive.id == shipmentId) {
      _serverActiveInstant =
          _finalStatusIds.contains(statusId)
              ? null
              : serverActive.copyWith(
                shipmentStatus: statusId,
                shipmentStatusId: statusId,
                statusNameEn: _statusNameEn(statusId),
                statusNameAr: _statusNameAr(statusId),
                messageEn: _statusNameEn(statusId),
                messageAr: _statusNameAr(statusId),
                updatedAt: DateTime.now().toIso8601String(),
              );
    }

    final shipments = _pageShipments;
    final index = shipments.indexWhere((shipment) => shipment.id == shipmentId);
    if (index < 0) return;

    if (_finalStatusIds.contains(statusId)) {
      shipments.removeAt(index);
      return;
    }

    shipments[index] = shipments[index].copyWith(
      shipmentStatus: statusId,
      shipmentStatusId: statusId,
      statusNameEn: _statusNameEn(statusId),
      statusNameAr: _statusNameAr(statusId),
      messageEn: _statusNameEn(statusId),
      messageAr: _statusNameAr(statusId),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  void _updatePinnedActiveInstantStatus(int shipmentId, int statusId) {
    final pinned = _pinnedActiveInstantOverride;
    if (pinned == null || pinned.id != shipmentId) return;

    if (_finalStatusIds.contains(statusId)) {
      _pinnedActiveInstantOverride = null;
      return;
    }

    _pinnedActiveInstantOverride = pinned.copyWith(
      shipmentStatus: statusId,
      shipmentStatusId: statusId,
      statusNameEn: _statusNameEn(statusId),
      statusNameAr: _statusNameAr(statusId),
      messageEn: _statusNameEn(statusId),
      messageAr: _statusNameAr(statusId),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  String _statusNameEn(int statusId) {
    return switch (statusId) {
      2 => 'Accepted',
      4 => 'In Transit',
      10 => 'Awaiting Pickup',
      _ => 'Updated',
    };
  }

  String _statusNameAr(int statusId) {
    return switch (statusId) {
      2 => 'تم القبول',
      4 => 'في الطريق',
      10 => 'في انتظار الاستلام',
      _ => 'تم التحديث',
    };
  }

  Future<ShipmentActionResult> markArrivedAtStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    final readinessFailure = _operationalReadinessFailure(languageCode);
    if (readinessFailure != null) return readinessFailure;
    if (shipmentId == null || shipmentId <= 0) {
      return ShipmentActionResult(
        success: false,
        message: _fallbackMessage(
          languageCode,
          en: 'Shipment information is missing',
          ar: 'بيانات الشحنة غير متوفرة',
        ),
      );
    }

    if (isShipmentBusy(shipmentId)) {
      return ShipmentActionResult(
        success: false,
        message: _fallbackMessage(
          languageCode,
          en: 'Shipment request is already in progress',
          ar: 'جاري تنفيذ طلب هذه الشحنة',
        ),
      );
    }

    _busyShipmentIds.add(shipmentId);
    errorMessage = null;
    notifyListeners();

    try {
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (driverId == null || apiKey == null || apiKey.trim().isEmpty) {
        return ShipmentActionResult(
          success: false,
          message: _fallbackMessage(
            languageCode,
            en: 'Driver session is missing. Please login again.',
            ar: 'جلسة السائق غير متوفرة. يرجى تسجيل الدخول مرة أخرى.',
          ),
        );
      }

      final locationResult = await _readCurrentArrivalPosition(languageCode);
      final position = locationResult.position;
      if (position == null) {
        return ShipmentActionResult(
          success: false,
          message:
              locationResult.errorMessage ??
              _fallbackMessage(
                languageCode,
                en: 'Unable to read your current location.',
                ar: 'تعذر قراءة موقعك الحالي.',
              ),
        );
      }

      final latitude = position.latitude.toString();
      final longitude = position.longitude.toString();

      final requestData = {
        'shipment_id': shipmentId,
        'driver_id': driverId,
        'mark_arrived': 1,
        'arrived_status_id': 10,
        'latitude': latitude,
        'longitude': longitude,
        'lat': latitude,
        'lng': longitude,
        'driver_latitude': latitude,
        'driver_longitude': longitude,
      };
      final lease = RequestIdService.acquire(
        operation: 'driver.markArrivedAtStore',
        payload: requestData,
      );
      final response = await sessionDio(
        BaseOptions(
          connectTimeout: _arrivalRequestTimeout,
          receiveTimeout: _arrivalRequestTimeout,
          sendTimeout: _arrivalRequestTimeout,
        ),
      ).post(
        AppUrls.checkDriverArrival,
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
            ...lease.headers(),
          },
        ),
        data: requestData,
      );
      lease.complete();

      final data = response.data;
      if (response.statusCode == 200 &&
          data is Map &&
          _isSuccess(data) &&
          data['within_radius'] == true) {
        _updateAcceptedShipmentStatus(shipmentId, 10);
        await getShipmentsInstant(force: true);
        return ShipmentActionResult(
          success: true,
          code: _codeFrom(data),
          message:
              _messageFrom(data, languageCode: languageCode) ??
              _fallbackMessage(
                languageCode,
                en: 'Arrived at store successfully',
                ar: 'تم تأكيد الوصول إلى المتجر',
              ),
        );
      }

      return ShipmentActionResult(
        success: false,
        code: _codeFrom(data),
        message:
            _distanceMessageFrom(data, languageCode) ??
            _messageFrom(data, languageCode: languageCode) ??
            _fallbackMessage(
              languageCode,
              en: 'You are not close enough to the store yet.',
              ar: 'لم تصل إلى نطاق المتجر بعد.',
            ),
      );
    } on DioException catch (e) {
      // check_driver_arrival.php sends some refusals as 403/404/409 (another
      // driver's shipment, a removed one, a request already running). Those
      // arrive here as exceptions; their code and status are kept so the
      // screen can tell a stale shipment from a network failure.
      final response = e.response;
      if (response == null || e.error is SessionChanged) {
        log('Store arrival action failed: ${e.type}');
        return ShipmentActionResult(
          success: false,
          message: _fallbackMessage(
            languageCode,
            en: 'Unable to confirm store arrival',
            ar: 'تعذر تأكيد الوصول إلى المتجر',
          ),
        );
      }
      return ShipmentActionResult(
        success: false,
        code: _codeFrom(response.data),
        httpStatus: response.statusCode,
        message:
            _messageFrom(response.data, languageCode: languageCode) ??
            _fallbackMessage(
              languageCode,
              en: 'Unable to confirm store arrival',
              ar: 'تعذر تأكيد الوصول إلى المتجر',
            ),
      );
    } catch (e) {
      log('Store arrival action failed: ${e.runtimeType}');
      return ShipmentActionResult(
        success: false,
        message: _fallbackMessage(
          languageCode,
          en: 'Unable to confirm store arrival',
          ar: 'تعذر تأكيد الوصول إلى المتجر',
        ),
      );
    } finally {
      _busyShipmentIds.remove(shipmentId);
      notifyListeners();
    }
  }

  Future<_ArrivalPositionResult> _readCurrentArrivalPosition(
    String languageCode,
  ) async {
    try {
      final storedDriverPosition = await _readStoredDriverPosition();
      if (storedDriverPosition != null) {
        return _ArrivalPositionResult(position: storedDriverPosition);
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _ArrivalPositionResult(
          errorMessage: _fallbackMessage(
            languageCode,
            en:
                'Please enable location services to confirm arrival at the store.',
            ar: 'يرجى تفعيل خدمة الموقع لتأكيد الوصول إلى المتجر.',
          ),
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return _ArrivalPositionResult(
          errorMessage: _fallbackMessage(
            languageCode,
            en: 'Please allow location access to confirm arrival at the store.',
            ar: 'يرجى السماح بالوصول للموقع لتأكيد الوصول إلى المتجر.',
          ),
        );
      }

      if (permission == LocationPermission.deniedForever) {
        return _ArrivalPositionResult(
          errorMessage: _fallbackMessage(
            languageCode,
            en:
                'Location permission is permanently denied. Please enable it from settings.',
            ar: 'صلاحية الموقع مرفوضة نهائياً. يرجى تفعيلها من الإعدادات.',
          ),
        );
      }

      final lastKnownPosition = await Geolocator.getLastKnownPosition();
      if (lastKnownPosition != null &&
          (!kReleaseMode || !lastKnownPosition.isMocked) &&
          _isValidCoordinate(
            lastKnownPosition.latitude,
            lastKnownPosition.longitude,
          )) {
        return _ArrivalPositionResult(position: lastKnownPosition);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _arrivalPositionTimeout,
        ),
      );

      if (kReleaseMode && position.isMocked) {
        return _ArrivalPositionResult(
          errorMessage: _fallbackMessage(
            languageCode,
            en: 'Mocked location is not allowed for store arrival.',
            ar: 'لا يمكن استخدام موقع وهمي لتأكيد الوصول إلى المتجر.',
          ),
        );
      }

      if (!_isValidCoordinate(position.latitude, position.longitude)) {
        return _ArrivalPositionResult(
          errorMessage: _fallbackMessage(
            languageCode,
            en: 'Current location is not valid. Please try again.',
            ar: 'الموقع الحالي غير صالح. يرجى المحاولة مرة أخرى.',
          ),
        );
      }

      return _ArrivalPositionResult(position: position);
    } on TimeoutException {
      return _ArrivalPositionResult(
        errorMessage: _fallbackMessage(
          languageCode,
          en: 'Location request timed out. Please try again.',
          ar: 'انتهت مهلة تحديد الموقع. يرجى المحاولة مرة أخرى.',
        ),
      );
    } catch (e) {
      log('Arrival location read failed: ${e.runtimeType}');
      return _ArrivalPositionResult(
        errorMessage: _fallbackMessage(
          languageCode,
          en: 'Unable to read your current location.',
          ar: 'تعذر قراءة موقعك الحالي.',
        ),
      );
    }
  }

  Future<Position?> _readStoredDriverPosition() async {
    final session = await AuthService.getSessionSnapshot();
    if (session.isAuthenticated) {
      try {
        final response = await sessionDio().post(
          AppUrls.profileInfo,
          options: Options(
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-API-KEY': session.apiKey,
            },
          ),
          data: {'driverId': session.driverId},
        );

        final data = response.data;
        if (response.statusCode == 200 &&
            data is Map &&
            data['status']?.toString().toLowerCase() == 'success') {
          final profile =
              data['profile'] is Map<String, dynamic>
                  ? data['profile'] as Map<String, dynamic>
                  : <String, dynamic>{};
          final profileLat = double.tryParse(
            profile['latitude']?.toString() ?? '',
          );
          final profileLng = double.tryParse(
            profile['longitude']?.toString() ?? '',
          );

          if (profileLat != null &&
              profileLng != null &&
              _isValidCoordinate(profileLat, profileLng)) {
            return Position(
              longitude: profileLng,
              latitude: profileLat,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
          }
        }
      } catch (_) {
        // Fall back to locally cached coordinates below.
      }
    }

    final latitudeValue = await AuthService.getStoredLatitude();
    final longitudeValue = await AuthService.getStoredLongitude();
    final latitude = double.tryParse(latitudeValue ?? '');
    final longitude = double.tryParse(longitudeValue ?? '');
    if (latitude == null || longitude == null) return null;
    if (!_isValidCoordinate(latitude, longitude)) return null;

    return Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  bool _isValidCoordinate(double latitude, double longitude) {
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    if (latitude == 0 && longitude == 0) return false;
    return true;
  }

  /// Marks a shipment collected from the store.
  ///
  /// The server owns the from-check: mark_as_arrived_driver.php accepts only
  /// status 2 or 10 and sets 4, so the caller does not pass a status.
  Future<ShipmentActionResult> pickupShipmentFromStore(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    final readinessFailure = _operationalReadinessFailure(languageCode);
    if (readinessFailure != null) return readinessFailure;
    // Always the dedicated endpoint. Status 10 used to be routed through the
    // generic status endpoint with status_id 4, which that endpoint refuses —
    // its targets are the off-ramps 7/8/9 only — so a driver who had confirmed
    // arrival could never mark the shipment picked up. mark_as_arrived_driver
    // now accepts 2 or 10 and owns the from-check, the ownership check and the
    // idempotency record.
    final result = await _postShipmentAction(
      shipmentId: shipmentId,
      endpoint: AppUrls.markAsReceive,
      fallbackFailure: _fallbackMessage(
        languageCode,
        en: 'Unable to pickup shipment from store',
        ar: 'تعذر استلام الشحنة من المتجر',
      ),
      languageCode: languageCode,
    );

    if (result.success) {
      _updateAcceptedShipmentStatus(shipmentId ?? 0, 4);
      await getShipmentsInstant(force: true);
    }

    return result;
  }

  Future<void> checkDriverArrival({
    required int shipmentId,
    required BuildContext context,
  }) async {
    final languageCode = context.locale.languageCode;

    try {
      AppUtils.showLoaderDialog();
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (driverId == null || apiKey == null || apiKey.trim().isEmpty) {
        AppUtils.hideLoaderDialog();
        return;
      }

      final response = await sessionDio(
        BaseOptions(
          connectTimeout: _arrivalRequestTimeout,
          receiveTimeout: _arrivalRequestTimeout,
          sendTimeout: _arrivalRequestTimeout,
        ),
      ).post(
        AppUrls.checkDriverArrival,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'driver_id': driverId, 'shipment_id': shipmentId},
      );

      AppUtils.hideLoaderDialog();
      final data = response.data;
      if (response.statusCode == 200 && data is Map) {
        if (data['success'] == true) {
          Shipment? shipment;
          for (final item in allShipments) {
            if (item.id == shipmentId) {
              shipment = item;
              break;
            }
          }
          shipment?.withinRadius = data['within_radius'] == true;

          if (shipment?.withinRadius != true) {
            _showAlert(
              tr('store_arrival'),
              _messageFrom(data, languageCode: languageCode) ??
                  tr('something_went_wrong'),
            );
          }
        } else {
          _showAlert(
            tr('error'),
            _messageFrom(data, languageCode: languageCode) ??
                tr('something_went_wrong'),
            showBtn: false,
          );
        }
      } else {
        _showAlert(tr('error'), tr('something_went_wrong'), showBtn: false);
      }
    } catch (e) {
      AppUtils.hideLoaderDialog();
      log('Arrival check failed: ${e.runtimeType}');
    }
  }

  Future<void> markShipmentAsReceived(int? shipmentId) async {
    final result = await _postShipmentAction(
      shipmentId: shipmentId,
      endpoint: AppUrls.markAsReceive,
      fallbackFailure: 'Shipment arrival update failed',
    );

    if (result.success) {
      isshipmentArrived = true;
      await getShipmentsInstant(force: true);
      _showSuccess(
        tr('success'),
        result.message.trim().isEmpty
            ? 'Shipment marked as arrived.'
            : result.message,
      );
    } else {
      _showAlert(tr('info'), result.message, showBtn: false);
    }
  }

  static const Duration _deliveryRequestTimeout = Duration(seconds: 30);

  /// Completed (11), the status complete_shipment_driver.php sets.
  static const int _deliveredStatusId = 11;

  /// HTTP client for [deliverShipment]; replaced in tests. Always wrapped in
  /// the session interceptor, so a 401 or DRIVER_INACTIVE still ends the
  /// session exactly as on every other driver request.
  @visibleForTesting
  Dio Function()? deliveryDioFactory;

  /// "Delivered" (تم التسليم): in transit (4) -> Completed (11) through
  /// complete_shipment_driver.php.
  ///
  /// Server-authoritative: the server checks the API key against the driver id
  /// (the id is the session's own, read from secure storage, never typed in),
  /// the assignment and the from-status under a row lock, and records the
  /// money and the merchant notification. This method only reports what the
  /// server answered; nothing is marked delivered here before it says so.
  ///
  /// Concurrency: one request per shipment at a time (the busy set), and the
  /// request carries an X-Request-ID lease. A definitive reply releases the
  /// lease. A timeout or dropped connection keeps it and is reported as
  /// [ShipmentActionResult.unconfirmed]: nothing is resent automatically, the
  /// caller re-reads the shipment, and a manual retry reuses the same request
  /// id, which the server answers with SHIPMENT_COMPLETE_ALREADY_PROCESSED if
  /// the first attempt was in fact recorded.
  Future<ShipmentActionResult> deliverShipment(
    int? shipmentId, {
    String languageCode = 'en',
  }) async {
    String text(String en, String ar) =>
        _fallbackMessage(languageCode, en: en, ar: ar);

    final readinessFailure = _operationalReadinessFailure(languageCode);
    if (readinessFailure != null) return readinessFailure;

    if (shipmentId == null || shipmentId <= 0) {
      return ShipmentActionResult(
        success: false,
        message: text(
          'Shipment information is missing',
          'بيانات الشحنة غير متوفرة',
        ),
      );
    }
    if (isShipmentBusy(shipmentId)) {
      return ShipmentActionResult(
        success: false,
        code: 'REQUEST_IN_PROGRESS',
        message: text(
          'Shipment request is already in progress',
          'جاري تنفيذ طلب هذه الشحنة',
        ),
      );
    }

    _busyShipmentIds.add(shipmentId);
    notifyListeners();

    // The session this request belongs to. A reply that arrives after a logout
    // or an account switch belongs to nobody and is never reported as success.
    final generation = UserSessionState.generation;
    final sessionChanged = ShipmentActionResult(
      success: false,
      code: 'SESSION_CHANGED',
      message: text('Session ended.', 'انتهت الجلسة.'),
    );

    try {
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();
      if (!UserSessionState.isCurrent(generation)) return sessionChanged;
      if (driverId == null ||
          driverId.trim().isEmpty ||
          apiKey == null ||
          apiKey.trim().isEmpty) {
        return ShipmentActionResult(
          success: false,
          message: text(
            'Driver session is missing. Please login again.',
            'جلسة السائق غير متوفرة. يرجى تسجيل الدخول مرة أخرى.',
          ),
        );
      }

      final payload = <String, dynamic>{
        'shipment_id': shipmentId,
        'driver_id': driverId,
      };
      final lease = RequestIdService.acquire(
        operation: AppUrls.completeShipment,
        payload: payload,
      );
      final dio = protectSessionDio(
        deliveryDioFactory?.call() ??
            Dio(
              BaseOptions(
                connectTimeout: _deliveryRequestTimeout,
                sendTimeout: _deliveryRequestTimeout,
                receiveTimeout: _deliveryRequestTimeout,
              ),
            ),
      );

      final Response<dynamic> response;
      try {
        response = await dio.post(
          AppUrls.completeShipment,
          options: Options(
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-API-KEY': apiKey,
              ...lease.headers(),
            },
            // Every status is read here: the code decides, not Dio.
            validateStatus: (_) => true,
          ),
          data: payload,
        );
      } on DioException catch (e) {
        if (e.error is SessionChanged ||
            !UserSessionState.isCurrent(generation)) {
          // The session ended while waiting; this reply belongs to nobody.
          return sessionChanged;
        }
        // No reply: the delivery may or may not have been recorded. The lease
        // is kept so a manual retry is idempotent on the server.
        log('Delivery request got no reply: ${e.type}');
        return ShipmentActionResult(
          success: false,
          unconfirmed: true,
          message: text(
            'No reply from the server. The delivery may not be saved; checking the shipment.',
            'لم يصل رد من الخادم. قد لا يكون التسليم قد حُفظ؛ جارٍ التحقق من الشحنة.',
          ),
        );
      }

      // A reply arrived, so this request id is settled either way.
      lease.complete();
      if (!UserSessionState.isCurrent(generation)) return sessionChanged;
      final data = response.data;
      final code = _codeFrom(data);
      final status = response.statusCode;
      final serverSaysSuccess =
          (status ?? 0) >= 200 &&
          (status ?? 0) < 300 &&
          _isSuccess(data) &&
          (code == null ||
              code == 'SHIPMENT_COMPLETED' ||
              code == 'SHIPMENT_COMPLETE_ALREADY_PROCESSED');

      if (serverSaysSuccess) {
        // Confirmed by the server: drop the job from the active list now and
        // re-read the page; the refreshed rows are the authority.
        _updateAcceptedShipmentStatus(shipmentId, _deliveredStatusId);
        unawaited(getShipmentsInstant(force: true));
        return ShipmentActionResult(
          success: true,
          code: code,
          httpStatus: status,
          message:
              _messageFrom(data, languageCode: languageCode) ??
              text(
                'Shipment has been marked as delivered successfully.',
                'تم تعليم الشحنة كمسلّمة بنجاح.',
              ),
        );
      }

      return ShipmentActionResult(
        success: false,
        code: code,
        httpStatus: status,
        message: _deliveryFailureMessage(code, status, data, languageCode),
      );
    } catch (e) {
      log('Delivery action failed: ${e.runtimeType}');
      return ShipmentActionResult(
        success: false,
        message: text(
          'Unable to mark the shipment as delivered.',
          'تعذر تعليم الشحنة كمسلّمة.',
        ),
      );
    } finally {
      _busyShipmentIds.remove(shipmentId);
      notifyListeners();
    }
  }

  /// The driver's wording for a refused delivery, from the server's code
  /// first (the codes are stable across server versions), then its localized
  /// text, then a generic line by HTTP status.
  String _deliveryFailureMessage(
    String? code,
    int? status,
    dynamic data,
    String languageCode,
  ) {
    String text(String en, String ar) =>
        _fallbackMessage(languageCode, en: en, ar: ar);
    switch (code) {
      case 'INVALID_STATUS':
      case 'SHIPMENT_STATE_CONFLICT':
        return text(
          'This shipment\'s status changed, so it was not marked as delivered. It has been refreshed.',
          'تغيّرت حالة هذه الشحنة، لذلك لم يتم تعليمها كمسلّمة. تم تحديثها.',
        );
      case 'REQUEST_IN_PROGRESS':
        return text(
          'This delivery is already being processed. Please wait.',
          'هذا التسليم قيد المعالجة بالفعل. يرجى الانتظار.',
        );
      case 'NOT_ASSIGNED':
        return text(
          'This shipment is no longer assigned to you.',
          'هذه الشحنة لم تعد مسندة إليك.',
        );
      case 'SHIPMENT_NOT_FOUND':
        return text(
          'This shipment was not found.',
          'لم يتم العثور على هذه الشحنة.',
        );
      case 'DRIVER_SUBSCRIPTION_INACTIVE':
      case 'DRIVER_INACTIVE':
      case 'API_KEY_MISSING':
      case 'INVALID_DRIVER_AUTH':
      case 'REQUEST_ID_CONFLICT':
        return _messageForCode(code, languageCode) ??
            _messageFrom(data, languageCode: languageCode) ??
            text(
              'You cannot deliver this shipment.',
              'لا يمكنك تسليم هذه الشحنة.',
            );
    }
    return _messageFrom(data, languageCode: languageCode) ??
        ((status ?? 0) >= 500
            ? text(
              'The server could not save the delivery. Please try again.',
              'تعذر على الخادم حفظ التسليم. يرجى المحاولة مرة أخرى.',
            )
            : text(
              'Unable to mark the shipment as delivered.',
              'تعذر تعليم الشحنة كمسلّمة.',
            ));
  }

  Future<ShipmentActionResult> _postShipmentAction({
    required int? shipmentId,
    required String endpoint,
    required String fallbackFailure,
    String languageCode = 'en',
    Map<String, dynamic>? extraData,
    VoidCallback? onSuccess,
  }) async {
    final readinessFailure = _operationalReadinessFailure(languageCode);
    if (readinessFailure != null) return readinessFailure;

    if (shipmentId == null || shipmentId <= 0) {
      return ShipmentActionResult(
        success: false,
        message: _fallbackMessage(
          languageCode,
          en: 'Shipment information is missing',
          ar: 'بيانات الشحنة غير متوفرة',
        ),
      );
    }

    if (isShipmentBusy(shipmentId)) {
      return ShipmentActionResult(
        success: false,
        message: _fallbackMessage(
          languageCode,
          en: 'Shipment request is already in progress',
          ar: 'جاري تنفيذ طلب هذه الشحنة',
        ),
      );
    }

    _busyShipmentIds.add(shipmentId);
    errorMessage = null;
    notifyListeners();

    try {
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (driverId == null || apiKey == null || apiKey.trim().isEmpty) {
        return ShipmentActionResult(
          success: false,
          message: _fallbackMessage(
            languageCode,
            en: 'Driver session is missing. Please login again.',
            ar: 'جلسة السائق غير متوفرة. يرجى تسجيل الدخول مرة أخرى.',
          ),
        );
      }

      final requestData = {
        'shipment_id': shipmentId,
        'driver_id': driverId,
        if (extraData != null) ...extraData,
      };
      final lease = RequestIdService.acquire(
        operation: endpoint,
        payload: requestData,
      );
      final response = await sessionDio().post(
        endpoint,
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
            ...lease.headers(),
          },
        ),
        data: requestData,
      );
      lease.complete();

      final data = response.data;
      if (response.statusCode == 200 && _isSuccess(data)) {
        onSuccess?.call();
        return ShipmentActionResult(
          success: true,
          code: _codeFrom(data),
          message: _messageFrom(data, languageCode: languageCode) ?? '',
        );
      }

      return ShipmentActionResult(
        success: false,
        code: _codeFrom(data),
        message: _outcomeMessage(
          data,
          languageCode: languageCode,
          fallback: fallbackFailure,
        ),
      );
    } catch (e) {
      log('Shipment action failed: ${e.runtimeType}');
      return ShipmentActionResult(success: false, message: fallbackFailure);
    } finally {
      _busyShipmentIds.remove(shipmentId);
      notifyListeners();
    }
  }

  ShipmentActionResult? _operationalReadinessFailure(String languageCode) {
    if (OperationalReadinessProvider.currentState ==
        OperationalReadinessState.ready) {
      return null;
    }
    return ShipmentActionResult(
      success: false,
      code: 'DRIVER_NOT_OPERATIONALLY_READY',
      message: _fallbackMessage(
        languageCode,
        en: 'Enable location and disable VPN before continuing.',
        ar: 'فعّل الموقع وأوقف الـ VPN قبل المتابعة.',
      ),
    );
  }

  bool _isSuccess(dynamic data) {
    if (data is! Map) return false;

    final success = data['success']?.toString().toLowerCase();
    final status = data['status']?.toString().toLowerCase();
    final code = data['code']?.toString().toLowerCase();

    return data['success'] == true ||
        success == 'true' ||
        success == '1' ||
        status == 'success' ||
        code == 'success';
  }

  /// The server's wording for the driver's language, or nothing.
  ///
  /// Deliberately never falls through to the other language or to the generic
  /// `message` field: the endpoint localizes `message` from a `lang` the app
  /// does not send, so borrowing it would put English in an Arabic snackbar.
  /// When this returns null the caller words the outcome itself, by code.
  String? _messageFrom(dynamic data, {String languageCode = 'en'}) {
    if (data is! Map) return null;

    final localized =
        languageCode == 'ar' ? data['message_ar'] : data['message_en'];
    final value = localized?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
    return null;
  }

  static String? _codeFrom(dynamic data) {
    if (data is! Map) return null;
    final code = data['code']?.toString().trim();
    if (code == null || code.isEmpty) return null;
    return code.toUpperCase();
  }

  /// The app's own wording for the outcomes that matter, keyed by the stable
  /// code rather than by text. Returns null for codes the UI has nothing
  /// better to say about, so the caller falls back to its own message.
  static String? _messageForCode(String? code, String languageCode) {
    if (code == null) return null;
    final isArabic = languageCode == 'ar';
    return switch (code) {
      'SHIPMENT_ALREADY_ACCEPTED' =>
        isArabic
            ? 'هذه الشحنة لم تعد متاحة.'
            : 'This shipment is no longer available.',
      'SHIPMENT_NOT_AVAILABLE' =>
        isArabic
            ? 'هذه الشحنة غير متاحة للقبول.'
            : 'This shipment is not available to accept.',
      'DRIVER_INACTIVE' =>
        isArabic ? 'حساب السائق غير نشط.' : 'Your driver account is inactive.',
      'DRIVER_SUBSCRIPTION_INACTIVE' =>
        isArabic ? 'اشتراك السائق غير نشط.' : 'Your subscription is inactive.',
      'REQUEST_IN_PROGRESS' =>
        isArabic
            ? 'جاري تنفيذ طلب هذه الشحنة.'
            : 'This request is already being processed.',
      'REQUEST_ID_CONFLICT' =>
        isArabic
            ? 'تعذر تنفيذ الطلب. يرجى المحاولة مرة أخرى.'
            : 'Could not complete the request. Please try again.',
      'DB_ERROR' =>
        isArabic
            ? 'الخدمة غير متاحة حاليًا. يرجى المحاولة لاحقًا.'
            : 'Service is unavailable. Please try again later.',
      _ => null,
    };
  }

  /// One place that decides what the driver reads: the app's own wording for a
  /// known code first, then the server's own text in the driver's language,
  /// then the caller's localized fallback.
  String _outcomeMessage(
    dynamic data, {
    required String languageCode,
    required String fallback,
  }) {
    return _messageForCode(_codeFrom(data), languageCode) ??
        _messageFrom(data, languageCode: languageCode) ??
        fallback;
  }

  String? _distanceMessageFrom(dynamic data, String languageCode) {
    if (data is! Map) return null;

    final distance = _asDouble(data['distance_meters']);
    final radius = _asDouble(data['allowed_radius_meters']);
    if (distance == null || radius == null) return null;

    final distanceText = distance.round().toString();
    final radiusText = radius.round().toString();
    return _fallbackMessage(
      languageCode,
      en:
          'You are too far from the store. Current distance is about ${distanceText}m. You must be within ${radiusText}m.',
      ar:
          'أنت بعيد عن المتجر. المسافة الحالية تقريباً $distanceText متر، يجب أن تكون ضمن $radiusText متر.',
    );
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _fallbackMessage(
    String languageCode, {
    required String en,
    required String ar,
  }) {
    return languageCode == 'ar' ? ar : en;
  }

  /// Test seams. The wording rules and the busy set decide what the driver
  /// reads and whether a second tap is possible, so they are asserted directly
  /// rather than through a live request.
  @visibleForTesting
  static String? messageForCodeForTesting(String? code, String languageCode) =>
      _messageForCode(code, languageCode);

  @visibleForTesting
  String resolveOutcomeForTesting(
    dynamic data, {
    required String languageCode,
    required String fallback,
  }) => _outcomeMessage(data, languageCode: languageCode, fallback: fallback);

  @visibleForTesting
  void markBusyForTesting(int shipmentId) {
    _busyShipmentIds.add(shipmentId);
    notifyListeners();
  }

  void _showAlert(String title, String message, {bool showBtn = true}) {
    showAlertDialog(Nav.context, title, message, showBtn: showBtn);
  }

  void _showSuccess(String title, String message) {
    showAcceptanceDilaoge(Nav.context, title, message);
  }
}

class _ArrivalPositionResult {
  const _ArrivalPositionResult({this.position, this.errorMessage});

  final Position? position;
  final String? errorMessage;
}
