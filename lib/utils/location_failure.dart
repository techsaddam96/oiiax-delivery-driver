import 'localization.dart';

/// Why a location lookup did not produce a position.
///
/// The reason is a value rather than a sentence. The old code decided whether
/// to offer a Settings button with `message.contains('settings')` — a test
/// against English prose, which meant the button would silently disappear the
/// moment the message was translated.
enum LocationFailure {
  /// Location services are switched off on the device.
  serviceDisabled,

  /// The driver declined the permission prompt this time.
  permissionDenied,

  /// The driver declined permanently; the prompt will not appear again and
  /// only the system settings screen can undo it.
  permissionPermanentlyDenied,

  /// A timeout, a platform error, or anything else. Deliberately the catch-all
  /// so an unexpected failure still produces app-owned wording.
  unavailable,
}

/// What a lookup produced: an address, or a reason there is none.
class LocationLookup {
  const LocationLookup.success(String this.address) : failure = null;

  const LocationLookup.failed(LocationFailure this.failure) : address = null;

  final String? address;
  final LocationFailure? failure;

  bool get isSuccess => failure == null;
}

/// Whether this failure is one the driver can fix from the system settings.
///
/// Derived from the failure type, never from the text of a message.
bool locationFailureOffersSettings(LocationFailure failure) {
  return failure == LocationFailure.serviceDisabled ||
      failure == LocationFailure.permissionPermanentlyDenied;
}

/// App-owned wording for a failure.
///
/// Reads [AppLocalizations] rather than a BuildContext because the caller is a
/// service with no place in the widget tree — the same reason the offline
/// screen reads it.
String locationFailureMessage(LocationFailure failure, {bool? isArabic}) {
  final arabic = isArabic ?? AppLocalizations.isArabic;

  switch (failure) {
    case LocationFailure.serviceDisabled:
      return arabic
          ? 'خدمة الموقع غير مفعلة على جهازك.'
          : 'Location services are turned off on your device.';
    case LocationFailure.permissionDenied:
      return arabic
          ? 'نحتاج إذن الموقع لمتابعة العمل.'
          : 'Location permission is needed to continue.';
    case LocationFailure.permissionPermanentlyDenied:
      return arabic
          ? 'إذن الموقع مرفوض نهائياً. فعّله من إعدادات التطبيق.'
          : 'Location permission is permanently denied. Enable it in app settings.';
    case LocationFailure.unavailable:
      return arabic ? 'تعذر تحديد موقعك.' : 'Unable to get your location.';
  }
}

/// Label for the action that opens the system settings screen.
String openSettingsActionLabel({bool? isArabic}) {
  final arabic = isArabic ?? AppLocalizations.isArabic;
  return arabic ? 'فتح الإعدادات' : 'Open Settings';
}
