import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter/material.dart';

import '../services/requests_service.dart';

/// Why the withdrawal-request read failed, in terms the app owns.
///
/// Deliberately not a message: no backend prose, no Dio text and no database
/// wording ever leaves this layer. The Wallet turns one of these into a
/// sentence in the driver's own language.
enum WalletRequestsError { session, network, server, unknown }

class RequestsProvider extends UserScopedNotifier {
  List<WithdrawalRequest> _requests = [];
  bool _isLoading = false;
  bool _isPageChanging = false;
  WalletRequestsError? _error;
  bool _hasLoaded = false;

  // Withdrawal history is financial data and must not survive an account change.
  @override
  void clearUserState() {
    _requests = [];
    _isLoading = false;
    _isPageChanging = false;
    _error = null;
    _hasLoaded = false;
    _currentPage = 1;
    _totalPages = 0;
    _total = 0;
    _hasMore = false;
  }

  // Pagination state, owned by the server.
  int _currentPage = 1;
  int _totalPages = 0;
  int _total = 0;
  bool _hasMore = false;
  final int _itemsPerPage = 3;

  List<WithdrawalRequest> get requests => _requests;
  bool get isLoading => _isLoading;

  /// True only while moving between pages, so the rows already on screen can
  /// stay put under a loading hint instead of being replaced by a spinner.
  bool get isPageChanging => _isPageChanging;
  WalletRequestsError? get error => _error;
  bool get hasError => _error != null;

  /// True once a read has finished without failing. An empty list only means
  /// "no withdrawal requests" after this is true; before it, the list is empty
  /// because nothing has been read yet.
  bool get hasLoaded => _hasLoaded;

  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;
  int get totalPages => _totalPages;
  int get totalRequests => _total;
  bool get hasMore => _hasMore;

  /// The rows of the current page.
  ///
  /// The server decides which rows these are. This used to slice a local list
  /// that was itself capped at the endpoint's default of fifty, so older
  /// history could not be reached at all.
  List<WithdrawalRequest> get paginatedRequests => _requests;

  Future<void> fetchRequests({bool force = false, int? page}) async {
    // One read at a time: a second tap on Next while the first is in flight
    // would race, and the two could land out of order.
    if (_isLoading && (_isPageChanging || !force)) return;

    final requestedPage = page ?? _currentPage;
    final isPageChange = _hasLoaded && requestedPage != _currentPage;

    // The session this read belongs to. A reply that lands after a logout or an
    // account switch is financial data belonging to the previous driver and is
    // dropped rather than written into the next driver's wallet.
    final generation = stateGeneration;
    _isLoading = true;
    _isPageChanging = isPageChange;
    _error = null;
    notifyListeners();

    try {
      final result = await RequestsService.fetchWithdrawalRequests(
        page: requestedPage,
        limit: _itemsPerPage,
      );
      if (!acceptsState(generation)) return;

      final data = result['page'];
      if (result['success'] == true && data is WithdrawalRequestsPage) {
        // Rows and pager move together, and only on success, so the pager can
        // never end up describing a page the rows do not belong to.
        _requests = data.requests;
        _currentPage = data.page;
        _totalPages = data.pages;
        _total = data.total;
        _hasMore = data.hasMore;
        _error = null;
        _hasLoaded = true;
      } else {
        _error =
            result['success'] == true
                ? WalletRequestsError.unknown
                : errorForCode(result['code']?.toString());
        // A failed page change keeps the page it already had, rows included.
        if (!isPageChange) {
          _requests = [];
          _hasLoaded = false;
        }
      }
    } catch (e) {
      debugPrint('Withdrawal request fetch failed: ${e.runtimeType}');
      if (acceptsState(generation)) {
        _error = WalletRequestsError.unknown;
        if (!isPageChange) {
          _requests = [];
          _hasLoaded = false;
        }
      }
    } finally {
      // After a reset the cleared state is the current one; re-publishing this
      // read's bookkeeping would undo it.
      if (acceptsState(generation)) {
        _isLoading = false;
        _isPageChanging = false;
        notifyListeners();
      }
    }
  }

  /// Maps the service's stable code onto the app's own vocabulary. An
  /// unrecognised code falls through to [WalletRequestsError.unknown] rather
  /// than being shown to the driver.
  @visibleForTesting
  WalletRequestsError errorForCode(String? code) {
    return switch (code) {
      'SESSION_MISSING' ||
      'API_KEY_REQUIRED' ||
      'AUTH_FAILED' ||
      'DRIVER_ID_REQUIRED' => WalletRequestsError.session,
      'NETWORK_ERROR' => WalletRequestsError.network,
      'DB_ERROR' || 'SERVER_ERROR' => WalletRequestsError.server,
      _ => WalletRequestsError.unknown,
    };
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() {
    return fetchRequests(force: true);
  }

  // Each page change asks the server for that page; the state only moves when
  // the server answers.
  Future<void> setPage(int page) async {
    if (page < 1 || _totalPages <= 0 || page > _totalPages) return;
    if (page == _currentPage) return;
    await fetchRequests(page: page);
  }

  Future<void> goToNextPage() async {
    if (_currentPage >= _totalPages) return;
    await fetchRequests(page: _currentPage + 1);
  }

  Future<void> goToPrevPage() async {
    if (_currentPage <= 1) return;
    await fetchRequests(page: _currentPage - 1);
  }
}
