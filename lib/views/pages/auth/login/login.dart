import 'package:blockatie/constants/oiiax_brand.dart';
import 'package:blockatie/provider/login.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/pages/auth/signup/register.dart';
import 'package:blockatie/views/pages/hub/components/custom_toggle_btn.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart'
    show SupportAssistencePage;
import 'package:blockatie/views/widgets/protected_blockatie_attribution.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const Color _loginBlue = OIIAXBrand.primary;
const Color _loginCyan = OIIAXBrand.primary;
const Color _loginDeepBlue = OIIAXBrand.charcoal;
const Color _loginText = OIIAXBrand.charcoal;
const Color _loginMuted = Color(0xFF687587);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final AnimationController _controller;
  late final Animation<double> _headerOpacity;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _cardOpacity;
  late final Animation<Offset> _cardSlide;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _headerOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .58, curve: Curves.easeOut),
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -.10),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .62, curve: Curves.easeOutCubic),
      ),
    );
    _cardOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.22, 1, curve: Curves.easeOut),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, .12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(.22, 1, curve: Curves.easeOutCubic),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoginProvider>();
    // The same locale MaterialApp resolved, which is also what Directionality
    // is built from. Reading EasyLocalization's own locale here could disagree
    // with the app's actual language and put Arabic text in an LTR layout.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        onTap: FocusScope.of(context).unfocus,
        child: Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: true,
          body: Stack(
            children: [
              const Positioned.fill(child: _LoginBackground()),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxHeight < 680;
                    final horizontalPadding =
                        constraints.maxWidth < 360 ? 20.0 : 24.0;
                    final contentWidth =
                        (constraints.maxWidth - (horizontalPadding * 2))
                            .clamp(280.0, 430.0)
                            .toDouble();

                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      // The Scaffold already resizes for the keyboard, so the
                      // inset must not be subtracted a second time here. It
                      // used to be, which on a short screen drove the minimum
                      // height below zero and threw during layout.
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        isCompact ? 22 : 34,
                        horizontalPadding,
                        24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight -
                                  (isCompact ? 46 : 58))
                              .clamp(0.0, double.infinity),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: contentWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FadeTransition(
                                  opacity: _headerOpacity,
                                  child: SlideTransition(
                                    position: _headerSlide,
                                    child: _LoginHeader(isArabic: isArabic),
                                  ),
                                ),
                                SizedBox(height: isCompact ? 22 : 30),
                                FadeTransition(
                                  opacity: _cardOpacity,
                                  child: SlideTransition(
                                    position: _cardSlide,
                                    child: _LoginCard(
                                      formKey: _formKey,
                                      provider: provider,
                                      isArabic: isArabic,
                                      obscurePassword: _obscurePassword,
                                      onTogglePassword: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                      onSubmit: _submit,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const ProtectedBlockatieAttribution(),
                              ],
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

  Future<void> _submit(LoginProvider provider) async {
    FocusScope.of(context).unfocus();
    provider.clearError();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    await provider.logIn();
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          AppImages.logo,
          width: 188,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 10),
        Text(
          isArabic
              ? 'سجّل الدخول لإدارة عمليات التوصيل'
              : 'Sign in to manage deliveries',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: .82),
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 18),
        CustomToggleBtn(
          onTabChanged: (index) {
            if (index == 1) {
              Nav.to(const SupportAssistencePage());
            }
          },
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.provider,
    required this.isArabic,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final LoginProvider provider;
  final bool isArabic;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final Future<void> Function(LoginProvider provider) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .14),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isArabic ? 'مرحبًا بعودتك' : 'Welcome back',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _loginText,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'أدخل رقم الهاتف وكلمة المرور للمتابعة'
                  : 'Enter your phone and password to continue',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _loginMuted,
                fontWeight: FontWeight.w500,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 22),
            _LoginTextField(
              controller: provider.phoneCont,
              label: isArabic ? 'رقم الهاتف' : 'Phone number',
              hint: '07xxxxxxxx',
              icon: Icons.phone_rounded,
              prefixIconOverride: const _JordanPhonePrefix(),
              enabled: !provider.isLoading,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              contentTextDirection: TextDirection.ltr,
              // Digits only: the backend takes a local 10-digit Jordan number,
              // so a '+' would never be valid here.
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(
                  LoginProvider.jordanPhoneLength,
                ),
              ],
              onChanged: (_) => provider.clearError(),
              // One rule set, shared with the provider, matching what
              // api_driver_login.php actually accepts.
              validator: (value) => LoginProvider.phoneValidationMessage(
                value,
                isArabic: isArabic,
              ),
            ),
            const SizedBox(height: 14),
            _LoginTextField(
              controller: provider.passCont,
              label: isArabic ? 'كلمة المرور' : 'Password',
              hint: '••••••••',
              icon: Icons.lock_rounded,
              enabled: !provider.isLoading,
              obscureText: obscurePassword,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              contentTextDirection: TextDirection.ltr,
              onFieldSubmitted: (_) => onSubmit(provider),
              onChanged: (_) => provider.clearError(),
              suffix: IconButton(
                tooltip:
                    obscurePassword
                        ? (isArabic ? 'إظهار كلمة المرور' : 'Show password')
                        : (isArabic ? 'إخفاء كلمة المرور' : 'Hide password'),
                onPressed: provider.isLoading ? null : onTogglePassword,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: _loginMuted,
                  size: 20,
                ),
              ),
              validator: (value) => LoginProvider.passwordValidationMessage(
                value,
                isArabic: isArabic,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: provider.isChecked,
                    onChanged:
                        provider.isLoading
                            ? null
                            : (value) => provider.setCheckbox(value ?? false),
                    activeColor: _loginBlue,
                    side: const BorderSide(color: Color(0xFFD4DDE8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isArabic ? 'تذكرني' : 'Remember me',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _loginMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child:
                  provider.errorMessage == null
                      ? const SizedBox(height: 14)
                      : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _LoginError(message: provider.errorMessage!),
                      ),
            ),
            const SizedBox(height: 18),
            _LoginButton(
              isLoading: provider.isLoading,
              label: isArabic ? 'تسجيل الدخول' : 'Sign in',
              onPressed: provider.isLoading ? null : () => onSubmit(provider),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  isArabic ? 'ليس لديك حساب؟ ' : "Don't have an account? ",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _loginMuted,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap:
                      provider.isLoading
                          ? null
                          : () => Nav.offAll(const RegisterPage()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    child: Text(
                      isArabic ? 'إنشاء حساب' : 'Sign up',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _loginBlue,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
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

/// Static Jordan prefix.
///
/// This replaced a country picker whose selection was discarded: the backend
/// accepts local Jordanian numbers only (077/078/079), so offering a country
/// list promised something the API cannot honour. Nothing here is selectable.
class _JordanPhonePrefix extends StatelessWidget {
  const _JordanPhonePrefix();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phone_rounded, color: _loginBlue, size: 20),
          const SizedBox(width: 8),
          // Dial codes read left-to-right in both languages.
          const Text(
            '+962',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: _loginText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: const Color(0xFFE2EAF3)),
        ],
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.enabled,
    required this.keyboardType,
    required this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.prefixIconOverride,
    this.suffix,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.contentTextDirection,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool enabled;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? prefixIconOverride;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  /// Direction of the typed content only. Phone numbers and passwords are
  /// entered left-to-right even in Arabic; the label, hint and error around
  /// them stay with the page direction.
  final TextDirection? contentTextDirection;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      validator: validator,
      // Once the driver has touched a field, corrections clear the error as
      // they type. Without this the message from a failed submit stays on
      // screen even after the number is fixed.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      textDirection: contentTextDirection,
      textAlign:
          contentTextDirection == TextDirection.ltr
              ? TextAlign.left
              : TextAlign.start,
      cursorColor: _loginBlue,
      style: const TextStyle(
        color: _loginText,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF5F8FC),
        prefixIcon:
            prefixIconOverride ?? Icon(icon, color: _loginBlue, size: 20),
        prefixIconConstraints:
            prefixIconOverride == null
                ? null
                : const BoxConstraints(minWidth: 108, minHeight: 48),
        suffixIcon: suffix,
        labelStyle: const TextStyle(
          color: _loginMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        hintStyle: TextStyle(
          color: _loginMuted.withValues(alpha: .70),
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2EAF3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _loginBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE25555), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE25555), width: 1.4),
        ),
      ),
    );
  }
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(message),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD1D1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFE25555),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF9B2E2E),
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.isLoading,
    required this.label,
    required this.onPressed,
  });

  final bool isLoading;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _loginBlue,
          disabledBackgroundColor: _loginBlue.withValues(alpha: .70),
          foregroundColor: OIIAXBrand.charcoal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child:
              isLoading
                  ? const SizedBox(
                    key: ValueKey('loading'),
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        OIIAXBrand.charcoal,
                      ),
                    ),
                  )
                  : Row(
                    key: const ValueKey('label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
                  ),
        ),
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_loginBlue, _loginDeepBlue],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(.65, -.65),
                        radius: 1.1,
                        colors: [
                          _loginCyan.withValues(alpha: .18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Expanded(flex: 4, child: ColoredBox(color: Colors.white)),
      ],
    );
  }
}
