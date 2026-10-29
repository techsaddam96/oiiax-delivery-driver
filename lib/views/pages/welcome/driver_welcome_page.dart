import 'package:blockatie/constants/colors.dart';
import 'package:blockatie/constants/oiiax_brand.dart';
import 'package:blockatie/utils/app_images.dart';
import 'package:blockatie/views/pages/auth/login/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _driverWelcomeBackground = OIIAXBrand.driverSplash;

/// The unauthenticated cinematic entry point for drivers.
class DriverWelcomePage extends StatefulWidget {
  const DriverWelcomePage({super.key, this.onLogin});

  @visibleForTesting
  final VoidCallback? onLogin;

  @override
  State<DriverWelcomePage> createState() => _DriverWelcomePageState();
}

class _DriverWelcomePageState extends State<DriverWelcomePage>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _sceneController;
  late final Animation<Offset> _contentSlide;
  late final Animation<double> _sceneMotion;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _sceneController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, .025),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _sceneMotion = CurvedAnimation(
      parent: _sceneController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion == reduceMotion && _entranceController.isAnimating) {
      return;
    }
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _sceneController.stop();
      _entranceController.value = 1;
    } else {
      _entranceController.forward();
      if (!_sceneController.isAnimating) {
        _sceneController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _sceneController.dispose();
    super.dispose();
  }

  void _openLogin() {
    final callback = widget.onLogin;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final headline = isArabic ? 'انطلق مع OIIAX' : 'Drive with OIIAX';
    final description =
        isArabic
            ? 'رحلتك في عالم التوصيل تبدأ من هنا.'
            : 'Your delivery journey starts here.';
    final loginLabel = isArabic ? 'الدخول' : 'Login';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: OIIAXBrand.charcoal,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: OIIAXBrand.charcoal,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _sceneMotion,
              builder:
                  (context, child) => Transform.translate(
                    offset: Offset(0, -10 * _sceneMotion.value),
                    child: Transform.scale(
                      scale: 1 + (_sceneMotion.value * .045),
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  ),
              child: Image.asset(
                _driverWelcomeBackground,
                key: const Key('driver-welcome-background'),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
                semanticLabel: 'OIIAX delivery fleet',
              ),
            ),
            const _CinematicScrim(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 680;
                  final logoSize = compact ? 180.0 : 204.0;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      compact ? 12 : 20,
                      24,
                      compact ? 14 : 20,
                    ),
                    child: FadeTransition(
                      opacity: _entranceController,
                      child: SlideTransition(
                        position: _contentSlide,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: AlignmentDirectional.center,
                              child: AnimatedBuilder(
                                animation: _sceneMotion,
                                builder:
                                    (context, child) => Transform.translate(
                                      offset: Offset(
                                        0,
                                        -10 * _sceneMotion.value,
                                      ),
                                      child: Transform.scale(
                                        scale: 1 + (_sceneMotion.value * .045),
                                        alignment: Alignment.center,
                                        child: child,
                                      ),
                                    ),
                                child: Image.asset(
                                  AppImages.logo,
                                  width: logoSize,
                                  height: logoSize,
                                  fit: BoxFit.contain,
                                  semanticLabel: 'OIIAX',
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 24),
                            Text(
                              headline,
                              textAlign: TextAlign.center,
                              style: Theme.of(
                                context,
                              ).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontSize: compact ? 26 : 29,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                                shadows: const [_TextShadow()],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              description,
                              textAlign: TextAlign.center,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: .94),
                                fontSize: 15,
                                height: 1.6,
                                shadows: const [_TextShadow(blurRadius: 9)],
                              ),
                            ),
                            const Spacer(),
                            Semantics(
                              button: true,
                              label:
                                  isArabic
                                      ? 'الدخول إلى حساب OIIAX'
                                      : 'Log in to your OIIAX account',
                              child: SizedBox(
                                height: 56,
                                child: FilledButton.icon(
                                  key: const Key('driver-welcome-login'),
                                  onPressed: _openLogin,
                                  icon: Icon(
                                    isArabic
                                        ? Icons.arrow_back_rounded
                                        : Icons.arrow_forward_rounded,
                                  ),
                                  label: Text(loginLabel),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: OIIAXBrand.charcoal,
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    elevation: 1,
                                    shadowColor: const Color(0x66000D26),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}

class _TextShadow extends Shadow {
  const _TextShadow({super.blurRadius = 12})
    : super(color: const Color(0x66000D26), offset: const Offset(0, 3));
}

class _CinematicScrim extends StatelessWidget {
  const _CinematicScrim();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .42, .72, 1],
          colors: [
            Color(0x10000D26),
            Color(0x06000D26),
            Color(0x2D000D26),
            Color(0x95000D26),
          ],
        ),
      ),
    ),
  );
}
