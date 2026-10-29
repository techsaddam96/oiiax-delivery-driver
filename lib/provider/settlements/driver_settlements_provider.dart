import 'dart:collection';

import 'package:blockatie/models/settlements/driver_financial_summary.dart';
import 'package:blockatie/models/settlements/driver_performance_summary.dart';
import 'package:blockatie/models/settlements/driver_settlement.dart';
import 'package:blockatie/services/driver_settlement_service.dart';
import 'package:blockatie/services/user_session_state.dart';

/// Where a section of the settlements screen is in its own lifecycle.
///
/// Loading and failure used to be the same thing here: a summary that had not
/// arrived yet rendered the "unable to connect" card, so every visit reported a
/// failure for a read that was still in flight.
enum SettlementSectionState { idle, loading, ready, failed }

class DriverSettlementsProvider extends UserScopedNotifier {
  DriverSettlementsProvider({DriverSettlementService? service})
    : _service = service ?? DriverSettlementService();
  final DriverSettlementService _service;

  // Settlement totals are financial data; never reuse them across drivers.
  @override
  void clearUserState() {
    _items.clear();
    financialSummary = null;
    performanceSummary = null;
    isInitialLoading = false;
    isLoadingMore = false;
    isRefreshing = false;
    listError = null;
    loadMoreError = null;
    financialError = null;
    performanceError = null;
    financialState = SettlementSectionState.idle;
    performanceState = SettlementSectionState.idle;
    _page = 1;
    _hasMore = true;
    _status = null;
  }

  final List<DriverSettlement> _items = [];
  DriverFinancialSummary? financialSummary;
  DriverPerformanceSummary? performanceSummary;
  bool isInitialLoading = false;
  bool isLoadingMore = false;
  bool isRefreshing = false;
  bool isFiltering = false;
  String? listError;

  /// A later page failing is not the same as the list failing: the rows already
  /// on screen are still good, so this is reported beside them instead of
  /// replacing them.
  String? loadMoreError;
  String? financialError;
  String? performanceError;
  SettlementSectionState financialState = SettlementSectionState.idle;
  SettlementSectionState performanceState = SettlementSectionState.idle;
  int _page = 1;
  bool _hasMore = true;
  String? _status;
  UnmodifiableListView<DriverSettlement> get items =>
      UnmodifiableListView(_items);
  bool get hasMore => _hasMore;
  String? get statusFilter => _status;
  int get currentPage => _page;

  Future<void> loadInitial() async {
    if (isInitialLoading || (_items.isNotEmpty && listError == null)) return;
    final generation = stateGeneration;
    isInitialLoading = true;
    listError = null;
    loadMoreError = null;
    financialState = SettlementSectionState.loading;
    performanceState = SettlementSectionState.loading;
    notifyListeners();
    await _loadPage(reset: true);
    if (!acceptsState(generation)) return;
    isInitialLoading = false;
    notifyListeners();
    await Future.wait([_loadFinancial(), _loadPerformance()]);
  }

  Future<void> refresh() async {
    if (isRefreshing) return;
    final generation = stateGeneration;
    isRefreshing = true;
    financialState = SettlementSectionState.loading;
    performanceState = SettlementSectionState.loading;
    notifyListeners();
    await Future.wait([
      _loadPage(reset: true),
      _loadFinancial(),
      _loadPerformance(),
    ]);
    if (!acceptsState(generation)) return;
    isRefreshing = false;
    notifyListeners();
  }

  Future<void> setStatusFilter(String? status) async {
    if (_status == status || isFiltering) return;
    _status = status;
    isFiltering = true;
    loadMoreError = null;
    notifyListeners();
    await _loadPage(reset: true);
    isFiltering = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (isLoadingMore || !_hasMore || isInitialLoading || isRefreshing) return;
    // A page that just failed must not be retried by the scroll listener on
    // every frame; the driver asks for it again.
    if (loadMoreError != null) return;
    isLoadingMore = true;
    notifyListeners();
    await _loadPage(reset: false);
    isLoadingMore = false;
    notifyListeners();
  }

  /// Retries the page that failed, from the driver's own tap.
  Future<void> retryLoadMore() async {
    if (isLoadingMore) return;
    loadMoreError = null;
    notifyListeners();
    await loadMore();
  }

  Future<void> _loadPage({required bool reset}) async {
    // The session this read belongs to. A reply that lands after a logout is
    // the previous driver's financial data and is dropped rather than written
    // into the next driver's list.
    final generation = stateGeneration;
    try {
      final page = reset ? 1 : _page + 1;
      final result = await _service.fetchSettlements(
        page: page,
        status: _status,
      );
      if (!acceptsState(generation)) return;

      // Rows and pager move together, and only on success.
      if (reset) _items.clear();
      _items.addAll(result.items);
      _page = result.pagination.page;
      _hasMore = result.pagination.hasMore;
      listError = null;
      loadMoreError = null;
    } on DriverSettlementException catch (error) {
      if (!acceptsState(generation)) return;
      if (reset) {
        listError = error.code;
        _items.clear();
        _hasMore = false;
      } else {
        // Keep the rows and the page exactly as they were.
        loadMoreError = error.code;
      }
    }
  }

  Future<void> _loadFinancial() async {
    final generation = stateGeneration;
    try {
      final summary = await _service.fetchFinancialSummary();
      if (!acceptsState(generation)) return;
      financialSummary = summary;
      financialError = null;
      financialState = SettlementSectionState.ready;
    } on DriverSettlementException catch (error) {
      if (!acceptsState(generation)) return;
      financialError = error.code;
      financialState = SettlementSectionState.failed;
    }
    notifyListeners();
  }

  Future<void> _loadPerformance() async {
    final generation = stateGeneration;
    try {
      final summary = await _service.fetchPerformanceSummary();
      if (!acceptsState(generation)) return;
      performanceSummary = summary;
      performanceError = null;
      performanceState = SettlementSectionState.ready;
    } on DriverSettlementException catch (error) {
      if (!acceptsState(generation)) return;
      performanceError = error.code;
      performanceState = SettlementSectionState.failed;
    }
    notifyListeners();
  }
}
