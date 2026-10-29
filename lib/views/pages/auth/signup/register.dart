import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/provider/register.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/password_policy.dart';
import 'package:blockatie/utils/register_rules.dart';
import 'package:blockatie/views/pages/auth/login/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// Set the moment a successful registration has been handled, so a second
  /// reply — or a second tap that raced the first — cannot navigate again.
  bool _completed = false;

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  String _text(String ar, String en) => _isArabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _submit(RegisterProvider provider) async {
    if (_completed || provider.isLoading) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final result = await provider.register();

    // The reply may land after the driver has left. Nothing below may run then:
    // a dialog on a dead route and a second navigation are both worse than
    // silence.
    if (!mounted || _completed) return;

    if (!result.isSuccess) {
      // Input is deliberately left untouched so a recoverable failure does not
      // cost the driver the whole form.
      _showSnack(_outcomeMessage(result.outcome), isError: true);
      return;
    }

    _completed = true;
    // Registration is not a login. The account exists and is waiting for an
    // Admin, so the only place to go is back to sign in — and `offAll` leaves
    // no Register route underneath it.
    await _showPendingActivationDialog();
    if (!mounted) return;
    Nav.offAll(const LoginPage());
  }

  /// Confirms the account was created and says plainly that it is not yet
  /// usable. It never claims the driver is signed in or ready for work.
  Future<void> _showPendingActivationDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            icon: const Icon(
              Icons.mark_email_read_outlined,
              color: Color(0xFF16A06D),
              size: 34,
            ),
            title: Text(
              _text('تم التسجيل', 'Registration completed'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            content: Text(
              _text(
                'تم التسجيل بنجاح. حسابك بانتظار التفعيل.',
                'Registration completed. Your account is awaiting activation.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF687587),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _text('العودة لتسجيل الدخول', 'Back to login'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// App-owned wording for every outcome.
  ///
  /// The endpoint's own sentence is never rendered: it used to be, which is how
  /// `DB_PREPARE_ERROR` — "Database prepare error." — and a bare
  /// "Status Code: 500" could reach a driver.
  String _outcomeMessage(RegisterOutcome outcome) {
    return switch (outcome) {
      RegisterOutcome.success => _text(
        'تم التسجيل بنجاح. حسابك بانتظار التفعيل.',
        'Registration completed. Your account is awaiting activation.',
      ),
      RegisterOutcome.requiredFields => _text(
        'يرجى تعبئة جميع الحقول المطلوبة.',
        'Please fill in all required fields.',
      ),
      RegisterOutcome.nameTooLong => _text(
        'الاسم يجب ألا يتجاوز $kRegisterNameMaxLength حرفاً.',
        'Name must be at most $kRegisterNameMaxLength characters.',
      ),
      RegisterOutcome.phoneTooLong || RegisterOutcome.phoneTooShort => _text(
        'رقم الهاتف يجب أن يتكون من 10 أرقام.',
        'Phone number must be exactly 10 digits.',
      ),
      RegisterOutcome.invalidPhonePrefix => _text(
        'بادئة رقم الهاتف غير صحيحة (المسموح: 077 أو 078 أو 079).',
        'Invalid phone prefix (allowed: 077, 078, 079).',
      ),
      RegisterOutcome.weakPassword => _text(
        'كلمة المرور يجب أن تكون $kRegisterPasswordMinLength أحرف على الأقل.',
        'Password must be at least $kRegisterPasswordMinLength characters.',
      ),
      RegisterOutcome.passwordTooLong => _text(
        'كلمة المرور طويلة جداً.',
        'Password is too long.',
      ),
      RegisterOutcome.tooManyAttempts => _text(
        'محاولات تسجيل كثيرة. يرجى المحاولة لاحقاً.',
        'Too many registration attempts. Please try again later.',
      ),
      RegisterOutcome.phoneExists => _text(
        'رقم الهاتف مسجل بالفعل.',
        'This phone number is already registered.',
      ),
      RegisterOutcome.network => _text(
        'تعذر الاتصال. يرجى المحاولة مرة أخرى.',
        'Unable to connect. Please try again.',
      ),
      RegisterOutcome.invalidResponse || RegisterOutcome.serverError => _text(
        'تعذر إكمال التسجيل. يرجى المحاولة لاحقاً.',
        'Unable to complete registration. Please try again later.',
      ),
    };
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? const Color(0xffDC2626) : const Color(0xff16A06D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RegisterProvider>();
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        onTap: FocusScope.of(context).unfocus,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: const Color(0xFFF3F7FC),
          body: Stack(
            children: [
              const _RegisterBackground(),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 700;
                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        compact ? 24 : 36,
                        20,
                        viewInsets.bottom + 28,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight -
                              viewInsets.bottom -
                              (compact ? 48 : 64),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _RegisterHeader(
                                    isArabic: _isArabic,
                                    onBack: () => Nav.offAll(const LoginPage()),
                                  ),
                                  SizedBox(height: compact ? 22 : 30),
                                  _RegisterCard(
                                    formKey: _formKey,
                                    provider: provider,
                                    isArabic: _isArabic,
                                    obscurePassword: _obscurePassword,
                                    onTogglePassword: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    obscureConfirmPassword:
                                        _obscureConfirmPassword,
                                    onToggleConfirmPassword: () {
                                      setState(() {
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword;
                                      });
                                    },
                                    onSubmit: () => _submit(provider),
                                    onLogin:
                                        () => Nav.offAll(const LoginPage()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterHeader extends StatelessWidget {
  const _RegisterHeader({required this.isArabic, required this.onBack});

  final bool isArabic;
  final VoidCallback onBack;

  String _text(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: isArabic ? Alignment.centerRight : Alignment.centerLeft,
          child: Tooltip(
            message: _text('العودة لتسجيل الدخول', 'Back to sign in'),
            child: Material(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onBack,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    isArabic
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Image.asset(
          AppImages.logo,
          width: 158,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 14),
        Text(
          _text('إنشاء حساب سائق', 'Create driver account'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _text(
            'أنشئ حسابك وابدأ إدارة عمليات التوصيل بثقة.',
            'Create your account and start managing deliveries with confidence.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .84),
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _RegisterCard extends StatelessWidget {
  const _RegisterCard({
    required this.formKey,
    required this.provider,
    required this.isArabic,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.obscureConfirmPassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
    required this.onLogin,
  });

  final GlobalKey<FormState> formKey;
  final RegisterProvider provider;
  final bool isArabic;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final bool obscureConfirmPassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onSubmit;
  final VoidCallback onLogin;

  String _text(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .13),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _text('بيانات التسجيل', 'Registration details'),
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Color(0xFF14243A),
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _text(
                'أدخل بياناتك الأساسية لإنشاء حساب السائق.',
                'Enter your basic details to create your driver account.',
              ),
              textAlign: TextAlign.start,
              style: const TextStyle(
                color: Color(0xFF687587),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            _RegisterField(
              controller: provider.nameCont,
              label: _text('اسم السائق', 'Driver name'),
              icon: Icons.person_outline_rounded,
              enabled: !provider.isLoading,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (isRegisterNameTooLong(value)) {
                  return _text(
                    'الاسم يجب ألا يتجاوز $kRegisterNameMaxLength حرفاً',
                    'Name must be at most $kRegisterNameMaxLength characters',
                  );
                }
                if (!isValidRegisterName(value)) {
                  return _text(
                    'يرجى إدخال اسم السائق بشكل صحيح',
                    'Enter a valid driver name',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _RegisterField(
              controller: provider.phoneCont,
              label: _text('رقم الهاتف', 'Phone number'),
              icon: Icons.phone_rounded,
              enabled: !provider.isLoading,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              isIdentifier: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                LengthLimitingTextInputFormatter(15),
              ],
              // The server's own rules, in the server's order, so the form and
              // the endpoint never disagree about the same number. Both
              // `0791234567` and `+962791234567` pass — they canonicalize to
              // one value, which is the one the UNIQUE key protects.
              validator: (value) {
                return switch (registerPhoneProblem(value)) {
                  RegisterPhoneProblem.empty => _text(
                    'رقم الهاتف مطلوب',
                    'Phone number is required',
                  ),
                  RegisterPhoneProblem.tooShort ||
                  RegisterPhoneProblem.tooLong => _text(
                    'رقم الهاتف يجب أن يتكون من 10 أرقام',
                    'Phone number must be exactly 10 digits',
                  ),
                  RegisterPhoneProblem.invalidPrefix => _text(
                    'البادئة المسموحة: 077 أو 078 أو 079',
                    'Allowed prefixes: 077, 078, 079',
                  ),
                  null => null,
                };
              },
            ),
            const SizedBox(height: 14),
            _RegisterField(
              controller: provider.passCont,
              label: _text('كلمة المرور', 'Password'),
              icon: Icons.lock_outline_rounded,
              enabled: !provider.isLoading,
              obscureText: obscurePassword,
              keyboardType: TextInputType.visiblePassword,
              // Was `done`; confirm password now follows it, so the keyboard
              // advances there instead of trying to submit a half-filled form.
              suffix: IconButton(
                tooltip:
                    obscurePassword
                        ? _text('إظهار كلمة المرور', 'Show password')
                        : _text('إخفاء كلمة المرور', 'Hide password'),
                onPressed: provider.isLoading ? null : onTogglePassword,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: const Color(0xFF687587),
                  size: 20,
                ),
              ),
              isSecret: true,
              textInputAction: TextInputAction.next,
              validator: (value) {
                return switch (registerPasswordProblem(value)) {
                  RegisterPasswordProblem.tooShort => _text(
                    'كلمة المرور يجب أن تكون $kRegisterPasswordMinLength أحرف على الأقل',
                    'Password must be at least $kRegisterPasswordMinLength characters',
                  ),
                  RegisterPasswordProblem.tooLong => _text(
                    'كلمة المرور طويلة جداً',
                    'Password is too long',
                  ),
                  RegisterPasswordProblem.weak => _text(
                    PasswordPolicy.rules(isArabic: true),
                    PasswordPolicy.rules(isArabic: false),
                  ),
                  null => null,
                };
              },
            ),
            const SizedBox(height: 14),
            _RegisterField(
              controller: provider.confirmPassCont,
              label: _text('تأكيد كلمة المرور', 'Confirm password'),
              icon: Icons.lock_reset_rounded,
              enabled: !provider.isLoading,
              obscureText: obscureConfirmPassword,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              isSecret: true,
              suffix: IconButton(
                tooltip:
                    obscureConfirmPassword
                        ? _text('إظهار كلمة المرور', 'Show password')
                        : _text('إخفاء كلمة المرور', 'Hide password'),
                onPressed: provider.isLoading ? null : onToggleConfirmPassword,
                icon: Icon(
                  obscureConfirmPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: const Color(0xFF687587),
                  size: 20,
                ),
              ),
              onSubmitted: (_) => onSubmit(),
              // Compared, never sent: this exists only so a mistyped password
              // does not silently become the account password, with no reset
              // path to recover it.
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return _text(
                    'تأكيد كلمة المرور مطلوب',
                    'Confirm password is required',
                  );
                }
                if (value != provider.passCont.text) {
                  return _text(
                    'كلمتا المرور غير متطابقتين.',
                    'Passwords do not match.',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: provider.isLoading ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: .70,
                  ),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child:
                    provider.isLoading
                        ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Flexible, because the English label plus the
                            // arrow overflowed this button by 21px at 360
                            // width. The label gives way rather than painting
                            // past the edge.
                            Flexible(
                              child: Text(
                                _text('إنشاء الحساب', 'Create account'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isArabic
                                  ? Icons.arrow_back_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          ],
                        ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _text('لديك حساب بالفعل؟ ', 'Already have an account? '),
                  style: const TextStyle(
                    color: Color(0xFF687587),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: provider.isLoading ? null : onLogin,
                  child: Text(
                    _text('تسجيل الدخول', 'Sign in'),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterField extends StatelessWidget {
  const _RegisterField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
    this.isIdentifier = false,
    this.isSecret = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  /// A phone number: left-to-right content that keeps its own direction inside
  /// an Arabic form. Prose fields follow the page.
  final bool isIdentifier;

  /// A password. Also left-to-right, and additionally kept away from the
  /// keyboard's correction and suggestion machinery — a corrected password is a
  /// password the driver did not choose, and suggestions would offer it back.
  final bool isSecret;

  @override
  Widget build(BuildContext context) {
    final forceLtr = isIdentifier || isSecret;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      autocorrect: !isSecret,
      enableSuggestions: !isSecret,
      autofillHints:
          isSecret
              ? const [AutofillHints.newPassword]
              : (isIdentifier ? const [AutofillHints.telephoneNumber] : null),
      textDirection: forceLtr ? TextDirection.ltr : null,
      textAlign: forceLtr ? TextAlign.left : TextAlign.start,
      style: const TextStyle(
        color: Color(0xFF14243A),
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: true,
        fillColor: const Color(0xFFF5F8FC),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        suffixIcon: suffix,
        labelStyle: const TextStyle(
          color: Color(0xFF687587),
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE1E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE25555)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE25555), width: 1.5),
        ),
      ),
    );
  }
}

class _RegisterBackground extends StatelessWidget {
  const _RegisterBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primary, AppColors.gradient2],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -68,
            child: _GlowCircle(color: Colors.white.withValues(alpha: .10)),
          ),
          Positioned(
            left: -110,
            bottom: -130,
            child: _GlowCircle(
              color: AppColors.primary.withValues(alpha: .18),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
