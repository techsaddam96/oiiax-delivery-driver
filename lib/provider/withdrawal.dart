import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/helper.dart';
import 'package:blockatie/models/withdrawal.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/request_id_service.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/withdrawal_rules.dart';
import 'package:blockatie/views/dialoges/alert_dialoge.dart';
import 'package:blockatie/views/dialoges/shipment_accept_dialog.dart';
import 'package:blockatie/views/widgets/bottom_nav.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What the withdrawal endpoint answered, as a stable code rather than prose.
///
/// The server's own `message` is documented as English kept for backward
/// compatibility, and its `DB_*` wording must never reach a driver, so nothing
/// from the wire is carried here. The Wallet writes the sentence.
enum WithdrawalSubmissionCode {
  requestSubmitted,
  pendingRequestExists,
  amountExceedsAvailable,
  invalidAmount,
  invalidWithdrawalMethod,
  invalidRequest,
  requestNotFound,
  invalidTransition,
  requestAlreadyProcessed,
  requestIdConflict,
  requestInProgress,
  driverInactive,
  apiKeyRequired,
  network,
  serverError,
}

/// The outcome of one submission attempt.
class WithdrawalSubmission {
  const WithdrawalSubmission({required this.success, required this.code});

  final bool success;
  final WithdrawalSubmissionCode code;
}

class WithdrawalProvider extends UserScopedNotifier with Helper {
  String selectedOption = 'cash'; // Default selected option
  final List<WithdrawalRequest> _requests = [];

  /// Balances and withdrawal history are financial data. Driver B must never see
  /// a value that belonged to Driver A, not even for one frame.
  @override
  void clearUserState() {
    selectedOption = 'cash';
    _requests.clear();
    _currentPage = 1;
    amount = '00.00 JOD';
    showAgreement = false;
    agreedToTerms = false;
    isBalanceHidden = false;
    withdrwalRes = null;
    isLoading = false;
    isSubmitting = false;
    lastError = null;
    lastMessage = null;
    lastCode = null;
    _inFlight = null;
    unreadCount = null;
  }

  // Pagination properties
  int _currentPage = 1;
  final int _itemsPerPage = 3; // 2 items per page as requested
  // Pagination getters
  int get currentPage => _currentPage;

  int get itemsPerPage => _itemsPerPage;

  void setPage(int page) {
    if (page >= 1 && page <= totalPages && totalPages > 0) {
      _currentPage = page;
      notifyListeners();
    }
  }

  List<WithdrawalRequest> get paginatedRequests {
    if (_requests.isEmpty) return [];

    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;

    if (startIndex >= _requests.length) return [];

    try {
      return _requests.sublist(
        startIndex,
        endIndex > _requests.length ? _requests.length : endIndex,
      );
    } catch (e) {
      return [];
    }
  }

  void selectOption(String option) {
    selectedOption = option;
    notifyListeners();
  }

  int get totalPages {
    if (_requests.isEmpty) return 0;
    return (_requests.length / _itemsPerPage).ceil();
  }

  // amount input
  String amount = '00.00 JOD';
  bool showAgreement = false;
  bool agreedToTerms = false;

  void updateAmount(String newAmount) {
    amount = newAmount;
    notifyListeners();
  }

  void addDigit(String digit) {
    String currentAmount = amount.replaceAll(' JOD', '');

    // Remove leading 00.00 or 0
    if (amount == '00.00 JOD' || amount == '0 JOD') {
      amount = '$digit JOD';
    } else if (currentAmount.length < 10) {
      amount = '$currentAmount$digit JOD';
    }

    notifyListeners();
  }

  // void addDigit(String digit) {
  //   if (amount == '00.00 JOD') {
  //     amount = '$digit JOD';
  //   } else {
  //     String currentAmount = amount.replaceAll(' JOD', '');
  //     if (currentAmount.length < 10) {
  //       amount = '$currentAmount$digit JOD';
  //     }
  //   }
  //   notifyListeners();
  // }

  void removeLastDigit() {
    String currentAmount = amount.replaceAll(' JOD', '');
    if (currentAmount.length > 1) {
      String newAmount = currentAmount.substring(0, currentAmount.length - 1);
      amount = '$newAmount JOD';
    } else {
      amount = '0 JOD';
    }
    notifyListeners();
  }

  void clear() {
    amount = '0 JOD'; // Simpler initial state
    showAgreement = false;
    agreedToTerms = false;
    notifyListeners();
  }

  // void clear() {
  //   amount = '00.00 JOD';
  //   showAgreement = false;
  //   agreedToTerms = false;
  //   notifyListeners();
  // }

  // Agreement functionality
  void showAgreementSection() {
    showAgreement = true;
    notifyListeners();
  }

  void hideAgreementSection() {
    showAgreement = false;
    notifyListeners();
  }

  void toggleAgreement() {
    agreedToTerms = !agreedToTerms;
    notifyListeners();
  }

  bool isBalanceHidden = false;

  void toggleBalanceVisibility() {
    isBalanceHidden = !isBalanceHidden;
    notifyListeners();
  }

  WithdrawalRequestsResponse? withdrwalRes;

  bool isLoading = false;
  bool isSubmitting = false;

  /// Kept only so the session reset keeps clearing them; nothing writes a
  /// message any more. Outcomes travel as [lastCode], which the Wallet turns
  /// into its own wording.
  String? lastError;
  String? lastMessage;

  /// The stable code of the last submission, for the page to turn into copy.
  WithdrawalSubmissionCode? lastCode;

  /// The submission currently in flight, if any. A second tap joins nothing
  /// and is told so, rather than being answered with a failure it did not
  /// cause.
  Future<WithdrawalSubmission>? _inFlight;

  /// Replaces the session client in tests, so a withdrawal can be exercised
  /// end to end — headers included — without reaching a real server.
  @visibleForTesting
  Dio? debugClient;

  Dio get _client => debugClient ?? sessionDio();

  int? unreadCount;

  Future<void> getWithrawals() async {
    isLoading = true;
    try {
      final dio = sessionDio();
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (driverId == null || apiKey == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      final response = await dio.post(
        AppUrls.getWithdrawal,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
          },
        ),
        data: {'driver_id': driverId},
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        withdrwalRes = WithdrawalRequestsResponse.fromJson(response.data);
      } else {
        _showInfoDialog(
          tr('error'),
          getLocalizedTypeName(
            response.data['message_en'] ?? 'Failed to fetch withdrawals',
            response.data['message_ar'],
          ),
        );
      }
    } catch (e) {
      debugPrint('Withdrawal fetch failed: ${e.runtimeType}');
      _showErrorDialog(tr('error'), tr('something_went_wrong'));
    }

    isLoading = false;
    notifyListeners();
  }

  String getWithdrawalStatus(int statusCode) {
    switch (statusCode) {
      case 0:
        return tr('pending'); //Pending
      case 1:
        return tr('approved');
      case 2:
        return tr('rejected');
      case 3:
        return tr('completed');
      default:
        return 'Unknown';
    }
  }

  /// Creates one withdrawal request.
  ///
  /// Returns null when a submission is already in flight: the caller has
  /// nothing to report, because the request it thinks it just made is the one
  /// already running. Answering a second tap with `false` is what used to show
  /// a failure snackbar over a request that went on to succeed.
  ///
  /// [canonicalAmount] must already be in the shape the backend accepts
  /// (`12`, `12.5`, `12.50`); the page validates before calling so the driver
  /// is told about a bad amount without a round trip.
  Future<WithdrawalSubmission?> submitWithdrawalRequest({
    required String canonicalAmount,
    required String withdrawalMethod,
  }) {
    if (_inFlight != null) return Future.value(null);

    final pending = _submit(
      canonicalAmount: canonicalAmount,
      withdrawalMethod: withdrawalMethod,
    );
    _inFlight = pending;

    return pending.whenComplete(() {
      if (identical(_inFlight, pending)) _inFlight = null;
    });
  }

  Future<WithdrawalSubmission> _submit({
    required String canonicalAmount,
    required String withdrawalMethod,
  }) async {
    if (normalizeWithdrawalAmount(canonicalAmount) == null) {
      return _finish(WithdrawalSubmissionCode.invalidAmount, success: false);
    }
    if (!isSupportedWithdrawalMethod(withdrawalMethod)) {
      return _finish(
        WithdrawalSubmissionCode.invalidWithdrawalMethod,
        success: false,
      );
    }

    final generation = stateGeneration;
    isSubmitting = true;
    lastError = null;
    lastMessage = null;
    lastCode = null;
    notifyListeners();

    // The idempotency key. Keyed on the payload, so an unchanged retry reuses
    // the same id and the backend answers with the original request instead of
    // creating a second one; changing the amount or the method produces a new
    // id. The session generation is part of that key, so Driver B can never
    // inherit Driver A's token.
    final lease = RequestIdService.acquire(
      operation: 'driver.createWithdrawal',
      payload: {
        'amount': canonicalAmount,
        'withdrawal_method': withdrawalMethod,
      },
    );
    var keepLeaseForRetry = false;

    try {
      final driverId = await AuthService.getuserId();
      final apiKey = await AuthService.getApiKey();

      if (driverId == null || apiKey == null || apiKey.trim().isEmpty) {
        return _finish(
          WithdrawalSubmissionCode.apiKeyRequired,
          success: false,
          generation: generation,
        );
      }

      final response = await _client.post(
        AppUrls.makeWithdrawalRequest,
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-API-KEY': apiKey,
            ...lease.headers(),
          },
        ),
        data: {
          'driver_id': driverId,
          'amount': canonicalAmount,
          'withdrawal_method': withdrawalMethod,
        },
      );

      final data = response.data;
      final code = codeFromResponse(data);
      final succeeded =
          response.statusCode == 200 &&
          data is Map &&
          (_isSuccess(data['success']) || _isSuccess(data['status']));

      if (succeeded) {
        clear();
        return _finish(
          WithdrawalSubmissionCode.requestSubmitted,
          success: true,
          generation: generation,
        );
      }

      return _finish(
        code ?? WithdrawalSubmissionCode.serverError,
        success: false,
        generation: generation,
      );
    } on DioException catch (e) {
      debugPrint(
        'Withdrawal submit Dio error: ${e.response?.statusCode ?? e.type}',
      );
      // The request may or may not have reached the server. Holding the id
      // means the retry is the same request rather than a second one.
      keepLeaseForRetry = true;
      return _finish(
        WithdrawalSubmissionCode.network,
        success: false,
        generation: generation,
      );
    } catch (e) {
      debugPrint('Withdrawal submit failed: ${e.runtimeType}');
      keepLeaseForRetry = true;
      return _finish(
        WithdrawalSubmissionCode.serverError,
        success: false,
        generation: generation,
      );
    } finally {
      lease.complete(keepForRetry: keepLeaseForRetry);
      if (acceptsState(generation)) {
        isSubmitting = false;
        notifyListeners();
      }
    }
  }

  WithdrawalSubmission _finish(
    WithdrawalSubmissionCode code, {
    required bool success,
    int? generation,
  }) {
    // A result belonging to a previous driver is reported to its own caller and
    // written nowhere: Driver B must not see Driver A's outcome.
    if (generation == null || acceptsState(generation)) {
      lastCode = code;
      notifyListeners();
    }

    return WithdrawalSubmission(success: success, code: code);
  }

  /// The server's stable code, mapped onto the app's own vocabulary.
  @visibleForTesting
  WithdrawalSubmissionCode? codeFromResponse(dynamic data) {
    if (data is! Map) return null;

    return switch (data['code']?.toString().toUpperCase()) {
      'REQUEST_SUBMITTED' => WithdrawalSubmissionCode.requestSubmitted,
      'PENDING_REQUEST_EXISTS' => WithdrawalSubmissionCode.pendingRequestExists,
      'AMOUNT_EXCEEDS_AVAILABLE' || 'AMOUNT_EXCEEDS_BALANCE' =>
        WithdrawalSubmissionCode.amountExceedsAvailable,
      'INVALID_AMOUNT' ||
      'REQUIRED_FIELDS' => WithdrawalSubmissionCode.invalidAmount,
      'INVALID_WITHDRAWAL_METHOD' =>
        WithdrawalSubmissionCode.invalidWithdrawalMethod,
      'INVALID_REQUEST' => WithdrawalSubmissionCode.invalidRequest,
      'REQUEST_NOT_FOUND' => WithdrawalSubmissionCode.requestNotFound,
      'INVALID_TRANSITION' => WithdrawalSubmissionCode.invalidTransition,
      'REQUEST_ALREADY_PROCESSED' =>
        WithdrawalSubmissionCode.requestAlreadyProcessed,
      'REQUEST_ID_CONFLICT' => WithdrawalSubmissionCode.requestIdConflict,
      'REQUEST_IN_PROGRESS' => WithdrawalSubmissionCode.requestInProgress,
      'DRIVER_INACTIVE' => WithdrawalSubmissionCode.driverInactive,
      'API_KEY_REQUIRED' ||
      'INVALID_API_KEY' => WithdrawalSubmissionCode.apiKeyRequired,
      _ => null,
    };
  }

  /// The keypad sheet's entry point.
  ///
  /// That sheet is not reachable from any live screen — the Wallet form is the
  /// only withdrawal UI — so this is kept compiling against the current
  /// contract rather than rebuilt. It shares the same validation and the same
  /// idempotency lease as the live path.
  Future<void> makeWithdrawal() async {
    final canonicalAmount = normalizeWithdrawalAmount(_amountText);
    if (canonicalAmount == null ||
        !isSupportedWithdrawalMethod(selectedOption)) {
      showAlertDialog(
        Nav.context,
        tr('error'),
        tr('enter_the_amount_to_withdraw'),
        showBtn: false,
      );
      return;
    }

    final result = await submitWithdrawalRequest(
      canonicalAmount: canonicalAmount,
      withdrawalMethod: selectedOption,
    );
    // Null means a submission was already running; the one on screen owns the
    // outcome.
    if (result == null) return;
    await getWithrawals();

    if (result.success) {
      _showInfoDialog(tr('success'), tr('success'));
      Nav.offAll(withNav: true, navIndex: 2, const CustomBottomNavBar());
    } else {
      _showErrorDialog(tr('error'), tr('something_went_wrong'));
    }
  }

  String get _amountText => amount.replaceAll('JOD', '').trim();

  bool _isSuccess(dynamic value) {
    if (value == true) return true;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'success';
  }

  void _showInfoDialog(String title, String message) {
    showAcceptanceDilaoge(Nav.context, title, message);
  }

  void _showErrorDialog(String title, String message) {
    showAlertDialog(Nav.context, title, message, showBtn: false);
  }
}
