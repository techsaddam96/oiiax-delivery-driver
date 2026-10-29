import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/models/client.dart';
import 'package:blockatie/models/filter.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/status_shipment_model.dart';

/// How a set of filter options is doing.
///
/// Options used to be force-unwrapped by the page, so the very first build —
/// before the fetch returned — threw on a null. The state is explicit now, and
/// a failure is a failure rather than an empty list.
enum FilterOptionsState { idle, loading, ready, failed }

/// How the filtered query is doing.
///
/// [empty] and [failed] are deliberately separate: every failure path used to
/// set one `noShipmentFound` flag, so an offline device and a genuinely empty
/// result both read "No shipments found."
enum FilterQueryState { idle, loading, rows, empty, failed }

/// The filter actually being asked of the server.
///
/// Snapshotted when the driver presses Search, so editing a control afterwards
/// cannot change which query page two belongs to.
@immutable
class FilterCriteria {
  const FilterCriteria({this.date, this.statusId = 0, this.storeId});

  /// The single day being filtered, or null for "any date".
  final DateTime? date;

  /// A shipment status id, or 0 for "all".
  final int statusId;

  /// A store id, or null for "all stores".
  final String? storeId;

  bool get hasAny => date != null || statusId > 0 || storeId != null;

  /// `yyyy-MM-dd`, the only form the endpoint accepts. The display format is
  /// the page's business.
  String? get isoDate {
    final value = date;
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  /// The request body. A filter that is not set is omitted, never sent as a
  /// zero or an empty string.
  Map<String, dynamic> toRequest({required int page, required int limit}) => {
    'page': '$page',
    'limit': '$limit',
    if (isoDate != null) 'shipment_date': isoDate,
    if (statusId > 0) 'shipment_status': '$statusId',
    if (storeId != null) 'store_id': storeId,
  };

  FilterCriteria copyWith({
    Object? date = _unset,
    int? statusId,
    Object? storeId = _unset,
  }) {
    return FilterCriteria(
      date: identical(date, _unset) ? this.date : date as DateTime?,
      statusId: statusId ?? this.statusId,
      storeId: identical(storeId, _unset) ? this.storeId : storeId as String?,
    );
  }

  static const Object _unset = Object();
}

class FilterProvider extends UserScopedNotifier {
  FilterProvider({Dio? httpClient}) : _injectedDio = httpClient;

  /// Injectable so tests drive the real methods rather than replacing them.
  final Dio? _injectedDio;
  Dio get _dio => _injectedDio ?? sessionDio();

  /// Rows per page. The endpoint defaults to 50 and allows up to 100; 20
  /// matches what the other paged lists in this app request.
  static const int pageSize = 20;

  final TextEditingController dateController = TextEditingController();

  // ---------------------------------------------------------------- options
  StatusShipmentData? statusShipmentData;
  FilterOptionsState statusState = FilterOptionsState.idle;

  List<ClientModel> clientList = [];
  FilterOptionsState clientsState = FilterOptionsState.idle;

  // ------------------------------------------------------------------ draft
  /// What the controls currently show. Changing it does not touch the results
  /// on screen; only Search promotes it to [activeCriteria].
  FilterCriteria draft = const FilterCriteria();

  // ----------------------------------------------------------------- active
  FilterCriteria activeCriteria = const FilterCriteria();
  FilterQueryState queryState = FilterQueryState.idle;

  final List<Shipment> shipments = [];
  FilterPagination? pagination;

  bool isLoadingMore = false;
  bool loadMoreFailed = false;

  /// Bumped on every new query. A reply stamped with an older revision belongs
  /// to a filter the driver has already replaced and is discarded.
  int _queryRevision = 0;
  bool _isQuerying = false;

  int get totalResults => pagination?.total ?? shipments.length;
  bool get hasMore => pagination?.hasMore ?? false;
  bool get isQuerying => queryState == FilterQueryState.loading;

  /// Kept for the calendar sheet and for callers that only need a selected day.
  DateTime? get selectedDate => draft.date;

  /// The month the calendar is showing. It has to exist even when no day is
  /// chosen, so it falls back to today rather than to a hardcoded past date.
  DateTime _visibleMonth = DateTime.now();

  /// Everything on this screen belongs to one driver.
  @override
  void clearUserState() {
    dateController.clear();
    statusShipmentData = null;
    statusState = FilterOptionsState.idle;
    clientList = [];
    clientsState = FilterOptionsState.idle;
    selectedClient = null;
    draft = const FilterCriteria();
    activeCriteria = const FilterCriteria();
    queryState = FilterQueryState.idle;
    shipments.clear();
    pagination = null;
    isLoadingMore = false;
    loadMoreFailed = false;
    _isQuerying = false;
    _queryRevision++;
    _visibleMonth = DateTime.now();
  }

  // ------------------------------------------------------------ draft edits

  void selectStatusId(int id) {
    draft = draft.copyWith(statusId: id);
    notifyListeners();
  }

  /// The explicit "All" choice. 0 is what the request omits.
  void clearStatusFilter() => selectStatusId(0);

  ClientModel? selectedClient;

  /// Null selects "all stores"; the request omits `store_id` entirely.
  void setSelectedClient(ClientModel? client) {
    selectedClient = client;
    draft = draft.copyWith(storeId: client?.id.toString());
    notifyListeners();
  }

  /// Restores the neutral state: no filters, no results, no page cursor.
  ///
  /// It no longer reaches into TimeProvider, and no longer parks the date on
  /// 2021-11-23.
  void resetFilters() {
    dateController.clear();
    selectedClient = null;
    draft = const FilterCriteria();
    activeCriteria = const FilterCriteria();
    queryState = FilterQueryState.idle;
    shipments.clear();
    pagination = null;
    isLoadingMore = false;
    loadMoreFailed = false;
    _visibleMonth = DateTime.now();
    // Any reply still in flight belongs to the query being discarded. Bumping
    // the revision disowns it, which is also what releases the re-entry lock:
    // without this, Search after Reset was refused until the abandoned request
    // happened to finish.
    _queryRevision++;
    _isQuerying = false;
    notifyListeners();
  }

  // -------------------------------------------------------------- calendar

  DateTime get visibleMonth => _visibleMonth;

  String get formattedDate {
    final value = draft.date;
    if (value == null) return '';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  void selectDate(int day) {
    final picked = DateTime(_visibleMonth.year, _visibleMonth.month, day);
    draft = draft.copyWith(date: picked);
    dateController.text = formattedDate;
    notifyListeners();
  }

  void clearDate() {
    draft = draft.copyWith(date: null);
    dateController.clear();
    notifyListeners();
  }

  void previousMonth() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    notifyListeners();
  }

  void nextMonth() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    notifyListeners();
  }

  String getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  List<List<int?>> getCalendarDays() {
    final firstDayOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    );

    final startWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth = lastDayOfMonth.day;

    final days = <int?>[];
    for (var i = 0; i < startWeekday; i++) {
      days.add(null);
    }
    for (var day = 1; day <= daysInMonth; day++) {
      days.add(day);
    }
    while (days.length % 7 != 0) {
      days.add(null);
    }

    final weeks = <List<int?>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7));
    }
    return weeks;
  }

  // --------------------------------------------------------------- options

  Future<void> getStatusShipment() async {
    if (statusState == FilterOptionsState.loading) return;
    final generation = stateGeneration;
    statusState = FilterOptionsState.loading;
    notifyListeners();

    try {
      final apiKey = await AuthService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        if (!acceptsState(generation)) return;
        statusState = FilterOptionsState.failed;
        notifyListeners();
        return;
      }

      final response = await _dio.get(
        AppUrls.getStatusShipment,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
          validateStatus: (_) => true,
        ),
      );

      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 && data is Map && data['success'] == true) {
        statusShipmentData = StatusShipmentData.fromJson(
          Map<String, dynamic>.from(data),
        );
        statusState = FilterOptionsState.ready;
      } else {
        statusState = FilterOptionsState.failed;
      }
    } catch (e) {
      debugPrint('Filter status options failed: ${e.runtimeType}');
      if (!acceptsState(generation)) return;
      statusState = FilterOptionsState.failed;
    }
    notifyListeners();
  }

  /// The store list is optional: if it fails the rest of the page still works,
  /// and only the store dropdown reports the problem.
  Future<void> getClients() async {
    if (clientsState == FilterOptionsState.loading) return;
    final generation = stateGeneration;
    clientsState = FilterOptionsState.loading;
    notifyListeners();

    try {
      final apiKey = await AuthService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        if (!acceptsState(generation)) return;
        clientsState = FilterOptionsState.failed;
        notifyListeners();
        return;
      }

      final response = await _dio.get(
        AppUrls.driverStores,
        options: Options(
          headers: {'Accept': 'application/json', 'X-API-KEY': apiKey},
          validateStatus: (_) => true,
        ),
      );

      if (!acceptsState(generation)) return;

      final data = response.data;
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true &&
          data['clients'] != null) {
        final model = ClientListResponse.fromJson(
          Map<String, dynamic>.from(data),
        );
        final unique = <String, ClientModel>{};
        for (final client in model.clients) {
          unique[client.id.toString()] = client;
        }
        clientList = unique.values.toList();

        if (selectedClient != null &&
            !clientList.any((c) => c.id == selectedClient!.id)) {
          selectedClient = null;
          draft = draft.copyWith(storeId: null);
        }
        clientsState = FilterOptionsState.ready;
      } else {
        clientsState = FilterOptionsState.failed;
      }
    } catch (e) {
      debugPrint('Filter store options failed: ${e.runtimeType}');
      if (!acceptsState(generation)) return;
      clientsState = FilterOptionsState.failed;
    }
    notifyListeners();
  }

  // ----------------------------------------------------------------- query

  /// Runs the current draft as a new query, from page one.
  Future<void> filterShipment() async {
    // Re-entry guard in the provider, not only on the button: a second tap that
    // lands before the first rebuild must still be refused.
    if (_isQuerying) return;
    _isQuerying = true;

    final generation = stateGeneration;
    final revision = ++_queryRevision;
    final criteria = draft;

    activeCriteria = criteria;
    queryState = FilterQueryState.loading;
    loadMoreFailed = false;
    notifyListeners();

    try {
      final page = await _fetchPage(criteria, 1, generation);
      if (!acceptsState(generation) || revision != _queryRevision) return;

      if (page == null) {
        queryState = FilterQueryState.failed;
        shipments.clear();
        pagination = null;
      } else {
        shipments
          ..clear()
          ..addAll(page.shipments);
        pagination = page.pagination;
        queryState =
            shipments.isEmpty ? FilterQueryState.empty : FilterQueryState.rows;
      }
    } finally {
      // Only the query that still owns the lock may release it. A reply that
      // lands after a reset belongs to nobody and must not unlock a search
      // started in the meantime.
      if (revision == _queryRevision) {
        _isQuerying = false;
        if (acceptsState(generation)) notifyListeners();
      }
    }
  }

  /// Appends the next page of the query already on screen.
  Future<void> loadMore() async {
    if (isLoadingMore || loadMoreFailed || !hasMore) return;
    if (queryState != FilterQueryState.rows) return;

    final generation = stateGeneration;
    final revision = _queryRevision;
    final nextPage = (pagination?.page ?? 1) + 1;

    isLoadingMore = true;
    notifyListeners();

    try {
      // The snapshot, not the controls: the driver may have edited them since.
      final page = await _fetchPage(activeCriteria, nextPage, generation);
      if (!acceptsState(generation) || revision != _queryRevision) return;

      if (page == null) {
        // The rows already on screen stay; only the next page failed.
        loadMoreFailed = true;
      } else {
        final seen = shipments.map((s) => s.id).toSet();
        shipments.addAll(page.shipments.where((s) => !seen.contains(s.id)));
        pagination = page.pagination;
        loadMoreFailed = false;
      }
    } finally {
      // Same ownership rule as the first page: a stale next page must not clear
      // the spinner belonging to the query that replaced it.
      if (revision == _queryRevision) {
        isLoadingMore = false;
        if (acceptsState(generation)) notifyListeners();
      }
    }
  }

  Future<void> retryLoadMore() async {
    loadMoreFailed = false;
    notifyListeners();
    await loadMore();
  }

  /// One page, or null when the request could not be trusted.
  Future<FilterResponse?> _fetchPage(
    FilterCriteria criteria,
    int page,
    int generation,
  ) async {
    try {
      final apiKey = await AuthService.getApiKey();
      // No session means the session layer will deal with it; this screen says
      // nothing technical about API keys.
      if (apiKey == null || apiKey.isEmpty) return null;
      if (!acceptsState(generation)) return null;

      final response = await _dio.post(
        AppUrls.filterShipments,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
          validateStatus: (_) => true,
        ),
        // Driver identity is derived server-side from the API key. driver_id
        // and client_id are never sent; the endpoint rejects them outright.
        data: criteria.toRequest(page: page, limit: pageSize),
      );

      if (response.statusCode != 200) return null;

      final parsed = FilterResponse.fromJson(response.data);
      if (parsed == null || !parsed.success) return null;
      return parsed;
    } catch (e) {
      debugPrint('Filter query failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  void dispose() {
    dateController.dispose();
    super.dispose();
  }
}
