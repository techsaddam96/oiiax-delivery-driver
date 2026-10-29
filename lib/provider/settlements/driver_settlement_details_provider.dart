import 'dart:collection';

import 'package:blockatie/models/settlements/driver_settlement.dart';
import 'package:blockatie/models/settlements/driver_settlement_line.dart';
import 'package:blockatie/services/driver_settlement_service.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:open_filex/open_filex.dart';

class DriverSettlementDetailsProvider extends UserScopedNotifier {
  DriverSettlementDetailsProvider({DriverSettlementService? service})
    : _service = service ?? DriverSettlementService();
  final DriverSettlementService _service;

  // A settlement belongs to one driver; clear the whole detail view.
  @override
  void clearUserState() {
    _lines.clear();
    settlement = null;
    isLoading = false;
    isLoadingMore = false;
    isDownloadingPdf = false;
    error = null;
    loadMoreError = null;
    pdfError = null;
    _settlementId = 0;
    _page = 1;
    _hasMore = false;
    _linesTotal = 0;
  }

  final List<DriverSettlementLine> _lines = [];
  DriverSettlement? settlement;
  bool isLoading = false;
  bool isLoadingMore = false;
  bool isDownloadingPdf = false;
  String? error;

  /// A later page of lines failing leaves the ones already loaded on screen.
  String? loadMoreError;
  String? pdfError;
  int _settlementId = 0;
  int _page = 1;
  bool _hasMore = false;
  int _linesTotal = 0;
  UnmodifiableListView<DriverSettlementLine> get lines =>
      UnmodifiableListView(_lines);
  bool get hasMore => _hasMore;
  int get currentPage => _page;

  /// How many shipments this settlement really has.
  ///
  /// `shipments_count` comes from the stored `total_shipments` column, which is
  /// `NOT NULL DEFAULT 0`: a settlement written with zero would claim no
  /// shipments while its lines render underneath. The pagination total is the
  /// counted truth, so it wins whenever the stored value is missing.
  int get shipmentsCount {
    final stored = settlement?.shipmentsCount ?? 0;
    if (stored > 0) return stored;
    if (_linesTotal > 0) return _linesTotal;
    return _lines.length;
  }

  Future<void> load(int settlementId) async {
    if (isLoading && _settlementId == settlementId) return;
    _settlementId = settlementId;
    isLoading = true;
    error = null;
    loadMoreError = null;
    _lines.clear();
    _linesTotal = 0;
    notifyListeners();
    await _fetch(page: 1, reset: true);
    isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() => load(_settlementId);

  Future<void> loadMore() async {
    if (isLoadingMore || !_hasMore || _settlementId <= 0) return;
    if (loadMoreError != null) return;
    isLoadingMore = true;
    notifyListeners();
    await _fetch(page: _page + 1, reset: false);
    isLoadingMore = false;
    notifyListeners();
  }

  Future<void> retryLoadMore() async {
    if (isLoadingMore) return;
    loadMoreError = null;
    notifyListeners();
    await loadMore();
  }

  Future<void> _fetch({required int page, required bool reset}) async {
    // A detail belonging to the previous driver must never land here.
    final generation = stateGeneration;
    try {
      final result = await _service.fetchSettlementDetails(
        _settlementId,
        page: page,
      );
      if (!acceptsState(generation)) return;

      settlement = result.settlement;
      if (reset) _lines.clear();
      _lines.addAll(result.lines);
      _page = result.pagination.page;
      _hasMore = result.pagination.hasMore;
      _linesTotal = result.pagination.total;
      error = null;
      loadMoreError = null;
    } on DriverSettlementException catch (e) {
      if (!acceptsState(generation)) return;
      if (reset) {
        error = e.code;
      } else {
        loadMoreError = e.code;
      }
    }
  }

  Future<bool> downloadPdf() async {
    final value = settlement;
    if (value == null || !value.hasPdf || isDownloadingPdf) return false;
    final generation = stateGeneration;
    isDownloadingPdf = true;
    pdfError = null;
    notifyListeners();
    try {
      final file = await _service.downloadSettlementPdf(
        value.settlementId,
        value.statementNumber,
      );
      // A document fetched for the previous driver is neither opened nor
      // reported once the session has moved on.
      if (!acceptsState(generation)) return false;
      final result = await OpenFilex.open(file.path);
      if (!acceptsState(generation)) return false;
      if (result.type != ResultType.done)
        throw const DriverSettlementException('PDF_FAILED');
      return true;
    } on DriverSettlementException catch (e) {
      if (!acceptsState(generation)) return false;
      pdfError = e.code;
      return false;
    } finally {
      if (acceptsState(generation)) {
        isDownloadingPdf = false;
        notifyListeners();
      }
    }
  }
}
