import 'package:blockatie/provider/operational_readiness.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/views/bottmsheets/logout_sheet.dart';
import 'package:blockatie/views/pages/driver-location/driver_location.dart';
import 'package:blockatie/views/pages/hub/support&assistance/support_assistence.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OperationalGuardOverlay extends StatelessWidget {
  const OperationalGuardOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final readiness = context.watch<OperationalReadinessProvider>();
    if (!readiness.hasStarted || readiness.isReady) {
      return const SizedBox.shrink();
    }

    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final vpn = readiness.state == OperationalReadinessState.vpnActive;
    final permanent =
        readiness.state ==
        OperationalReadinessState.locationPermissionPermanentlyDenied;
    final title =
        vpn
            ? (ar ? 'تم اكتشاف VPN' : 'VPN detected')
            : readiness.state == OperationalReadinessState.locationServiceOff
            ? (ar ? 'خدمة الموقع متوقفة' : 'Location service is off')
            : permanent
            ? (ar ? 'صلاحية الموقع مطلوبة' : 'Location permission required')
            : (ar ? 'الموقع غير جاهز' : 'Location is not ready');
    final message =
        vpn
            ? (ar
                ? 'يرجى إيقاف الـ VPN للمتابعة.\nيتطلب تشغيل تطبيق السائق اتصالاً مباشراً وآمناً بالشبكة.'
                : 'Please disable your VPN to continue.\nThe Driver app requires a direct and secure network connection.')
            : (ar
                ? 'يجب تشغيل الموقع لاستقبال الطلبات وتحديث موقعك بشكل صحيح.'
                : 'Location must be enabled to receive orders and update your position correctly.');

    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xffF4F7FB),
        child: SafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 120),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xffDBEAFE)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x160F172A),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      vpn ? Icons.vpn_lock_rounded : Icons.location_off_rounded,
                      size: 52,
                      color: const Color(0xffDC2626),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    if (!vpn)
                      FilledButton.icon(
                        onPressed:
                            () => readiness.requestPermission(isArabic: ar),
                        icon: Icon(
                          permanent
                              ? Icons.settings_rounded
                              : Icons.my_location_rounded,
                        ),
                        label: Text(
                          permanent
                              ? (ar
                                  ? 'فتح إعدادات التطبيق'
                                  : 'Open app settings')
                              : (ar ? 'تشغيل الموقع' : 'Enable location'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Nav.to(const DriverLocationPage()),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(ar ? 'موقعي' : 'My Location'),
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed:
                                () => Nav.to(const SupportAssistencePage()),
                            icon: const Icon(Icons.support_agent_rounded),
                            label: Text(ar ? 'الدعم' : 'Support'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () => showLogoutSheet(context),
                            icon: const Icon(Icons.logout_rounded),
                            label: Text(ar ? 'تسجيل الخروج' : 'Logout'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
