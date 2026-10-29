import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../provider/settlements/statement_handovers_provider.dart';
import '../../../services/statement_handover_service.dart';
import '../../../services/user_session_state.dart';

class StatementHandoversPage extends StatefulWidget {
  const StatementHandoversPage({super.key});
  @override
  State<StatementHandoversPage> createState() => _StatementHandoversPageState();
}

class _StatementHandoversPageState extends State<StatementHandoversPage> {
  final _provider = StatementHandoversProvider();
  @override
  void initState() {
    super.initState();
    _provider.load();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'تسليم النقد للعملاء' : 'Merchant cash handovers'),
      ),
      body: AnimatedBuilder(
        animation: _provider,
        builder:
            (context, _) => RefreshIndicator(
              onRefresh: _provider.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    ar
                        ? 'سلّم المبلغ المتبقي للعميل أولًا، ثم اطلب منه رمز التسليم من تفاصيل الكشف.'
                        : 'Pay the remaining amount first, then ask the merchant for the code in Statement Details.',
                  ),
                  if (_provider.loading) const LinearProgressIndicator(),
                  if (_provider.error != null)
                    TextButton(
                      onPressed: _provider.load,
                      child: Text(
                        ar
                            ? 'تعذر التحميل. إعادة المحاولة'
                            : 'Unable to load. Retry',
                      ),
                    ),
                  if (!_provider.loading &&
                      _provider.items.isEmpty &&
                      _provider.error == null)
                    Text(
                      ar
                          ? 'لا توجد كشوف معيّنة لك بانتظار التسليم.'
                          : 'No pending handovers assigned to you.',
                    ),
                  for (final item in _provider.items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(item.number),
                            Text(item.clientName),
                            Text('JOD ${item.amount}'),
                            FilledButton(
                              onPressed:
                                  _provider.submitting
                                      ? null
                                      : () async {
                                        final generation =
                                            UserSessionState.generation;
                                        final done = await showDialog<bool>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder:
                                              (_) => HandoverEntryDialog(
                                                item: item,
                                                provider: _provider,
                                                ar: ar,
                                              ),
                                        );
                                        if (!context.mounted ||
                                            generation !=
                                                UserSessionState.generation) {
                                          return;
                                        }
                                        if (done == true) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                ar
                                                    ? 'تم تأكيد تسليم النقد ودفع الكشف.'
                                                    : 'Cash handover confirmed. Statement paid.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              child: Text(
                                ar
                                    ? 'إدخال رمز التسليم'
                                    : 'Enter Handover Code',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_provider.hasMore)
                    TextButton(
                      onPressed:
                          _provider.loading
                              ? null
                              : () => _provider.load(more: true),
                      child: Text(ar ? 'المزيد' : 'Load more'),
                    ),
                ],
              ),
            ),
      ),
    );
  }
}

class HandoverEntryDialog extends StatefulWidget {
  const HandoverEntryDialog({
    super.key,
    required this.item,
    required this.provider,
    required this.ar,
  });
  final CashHandover item;
  final StatementHandoversProvider provider;
  final bool ar;
  @override
  State<HandoverEntryDialog> createState() => _HandoverEntryDialogState();
}

class _HandoverEntryDialogState extends State<HandoverEntryDialog>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  bool _busy = false;
  bool _expired = false;
  String? _error;
  late final int _generation;
  @override
  void initState() {
    super.initState();
    _generation = UserSessionState.generation;
    UserSessionState.register(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _sessionChanged() {
    _code.clear();
    if (mounted) {
      setState(() {
        _expired = true;
        _error = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _code.clear();
  }

  @override
  void dispose() {
    UserSessionState.unregister(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  /// The server counts every rejected code against a five-strike lockout, so
  /// a code that cannot possibly be right is stopped here rather than spent.
  static const int _codeLength = 6;

  bool get _isComplete => _code.text.length == _codeLength;

  Future<void> _submit() async {
    if (_busy || _expired || _generation != UserSessionState.generation) return;

    if (!_isComplete) {
      // Without this an empty field was submitted verbatim, and the driver was
      // told to "check the code and statement status" for a code they had not
      // entered — while it burned one of their five attempts.
      setState(() {
        _error =
            widget.ar
                ? 'أدخل رمز التسليم المكوّن من 6 أرقام.'
                : 'Enter the 6-digit handover code.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final code = _code.text;
    try {
      await widget.provider.complete(widget.item.id, code);
      if (mounted && _generation == UserSessionState.generation) {
        // Cleared only once it has been accepted. Wiping it before the request
        // meant any failure cost the driver all six digits again.
        _code.clear();
        Navigator.pop(context, true);
      }
    } on SessionChanged {
      if (mounted) _sessionChanged();
    } catch (error) {
      if (mounted && _generation == UserSessionState.generation) {
        setState(() {
          _error =
              error is HandoverException && error.code == 'HANDOVER_RETRY_LATER'
                  ? (widget.ar
                      ? 'محاولات كثيرة. حاول بعد 15 دقيقة.'
                      : 'Too many attempts. Retry in 15 minutes.')
                  : (widget.ar
                      ? 'لم يتم تأكيد التسليم. تحقق من الرمز وحالة الكشف ثم حاول مجددًا.'
                      : 'Handover was not confirmed. Check the code and statement status, then retry.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.ar ? 'إدخال رمز التسليم' : 'Enter Handover Code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_expired)
            Text('${widget.item.number} — JOD ${widget.item.amount}'),
          if (_expired)
            Text(
              widget.ar
                  ? 'تغيّر الحساب. أغلق هذه النافذة.'
                  : 'Account changed. Close this dialog.',
            )
          else
            TextField(
              controller: _code,
              enabled: !_busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: _codeLength,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // Keeps the confirm button and the counter in step with what has
              // been typed.
              onChanged: (_) => setState(() => _error = null),
              // Always goes through _submit, so pressing done on a short code
              // says what is missing instead of doing nothing.
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText:
                    widget.ar
                        ? 'رمز العميل (6 أرقام)'
                        : 'Merchant code (6 digits)',
              ),
            ),
          if (_error != null) Text(_error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(widget.ar ? 'إغلاق' : 'Close'),
        ),
        FilledButton(
          // Disabled until six digits are present, so the lockout counter is
          // only ever spent on a code the driver actually entered.
          onPressed: _busy || _expired || !_isComplete ? null : _submit,
          child: Text(widget.ar ? 'تأكيد التسليم' : 'Confirm handover'),
        ),
      ],
    ),
  );
}
