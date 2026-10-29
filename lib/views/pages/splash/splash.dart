import 'package:blockatie/constants/oiiax_brand.dart';
import 'package:blockatie/provider/bottom_nav.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/views/pages/welcome/driver_welcome_page.dart';
import 'package:blockatie/views/widgets/bottom_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The first Flutter-controlled frame. Android and iOS native launches stay
/// platform-compliant; this page is where the supplied delivery photograph is
/// shown without native-splash restrictions.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _startStartupFlow();
  }

  Future<void> _startStartupFlow() async {
    final stopwatch = Stopwatch()..start();
    DriverSession session;

    try {
      session = await AuthService.getSessionSnapshot();
    } catch (_) {
      session = const DriverSession();
    }

    if (!mounted || _didNavigate) return;
    _didNavigate = true;

    if (kDebugMode) {
      debugPrint(
        'Splash session check completed in ${stopwatch.elapsedMilliseconds}ms. '
        'Target: ${session.isAuthenticated ? 'home' : 'welcome'}',
      );
    }

    if (session.isAuthenticated) {
      context.read<BottomNavProvider>().setIndex(0);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CustomBottomNavBar()),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DriverWelcomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: OIIAXBrand.charcoal,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: const Scaffold(
        backgroundColor: OIIAXBrand.charcoal,
        body: _DriverSplashArtwork(),
      ),
    );
  }
}

class _DriverSplashArtwork extends StatelessWidget {
  const _DriverSplashArtwork();

  static const _sourceAspectRatio = 863 / 1822;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A phone gets edge-to-edge artwork. Wider formats retain every major
        // element instead of aggressively cropping the van, scooter, or boxes.
        final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final fit = screenAspectRatio > _sourceAspectRatio * 1.18
            ? BoxFit.contain
            : BoxFit.cover;
        final logoWidth =
            (constraints.maxWidth * .42).clamp(136.0, 184.0).toDouble();

        return ColoredBox(
          color: OIIAXBrand.charcoal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                OIIAXBrand.driverSplash,
                key: const Key('oiiax-driver-splash-artwork'),
                fit: fit,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'OIIAX delivery van, scooter, and packages',
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Image.asset(
                      OIIAXBrand.logoLight,
                      width: logoWidth,
                      fit: BoxFit.contain,
                      semanticLabel: 'OIIAX',
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
