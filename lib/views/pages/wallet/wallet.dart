import 'dart:async';

import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/models/statistics.dart';
import 'package:blockatie/provider/home.dart';
import 'package:blockatie/provider/requests_provider.dart';
import 'package:blockatie/provider/withdrawal.dart';
import 'package:blockatie/services/requests_service.dart';
import 'package:blockatie/models/shipment.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/money.dart';
import 'package:blockatie/utils/text_direction.dart';
import 'package:blockatie/utils/withdrawal_rules.dart';
import 'package:blockatie/views/pages/home/components/header.dart';
import 'package:blockatie/views/widgets/driver_chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  String _selectedMethod = 'cash';
  bool _isRefreshing = false;

  /// The session this page's local state belongs to. The bottom navigation
  /// keeps this page alive, so nothing here is disposed on a logout.
  late int _generation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _generation = UserSessionState.generation;
    UserSessionState.changes.addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadWalletData();
    });
  }

  @override
  void dispose() {
    UserSessionState.changes.removeListener(_onSessionChanged);
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  /// A typed withdrawal amount belongs to the driver who typed it. The
  /// providers clear themselves on a session change, but this controller lives
  /// in page State behind a keep-alive: without this it would carry Driver A's
  /// amount straight into Driver B's form.
  void _onSessionChanged() {
    if (!mounted || UserSessionState.isCurrent(_generation)) return;
    setState(() {
      _generation = UserSessionState.generation;
      _amountController.clear();
      _selectedMethod = 'cash';
      _isRefreshing = false;
    });
    _amountFocusNode.unfocus();
  }

  Future<void> _loadWalletData({bool force = false}) async {
    final requestsProvider = context.read<RequestsProvider>();
    final homeProvider = context.read<HomeProvider>();

    unawaited(requestsProvider.fetchRequests(force: force));
    if (force || homeProvider.driverStats == null) {
      unawaited(homeProvider.getDriverStatistics(context, force: force));
    }
  }

  /// Refreshes both visible sources at once.
  ///
  /// Two things matter here. A second pull while one is already running would
  /// double every request and let the two runs finish out of order, so the
  /// page refuses to start one. And each source keeps its own error state, so
  /// one of them failing must neither abort the other nor discard the data the
  /// other just loaded — hence the per-future catch instead of letting
  /// `Future.wait` short-circuit.
  ///
  /// Nothing is written back into page State once the awaits return: both
  /// providers stamp their own reads with the session generation and drop a
  /// reply that belongs to a previous driver, so the page has no stale
  /// completion of its own to guard against.
  Future<void> _refreshWallet() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    final requestsProvider = context.read<RequestsProvider>();
    final homeProvider = context.read<HomeProvider>();

    try {
      await Future.wait([
        requestsProvider.fetchRequests(force: true).catchError((Object _) {}),
        homeProvider
            .getDriverStatistics(context, force: true)
            .catchError((Object _) {}),
      ]);
    } finally {
      // Released even when the session moved on, so a later sign-in does not
      // inherit a stuck refresh.
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: const Color(0xffF6F8FC),
      body: SafeArea(
        child: Column(
          children: [
            HomeHeader(
              title: _copy('Wallet', 'المحفظة'),
              subtitle: _copy(
                'Earnings and withdrawal requests',
                'الأرباح وطلبات السحب',
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshWallet,
                color: AppColors.primary,
                child: Consumer3<
                  HomeProvider,
                  RequestsProvider,
                  WithdrawalProvider
                >(
                  builder: (
                    context,
                    homeProvider,
                    requestsProvider,
                    withdrawalProvider,
                    _,
                  ) {
                    final stats = homeProvider.driverStats;
                    final requests = requestsProvider.requests;

                    return ListView(
                      // Clears the floating chat launcher, so the last request
                      // card and the pagination bar stay reachable.
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        DriverChatBubble.reservedBottomSpace + 16,
                      ),
                      children: [
                        _BalanceSummaryCard(
                          stats: stats,
                          requests: requests,
                          isLoading: homeProvider.isLoading && stats == null,
                          hasError: homeProvider.hasStatisticsError,
                          pendingLoading:
                              requestsProvider.isLoading &&
                              !requestsProvider.hasLoaded,
                          pendingFailed: requestsProvider.hasError,
                          copy: _copy,
                        ),
                        const SizedBox(height: 14),
                        _WithdrawalFormCard(
                          amountController: _amountController,
                          amountFocusNode: _amountFocusNode,
                          selectedMethod: _selectedMethod,
                          isSubmitting: withdrawalProvider.isSubmitting,
                          // The server's own number. Null when it has not
                          // said, which disables the form rather than letting
                          // the app invent a ceiling.
                          available:
                              homeProvider.hasStatisticsError
                                  ? null
                                  : stats?.availableToWithdraw,
                          reserved: stats?.earningsReserved,
                          paid: stats?.earningsPaid,
                          isBalanceLoading:
                              homeProvider.isLoading && stats == null,
                          onMethodChanged: (method) {
                            setState(() => _selectedMethod = method);
                          },
                          onSubmit:
                              () => _submitWithdrawal(
                                available:
                                    homeProvider.hasStatisticsError
                                        ? null
                                        : stats?.availableToWithdraw,
                                withdrawalProvider: withdrawalProvider,
                              ),
                          copy: _copy,
                        ),
                        const SizedBox(height: 18),
                        _SectionTitle(
                          title: _copy('Withdrawal Requests', 'طلبات السحب'),
                          subtitle: _copy(
                            'Track every request and its status',
                            'تابع كل طلب وحالته',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildRequestsSection(requestsProvider),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsSection(RequestsProvider provider) {
    if (provider.isLoading && provider.requests.isEmpty) {
      return _StateCard(
        icon: Icons.account_balance_wallet_outlined,
        title: _copy('Loading wallet data...', 'جارٍ تحميل بيانات المحفظة...'),
        message: _copy('Please wait a moment.', 'يرجى الانتظار لحظات.'),
        isLoading: true,
      );
    }

    if (provider.error != null && provider.requests.isEmpty) {
      return _StateCard(
        icon: Icons.error_outline_rounded,
        title: _copy('Unable to load wallet data', 'تعذر تحميل بيانات المحفظة'),
        message: _errorMessage(provider.error!),
        actionLabel: _copy('Try again', 'حاول مرة أخرى'),
        onAction: () => provider.fetchRequests(force: true),
      );
    }

    if (provider.requests.isEmpty) {
      return _StateCard(
        icon: Icons.receipt_long_outlined,
        title: _copy('No withdrawal requests yet', 'لا توجد طلبات سحب حالياً'),
        message: _copy(
          'Your withdrawal history will appear here.',
          'سيظهر سجل طلبات السحب هنا.',
        ),
      );
    }

    return Column(
      children: [
        // The rows stay on screen while the next page loads, dimmed, so the
        // list does not flash empty between pages.
        Opacity(
          opacity: provider.isPageChanging ? 0.45 : 1,
          child: Column(
            children: [
              for (final request in provider.paginatedRequests) ...[
                _RequestCard(request: request, copy: _copy),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        if (provider.totalPages > 1)
          _PaginationBar(
            currentPage: provider.currentPage,
            totalPages: provider.totalPages,
            isChanging: provider.isPageChanging,
            onPrevious:
                (provider.currentPage > 1 && !provider.isPageChanging)
                    ? provider.goToPrevPage
                    : null,
            onNext:
                (provider.currentPage < provider.totalPages &&
                        !provider.isPageChanging)
                    ? provider.goToNextPage
                    : null,
            copy: _copy,
          ),
      ],
    );
  }

  Future<void> _submitWithdrawal({
    required double? available,
    required WithdrawalProvider withdrawalProvider,
  }) async {
    // Nothing is submitted against a ceiling nobody confirmed.
    if (available == null) return;

    final canonicalAmount = normalizeWithdrawalAmount(_amountController.text);
    if (canonicalAmount == null) {
      _showSnack(_submissionCopy(WithdrawalSubmissionCode.invalidAmount),
          isError: true);
      return;
    }

    if (!isWithinAvailable(canonicalAmount, available)) {
      _showSnack(
        _submissionCopy(WithdrawalSubmissionCode.amountExceedsAvailable),
        isError: true,
      );
      return;
    }

    _amountFocusNode.unfocus();
    final generation = UserSessionState.generation;

    final result = await withdrawalProvider.submitWithdrawalRequest(
      canonicalAmount: canonicalAmount,
      withdrawalMethod: _selectedMethod,
    );

    // A submission was already running: it owns the outcome, and a second tap
    // must not report a failure it did not cause.
    if (result == null) return;
    // A reply belonging to the previous driver never reaches this driver's
    // screen.
    if (!mounted || !UserSessionState.isCurrent(generation)) return;

    if (result.success) {
      _amountController.clear();
      _showSnack(_submissionCopy(result.code));
      // Both the authoritative balance and the history are re-read, so the
      // new reservation is visible immediately.
      await _refreshWallet();
    } else {
      // The typed amount is left alone: the driver may only need to change it.
      _showSnack(_submissionCopy(result.code), isError: true);
    }
  }

  /// App-owned wording for every outcome the endpoint can report.
  ///
  /// Resolved from the stable code, never from the server's prose: its
  /// `message` is documented as English, and its database wording must never
  /// reach a driver at all.
  String _submissionCopy(WithdrawalSubmissionCode code) {
    return switch (code) {
      WithdrawalSubmissionCode.requestSubmitted => _copy(
        'Withdrawal request submitted successfully.',
        'تم إرسال طلب السحب بنجاح.',
      ),
      WithdrawalSubmissionCode.pendingRequestExists => _copy(
        'You already have a pending withdrawal request.',
        'لديك طلب سحب قيد الانتظار بالفعل.',
      ),
      WithdrawalSubmissionCode.amountExceedsAvailable => _copy(
        'The requested amount exceeds your available withdrawal balance.',
        'المبلغ المطلوب يتجاوز الرصيد المتاح للسحب.',
      ),
      WithdrawalSubmissionCode.invalidAmount => _copy(
        'Enter a valid withdrawal amount.',
        'أدخل مبلغ سحب صحيح.',
      ),
      WithdrawalSubmissionCode.invalidWithdrawalMethod => _copy(
        'Select a valid withdrawal method.',
        'اختر طريقة سحب صحيحة.',
      ),
      WithdrawalSubmissionCode.requestInProgress => _copy(
        'This request is already being processed.',
        'يتم تنفيذ هذا الطلب حالياً.',
      ),
      WithdrawalSubmissionCode.requestIdConflict => _copy(
        'Please try again with a new request.',
        'يرجى المحاولة مرة أخرى بطلب جديد.',
      ),
      WithdrawalSubmissionCode.requestAlreadyProcessed => _copy(
        'This request has already been processed.',
        'تمت معالجة هذا الطلب بالفعل.',
      ),
      WithdrawalSubmissionCode.requestNotFound => _copy(
        'This withdrawal request was not found.',
        'لم يتم العثور على طلب السحب.',
      ),
      WithdrawalSubmissionCode.invalidTransition => _copy(
        'This request can no longer be changed.',
        'لا يمكن تغيير هذا الطلب بعد الآن.',
      ),
      WithdrawalSubmissionCode.driverInactive ||
      WithdrawalSubmissionCode.apiKeyRequired => _copy(
        'Session expired. Please login again.',
        'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      ),
      WithdrawalSubmissionCode.network => _copy(
        'Unable to connect. Please check your connection and try again.',
        'تعذر الاتصال. يرجى التحقق من الشبكة والمحاولة مرة أخرى.',
      ),
      WithdrawalSubmissionCode.invalidRequest ||
      WithdrawalSubmissionCode.serverError => _copy(
        'Unable to submit the withdrawal request. Please try again later.',
        'تعذر إرسال طلب السحب. يرجى المحاولة لاحقًا.',
      ),
    };
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? const Color(0xffDC2626) : const Color(0xff16A06D),
      ),
    );
  }

  /// The app's own wording for every way the read can fail.
  ///
  /// Nothing from the wire reaches this string: no backend `message`, no Dio
  /// text, no endpoint, no exception and no database wording. The service
  /// hands over a stable kind and the sentence is written here, in the
  /// driver's language.
  String _errorMessage(WalletRequestsError error) {
    return switch (error) {
      WalletRequestsError.session => _copy(
        'Session expired. Please login again.',
        'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
      ),
      WalletRequestsError.network => _copy(
        'Unable to connect. Please check your connection and try again.',
        'تعذر الاتصال. يرجى التحقق من الشبكة والمحاولة مرة أخرى.',
      ),
      WalletRequestsError.server => _copy(
        'Service is unavailable. Please try again later.',
        'الخدمة غير متاحة حاليًا. يرجى المحاولة لاحقًا.',
      ),
      WalletRequestsError.unknown => _copy(
        'Unable to load wallet data. Please try again.',
        'تعذر تحميل بيانات المحفظة. يرجى المحاولة مرة أخرى.',
      ),
    };
  }

  String _copy(String en, String ar) {
    return Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
  }
}

/// The driver's money, in the terms the backend actually means.
///
/// Three different figures live on this card and only one of them is the
/// driver's own money, so each label says which:
///
///  * `totalDriverDue` is the driver's commission on closed shipments — their
///    earnings, and the only figure a withdrawal can draw on.
///  * `totalAccrued` is the COD they collected for those shipments less that
///    commission. The backend's own alias for it is `total_amount_after_discount`:
///    it is money owed to the company, not earnings, and labelling it as
///    earnings invited exactly the wrong conclusion.
///  * `totalShipCost` is the gross COD value of every unsettled shipment.
///
/// None of the amounts or the queries behind them are touched here; only the
/// wording is.
class _BalanceSummaryCard extends StatelessWidget {
  const _BalanceSummaryCard({
    required this.stats,
    required this.requests,
    required this.isLoading,
    required this.hasError,
    required this.pendingLoading,
    required this.pendingFailed,
    required this.copy,
  });

  final DriverStatisticsData? stats;
  final List<WithdrawalRequest> requests;
  final bool isLoading;
  final bool hasError;
  final bool pendingLoading;
  final bool pendingFailed;
  final String Function(String en, String ar) copy;

  @override
  Widget build(BuildContext context) {
    final pending = requests
        .where((request) => request.status == 0)
        .fold<double>(0, (sum, request) => sum + _asDouble(request.amount));
    final statsAvailable = stats != null && !hasError;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.gradient2, AppColors.gradient2],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy('Earnings due', 'الأرباح المستحقة'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Scales down rather than clipping: a six-figure balance
                    // used to lose its last digits to an ellipsis at 360px,
                    // and a truncated amount on a wallet is worse than a
                    // smaller one.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        isLoading
                            ? copy('Loading...', 'جارٍ التحميل...')
                            : !statsAvailable
                            ? copy('Not available', 'غير متوفر')
                            : formatMoney(context, stats!.totalDriverDue),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _WalletMetric(
                  label: copy(
                    'Pending withdrawals',
                    'طلبات سحب قيد الانتظار',
                  ),
                  // A failed read empties the request list, and a sum over an
                  // empty list is zero — which on a wallet reads as an
                  // authoritative "you have nothing pending". A genuine empty
                  // list still shows a real zero.
                  value:
                      pendingLoading
                          ? copy('Loading...', 'جارٍ التحميل...')
                          : pendingFailed
                          ? copy('Unavailable', 'غير متوفر')
                          : formatMoney(context, pending),
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WalletMetric(
                  label: copy('Delivered', 'تم التسليم'),
                  value:
                      !statsAvailable
                          ? copy('Unavailable', 'غير متوفر')
                          : '${stats!.shipmentsDelivered}',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _WalletMetric(
                  label: copy('Cash to settle', 'مبالغ مستحقة للشركة'),
                  value:
                      !statsAvailable
                          ? copy('Unavailable', 'غير متوفر')
                          : formatMoney(context, stats!.totalAccrued),
                  icon: Icons.account_balance_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WalletMetric(
                  label: copy('COD value', 'قيمة التحصيل'),
                  value:
                      !statsAvailable
                          ? copy('Unavailable', 'غير متوفر')
                          : formatMoney(context, stats!.totalShipCost),
                  icon: Icons.receipt_long_rounded,
                ),
              ),
            ],
          ),
          if (statsAvailable && stats!.commissionPending > 0) ...[
            const SizedBox(height: 10),
            _WalletMetric(
              label: copy(
                'Pending commission (fee not collected yet)',
                'عمولة معلّقة (لم تُحصّل الأجرة بعد)',
              ),
              value: formatMoney(context, stats!.commissionPending),
              icon: Icons.hourglass_bottom_rounded,
            ),
          ],
          const SizedBox(height: 14),
          // These four numbers are counted over different sets of shipments,
          // so they are not meant to add up. Saying so is cheaper than a
          // driver trying to reconcile them.
          Text(
            copy(
              'Earnings due is the commission you can withdraw now: it is backed '
                  'by a collected delivery fee. Pending commission becomes '
                  'withdrawable once its fee is collected. Cash to settle is the '
                  'COD and any delivery fee you collected at the door, minus your '
                  'withdrawable commission. COD value is the total COD value for '
                  'unsettled shipments, including ones still in progress. '
                  'Delivered counts delivered and completed shipments only.',
              'الأرباح المستحقة هي العمولة التي يمكنك سحبها الآن لأن أجرة '
                  'التوصيل الخاصة بها حُصّلت. العمولة المعلّقة تصبح قابلة للسحب '
                  'بعد تحصيل أجرتها. المبالغ المستحقة للشركة هي التحصيل وأي أجرة '
                  'توصيل حصّلتها من العميل، بعد خصم عمولتك القابلة للسحب. قيمة '
                  'التحصيل هي إجمالي قيمة التحصيل للشحنات غير المسوّاة بما فيها '
                  'قيد التنفيذ. "تم التسليم" يعدّ الشحنات المسلّمة والمكتملة فقط.',
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 10.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.82), size: 18),
          const SizedBox(height: 8),
          // Amounts scale down instead of losing their last digits, and the
          // labels are long enough in Arabic to need a second line.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalFormCard extends StatelessWidget {
  const _WithdrawalFormCard({
    required this.amountController,
    required this.amountFocusNode,
    required this.selectedMethod,
    required this.isSubmitting,
    required this.available,
    required this.reserved,
    required this.paid,
    required this.isBalanceLoading,
    required this.onMethodChanged,
    required this.onSubmit,
    required this.copy,
  });

  final TextEditingController amountController;
  final FocusNode amountFocusNode;
  final String selectedMethod;
  final bool isSubmitting;

  /// What the server says may be withdrawn. Null means it has not said, and
  /// the form refuses to guess.
  final double? available;
  final double? reserved;
  final double? paid;
  final bool isBalanceLoading;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onSubmit;
  final String Function(String en, String ar) copy;

  bool get _canSubmit => available != null && !isSubmitting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: copy('Request Withdrawal', 'طلب سحب'),
            subtitle: copy(
              'Enter an amount and choose a payment method',
              'أدخل المبلغ واختر طريقة الدفع',
            ),
          ),
          const SizedBox(height: 14),
          _AvailableToWithdraw(
            available: available,
            reserved: reserved,
            paid: paid,
            isLoading: isBalanceLoading,
            copy: copy,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amountController,
            focusNode: amountFocusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            enabled: _canSubmit,
            // Only what the backend accepts can be typed: digits, one dot and
            // at most two decimals. A comma, a minus, a plus and scientific
            // notation never reach the field, so the driver is not told off
            // for something the keyboard offered them.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              TextInputFormatter.withFunction((previous, next) {
                final text = next.text;
                if (text.isEmpty) return next;
                return RegExp(r'^[0-9]{0,10}(\.[0-9]{0,2})?$').hasMatch(text)
                    ? next
                    : previous;
              }),
            ],
            // The typed amount is digits and a decimal point: it reads
            // left-to-right in both languages, while the label, the unit and
            // the rest of the form keep the page direction.
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              labelText: copy('Amount', 'المبلغ'),
              hintText: '0.00',
              suffixText: currencyUnit(context),
              prefixIcon: const Icon(Icons.payments_outlined),
              filled: true,
              fillColor: const Color(0xffF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xffE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xffE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MethodChoice(
                  label: copy('Cash', 'نقداً'),
                  icon: Icons.account_balance_outlined,
                  isSelected: selectedMethod == 'cash',
                  onTap: isSubmitting ? null : () => onMethodChanged('cash'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MethodChoice(
                  label: 'CliQ',
                  icon: Icons.phone_android_rounded,
                  isSelected: selectedMethod == 'click',
                  onTap: isSubmitting ? null : () => onMethodChanged('click'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              // Disabled the instant a submission starts, and while the
              // available amount is unknown.
              onPressed: _canSubmit ? onSubmit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withValues(
                  alpha: 0.55,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child:
                  isSubmitting
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                      : Text(
                        copy('Submit Request', 'إرسال الطلب'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The only number that decides whether a withdrawal can be made.
///
/// It comes from the server and is never reconstructed here. When it is
/// missing the form says so and stays disabled, because a ceiling the app
/// invented is how a paid-out driver kept being offered money that was no
/// longer there.
class _AvailableToWithdraw extends StatelessWidget {
  const _AvailableToWithdraw({
    required this.available,
    required this.reserved,
    required this.paid,
    required this.isLoading,
    required this.copy,
  });

  final double? available;
  final double? reserved;
  final double? paid;
  final bool isLoading;
  final String Function(String en, String ar) copy;

  @override
  Widget build(BuildContext context) {
    final value =
        isLoading
            ? copy('Loading...', 'جارٍ التحميل...')
            : available == null
            ? copy('Unavailable', 'غير متوفر')
            : formatMoney(context, available!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffEAF3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffCFE2FB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy('Available to withdraw', 'المتاح للسحب'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff1E4E8C),
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (available == null && !isLoading) ...[
            const SizedBox(height: 6),
            Text(
              copy(
                'Your balance could not be loaded, so withdrawals are paused.',
                'تعذر تحميل رصيدك، لذا تم إيقاف طلبات السحب مؤقتاً.',
              ),
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (reserved != null || paid != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (reserved != null)
                  _InfoChip(
                    icon: Icons.lock_clock_outlined,
                    label:
                        '${copy('Reserved', 'محجوز')}: '
                        '${formatMoney(context, reserved!)}',
                  ),
                if (paid != null)
                  _InfoChip(
                    icon: Icons.task_alt_rounded,
                    label:
                        '${copy('Paid', 'مدفوع')}: '
                        '${formatMoney(context, paid!)}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodChoice extends StatelessWidget {
  const _MethodChoice({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xffEAF3FF) : const Color(0xffF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xffE2E8F0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.primary : const Color(0xff64748B),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      isSelected ? AppColors.primary : const Color(0xff475569),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xff64748B),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.copy});

  final WithdrawalRequest request;
  final String Function(String en, String ar) copy;

  @override
  Widget build(BuildContext context) {
    final amount = formatMoney(context, _asDouble(request.amount));
    final method = _methodLabel(request.withdrawalMethod, copy);
    final createdAt = _formatDate(request.requestedAt);
    final processedAt = _formatDate(request.processedAt);
    final reason = request.note.trim();
    // A reason only belongs to a decision that had one.
    final showReason =
        reason.isNotEmpty && request.status == 2;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xffEAF3FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.south_west_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      amount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      method,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(
                label: request.statusLabel(context),
                color: request.statusColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.event_outlined,
                label:
                    '${copy('Requested', 'تاريخ الطلب')}: '
                    '${createdAt ?? copy('Not available', 'غير متوفر')}',
              ),
              // Only once it has actually been processed.
              if (processedAt != null)
                _InfoChip(
                  icon: Icons.event_available_outlined,
                  label: '${copy('Processed', 'تاريخ المعالجة')}: $processedAt',
                ),
              _InfoChip(icon: Icons.payments_outlined, label: method),
            ],
          ),
          if (showReason) ...[
            const SizedBox(height: 10),
            _ReasonBlock(label: copy('Reason', 'السبب'), reason: reason),
          ],
        ],
      ),
    );
  }
}

/// The admin's note on a rejected request. Rendered only when there is one, so
/// a settled request never carries an empty labelled block.
class _ReasonBlock extends StatelessWidget {
  const _ReasonBlock({required this.label, required this.reason});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xffFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff991B1B),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            reason,
            style: const TextStyle(
              color: Color(0xff7F1D1D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xff64748B)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff475569),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          if (isLoading)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                color: AppColors.primary,
              ),
            )
          else
            Icon(icon, color: AppColors.primary, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(actionLabel!),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.isChanging,
    required this.onPrevious,
    required this.onNext,
    required this.copy,
  });

  final int currentPage;
  final int totalPages;
  final bool isChanging;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String Function(String en, String ar) copy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.primary,
            tooltip: copy('Previous', 'السابق'),
          ),
          Expanded(
            child:
                isChanging
                    ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                    : Text(
                      copy(
                        'Page $currentPage of $totalPages',
                        // The digits are isolated so the Arabic paragraph
                        // cannot reorder them around the words.
                        'صفحة ${isolateIdentifier('$currentPage')} من '
                            '${isolateIdentifier('$totalPages')}',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xff475569),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.primary,
            tooltip: copy('Next', 'التالي'),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xffE5EAF2)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xff0F172A).withValues(alpha: 0.06),
        blurRadius: 22,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String _methodLabel(String value, String Function(String en, String ar) copy) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'cash') return copy('Cash', 'نقداً');
  if (normalized == 'click' || normalized == 'cliq') return 'CliQ';
  if (normalized.isEmpty) return copy('Not available', 'غير متوفر');
  return value;
}

/// `dd/MM/yyyy` in Western digits, the same convention as every other screen.
///
/// Null for anything that cannot be trusted — an empty value, a zero date or
/// an unparseable one — so a raw MySQL timestamp can never reach the screen.
String? _formatDate(String value) {
  final parsed = Shipment.safeDateTime(value);
  if (parsed == null) return null;

  return DateFormat('dd/MM/yyyy', 'en').format(parsed);
}
