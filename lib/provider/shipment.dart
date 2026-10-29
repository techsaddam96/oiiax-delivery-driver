import 'dart:async';
import 'dart:developer';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/driver_shipment_list_rules.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// class ShipmentProvider with ChangeNotifier {
//   int currentPage = 1;
//   final int itemsPerPage = 4;

//   final List<int> _allOrders = List.generate(40, (index) => index + 1); // dummy

//   // List<int> get paginatedOrders => _allOrders
//   //     .skip((currentPage - 1) * itemsPerPage)
//   //     .take(itemsPerPage)
//   //     .toList();
//   List<Shipment> get paginatedShipments {
//     if (shipmentsResponse == null) return [];

//     return shipmentsResponse!.shipments
//         .skip((currentPage - 1) * itemsPerPage)
//         .take(itemsPerPage)
//         .toList();
//   }

//   int get totalPages => (_allOrders.length / itemsPerPage).ceil();

//   void setPage(int page) {
//     currentPage = page;
//     notifyListeners();
//   }

//   void goToNextPage() {
//     if (currentPage < totalPages) {
//       currentPage++;
//       notifyListeners();
//     }
//   }

//   void goToPrevPage() {
//     if (currentPage > 1) {
//       currentPage--;
//       notifyListeners();
//     }
//   }

//   ShipmentsResponse? shipmentsResponse;

//   bool isLoading = false;
//   int? unreadCount;

//   Future<void> getAllShipments() async {
//     isLoading = true;
//     // notifyListeners();

//     try {
//       final dio = Dio();

//       final driverId = await AuthService.getuserId();
//       final apiKey = await AuthService.getApiKey();

//       if (driverId == null || apiKey == null) {
//         // AppUtils.errorToast('Missing user ID or API key');
//         isLoading = false;
//         notifyListeners();
//         return;
//       }

//       final response = await dio.post(
//         AppUrls.getAllShipments,
//         options: Options(
//           headers: {
//             'Content-Type': 'application/x-www-form-urlencoded',
//             'X-API-KEY': apiKey,
//           },
//         ),
//         data: {'driver_id': driverId},
//       );

//       if (response.statusCode == 200 && response.data['status'] == 'success') {
//         shipmentsResponse = ShipmentsResponse.fromJson(response.data);
//         print('shipment respode ${shipmentsResponse!.message}');
//       } else {
//         // AppUtils.errorToast(
//         //   response.data['message'] ?? 'Failed to fetch notifications',
//         // );
//       }
//     } catch (e) {
//       // AppUtils.errorToast("Something went wrong");
//     }

//     isLoading = false;
//     notifyListeners();
//   }

//   Future<void> acceptShipment(String? shipmentId) async {
//     isLoading = true;
//     //  notifyListeners();

//     try {
//       final dio = Dio();

//       final driverId = await AuthService.getuserId();
//       final apiKey = await AuthService.getApiKey();

//       if (driverId == null || apiKey == null) {
//         // AppUtils.errorToast('Missing user ID or API key');
//         isLoading = false;
//         notifyListeners();
//         return;
//       }

//       final response = await dio.post(
//         AppUrls.acceptShipment,
//         options: Options(
//           headers: {
//             'Accept': '*/*',
//             'Content-Type': 'application/x-www-form-urlencoded',
//             'X-API-KEY': apiKey,
//           },
//         ),
//         data: {'shipment_id': shipmentId, 'driver_id': driverId},
//       );

//       if (response.statusCode == 200 && response.data['status'] == 'success') {
//         log('response ${response.statusMessage}');
//       } else {
//         // AppUtils.errorToast(
//         //   response.data['message'] ?? 'Failed to fetch notifications',
//         // );
//       }
//     } catch (e) {
//       // AppUtils.errorToast("Something went wrong");
//     }

//     isLoading = false;
//     notifyListeners();
//   }
// }

/// Why a shipment page could not be loaded, in the only two categories the app
/// can tell apart reliably. Anything the backend says stays out of the UI.
enum ShipmentLoadFailure { network, generic }

class ShipmentProvider extends UserScopedNotifier {
  String _shipmentScope = 'all';
  String get shipmentScope => _shipmentScope;
  Future<void> selectShipmentScope(String scope) async {
    if (!const {'all', 'instant', 'scheduled', 'other'}.contains(scope)) return;
    if (_shipmentScope != scope) {
      resetUserState();
      _shipmentScope = scope;
    }
    await getAllShipments(force: true);
  }

  static const Duration _cacheDuration = Duration(seconds: 20);
  static const Duration _searchDebounce = Duration(milliseconds: 400);

  /// Rows for the page currently on screen. The backend decides what a page
  /// contains; nothing is sliced locally any more.
  List<Shipment> _pageShipments = [];
  int? _currentDriverId;

  String _searchQuery = '';
  Timer? _searchDebounceTimer;

  int currentPage = 1;
  final int itemsPerPage = 5;

  /// Populated from the server's pagination block.
  int _totalCount = 0;
  int _totalPages = 0;

  ShipmentsResponse? shipmentsResponse;
  bool isLoading = false;
  String? errorMessage;

  /// What went wrong, in terms the UI can word safely. The backend's own
  /// message is never shown, so this is how the page tells a connectivity
  /// problem from anything else.
  ShipmentLoadFailure? failure;

  /// True only while an already-loaded list is being replaced by another page.
  /// The page keeps the current rows on screen and disables the pager, rather
  /// than blanking a list the driver is reading.
  bool isPageChanging = false;

  bool _isFetchingShipments = false;
  DateTime? _lastFetchAt;
  // Cache is keyed by what was actually requested, so changing page or search
  // always refetches instead of re-showing the previous page.
  String? _lastFetchKey;

  /// Shipment lists carry recipient PII. Clearing `_lastFetchAt` also drops the
  /// cache window so the next driver cannot be served the previous one's data.
  @override
  void clearUserState() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    _pageShipments = [];
    _currentDriverId = null;
    _searchQuery = '';
    currentPage = 1;
    _totalCount = 0;
    _totalPages = 0;
    shipmentsResponse = null;
    isLoading = false;
    isPageChanging = false;
    errorMessage = null;
    failure = null;
    _isFetchingShipments = false;
    _lastFetchAt = null;
    _lastFetchKey = null;
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  /// === GETTERS ===

  List<Shipment> get paginatedShipments => _pageShipments;

  /// The current driver's live operational work from this server page. History
  /// remains available through [paginatedShipments], but Home must not call a
  /// delivered/cancelled row "active" merely because it was recently updated.
  List<Shipment> get activeOperationalShipments =>
      _pageShipments
          .where(
            (shipment) => DriverShipmentListRules.isActiveForCurrentDriver(
              shipment,
              _currentDriverId,
            ),
          )
          .toList();

  int get totalPages => _totalPages;
  int get totalCount => _totalCount;
  bool get hasLoaded => shipmentsResponse != null;
  bool get hasError => errorMessage != null && errorMessage!.trim().isNotEmpty;
  bool get _isCacheFresh {
    final lastFetchAt = _lastFetchAt;
    if (lastFetchAt == null) return false;
    return DateTime.now().difference(lastFetchAt) < _cacheDuration;
  }

  /// === SHIPMENT LOADING ===

  /// Pull-to-refresh: always returns the driver to page 1 of the current search.
  Future<void> onRefresh() async {
    currentPage = 1;
    await getAllShipments(force: true);
  }

  /// Loads one page from the backend.
  ///
  /// [page] defaults to [currentPage], so existing callers keep working and
  /// simply refresh whatever page is on screen.
  Future<void> getAllShipments({bool force = false, int? page}) async {
    if (_isFetchingShipments) return;

    final requestedPage = page ?? currentPage;
    final fetchKey = '$_shipmentScope|$requestedPage|$_searchQuery';
    if (!force && hasLoaded && _isCacheFresh && _lastFetchKey == fetchKey) {
      return;
    }

    // Guard the write-back: a response from the previous driver, or from a
    // page the user has already navigated away from, must not land.
    final generation = stateGeneration;

    // The page the driver is looking at right now. It stays authoritative
    // until the new one actually arrives, so a failed page change can never
    // leave the pager pointing at a page whose rows are not on screen.
    final previousPage = currentPage;

    _isFetchingShipments = true;
    isLoading = !hasLoaded || _lastFetchKey != fetchKey;
    isPageChanging = isLoading && hasLoaded;
    errorMessage = null;
    failure = null;
    if (isLoading) {
      notifyListeners();
    }
    try {
      final dio = sessionDio();
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();
      _currentDriverId = int.tryParse(driverId?.toString() ?? '');

      if (driverId == null || apiKey == null) {
        errorMessage = 'Missing user ID or API key';
        failure = ShipmentLoadFailure.generic;
        currentPage = previousPage;
        isLoading = false;
        isPageChanging = false;
        _isFetchingShipments = false;
        notifyListeners();
        return;
      }

      final response = await dio.post(
        // The endpoint localizes its own `message` from ?lang=; asking for the
        // driver's language keeps anything server-worded in step with the UI.
        // The bilingual status_name_en/ar columns stay authoritative locally.
        '${AppUrls.getAllShipments}?lang=$languageCode',
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
            'Accept-Language': languageCode,
          },
        ),
        data: {
          'driver_id': driverId,
          'shipment_scope': _shipmentScope,
          'page': requestedPage,
          'limit': itemsPerPage,
          if (_searchQuery.isNotEmpty) 'search': _searchQuery,
        },
      );

      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 && _isSuccess(data)) {
        final map = Map<String, dynamic>.from(data as Map);
        shipmentsResponse = ShipmentsResponse.fromJson(map);
        _pageShipments = shipmentsResponse!.shipments;
        _currentDriverId =
            shipmentsResponse!.driverId > 0
                ? shipmentsResponse!.driverId
                : _currentDriverId;
        _applyPagination(map['pagination'], requestedPage);
        _lastFetchAt = DateTime.now();
        _lastFetchKey = fetchKey;
      } else {
        // The backend's own wording is kept for logs only; the page words the
        // failure itself so nothing technical can reach the driver.
        errorMessage = _messageFrom(data) ?? 'Failed to fetch shipments';
        failure = ShipmentLoadFailure.generic;
        currentPage = previousPage;
      }
    } catch (e) {
      if (!acceptsState(generation)) return;
      errorMessage = 'Failed to fetch shipments';
      failure = _failureFor(e);
      currentPage = previousPage;
      log("getAllShipments Error : ${e.runtimeType}");
    }

    isLoading = false;
    isPageChanging = false;
    _isFetchingShipments = false;
    notifyListeners();
  }

  /// Applies an already-authoritative response in tests without opening a
  /// network connection. Mirrors the successful response path so ownership
  /// filtering is covered independently of UI rendering.
  @visibleForTesting
  void applyServerPageForTest(
    ShipmentsResponse response, {
    required int requestedPage,
    int? driverId,
    int? generation,
  }) {
    if (generation != null && !acceptsState(generation)) return;
    shipmentsResponse = response;
    _pageShipments = response.shipments;
    _currentDriverId = response.driverId > 0 ? response.driverId : driverId;
    _applyPagination(
      response.pagination == null
          ? null
          : <String, dynamic>{
            'page': response.pagination!.page,
            'total': response.pagination!.total,
            'total_pages': response.pagination!.totalPages,
          },
      requestedPage,
    );
    _lastFetchAt = DateTime.now();
    _lastFetchKey = '$_shipmentScope|$currentPage|$_searchQuery';
    notifyListeners();
  }

  /// The canonical code the backend expects. Read from the same place the rest
  /// of the app renders from, so a request cannot ask for a language the
  /// driver is not looking at.
  String get languageCode => AppLocalizations.isArabic ? 'ar' : 'en';

  /// Only failures the app can recognise with confidence are classified; any
  /// doubt falls back to the generic wording rather than guessing.
  ShipmentLoadFailure _failureFor(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return ShipmentLoadFailure.network;
        default:
          return ShipmentLoadFailure.generic;
      }
    }
    return ShipmentLoadFailure.generic;
  }

  /// Adopts the server's page/total figures. Falls back to the requested page
  /// and the row count if an older backend omits the block.
  void _applyPagination(dynamic pagination, int requestedPage) {
    if (pagination is Map) {
      final map = Map<String, dynamic>.from(pagination);
      currentPage = _asInt(map['page']) ?? requestedPage;
      _totalCount = _asInt(map['total']) ?? _pageShipments.length;
      _totalPages =
          _asInt(map['total_pages']) ?? (_totalCount / itemsPerPage).ceil();
      return;
    }

    currentPage = requestedPage;
    _totalCount = _pageShipments.length;
    _totalPages = _pageShipments.isEmpty ? 0 : 1;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  /// === SEARCH ===

  /// Search now runs on the backend so it still spans the driver's whole
  /// history rather than just the loaded page.
  ///
  /// Debounced because one caller fires this on every keystroke; without it
  /// each character would cost a request.
  void searchShipments(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized == _searchQuery) return;

    _searchQuery = normalized;
    currentPage = 1;
    notifyListeners();

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      unawaited(getAllShipments(force: true, page: 1));
    });
  }

  void clearSearch() {
    _searchDebounceTimer?.cancel();
    if (_searchQuery.isEmpty) return;

    _searchQuery = '';
    currentPage = 1;
    notifyListeners();
    unawaited(getAllShipments(force: true, page: 1));
  }

  /// === PAGINATION ===
  /// Each of these fetches the target page; pages are never sliced locally.

  void setPage(int page) {
    if (page < 1 || page == currentPage) return;
    if (_totalPages > 0 && page > _totalPages) return;
    // A second tap while a page is already in flight would be dropped by the
    // fetch guard anyway, but silently: refusing here keeps `currentPage` and
    // the rows on screen describing the same page throughout.
    if (_isFetchingShipments) return;

    // `currentPage` is advanced by the response, not by the tap. Until the new
    // page lands the pager keeps pointing at the rows that are actually shown.
    unawaited(getAllShipments(page: page, force: true));
  }

  void goToNextPage() {
    if (currentPage < totalPages) {
      setPage(currentPage + 1);
    }
  }

  void goToPrevPage() {
    if (currentPage > 1) {
      setPage(currentPage - 1);
    }
  }

  /// === ACTION ===

  Future<void> acceptShipment(String? shipmentId) async {
    if (shipmentId == null || shipmentId.isEmpty || _isFetchingShipments) {
      return;
    }
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final dio = sessionDio();
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (driverId == null || apiKey == null) {
        errorMessage = 'Missing user ID or API key';
        isLoading = false;
        notifyListeners();
        return;
      }

      final response = await dio.post(
        AppUrls.acceptShipment,
        options: Options(
          headers: {
            'Accept': '*/*',
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'shipment_id': shipmentId, 'driver_id': driverId},
      );

      if (response.statusCode == 200 && _isSuccess(response.data)) {
        log('Shipment accepted');
        await getAllShipments();
      } else {
        errorMessage =
            _messageFrom(response.data) ?? 'Failed to accept shipment';
      }
    } catch (e) {
      errorMessage = 'Failed to accept shipment';
    }

    isLoading = false;
    notifyListeners();
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

  String? _messageFrom(dynamic data) {
    if (data is! Map) return null;
    return (data['message'] ?? data['message_en'] ?? data['message_ar'])
        ?.toString();
  }
}
