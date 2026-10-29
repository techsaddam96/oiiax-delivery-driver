import 'dart:async';

import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/constants/notification_system.dart';
import 'package:blockatie/models/login.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/password_policy.dart';
import 'package:blockatie/provider/notification.dart';
import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/provider/shipment_flow_config.dart';
import 'package:blockatie/views/pages/auth/login/forced_password_change.dart';
import 'package:blockatie/views/widgets/bottom_nav.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:provider/provider.dart';

class LoginProvider extends UserScopedNotifier {
  /// The login transport. Production builds get the default client below;
  /// tests pass one with a stub adapter so the response handling can be
  /// exercised without a server. The request itself is identical either way.
  LoginProvider({Dio Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? _defaultHttpClient;

  final Dio Function() _httpClientFactory;

  static Dio _defaultHttpClient() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ),
  );

  // Login form state is pre-auth, but must not leak between accounts.
  @override
  void clearUserState() {
    phoneCont.clear();
    passCont.clear();
    _isChecked = false;
    _isLoading = false;
    _errorMessage = null;
  }

  final TextEditingController phoneCont = TextEditingController(text: '');
  final TextEditingController passCont = TextEditingController(text: '');
  final MaskTextInputFormatter phoneMaskFormatter = MaskTextInputFormatter(
    mask: '####-###-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  bool _isChecked = false;
  bool _isLoading = false;
  String? _errorMessage;

  bool get isChecked => _isChecked;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void toggleCheckbox() {
    _isChecked = !_isChecked;
    notifyListeners();
  }

  void setCheckbox(bool value) {
    _isChecked = value;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> logIn() async {
    if (_isLoading) return false;

    final validationMessage = validateLoginFields();
    if (validationMessage != null) {
      _setError(validationMessage);
      return false;
    }

    _setLoading(true);

    try {
      final dio = _httpClientFactory();

      // api_driver_login.php already reads ?lang= (and falls back to
      // Accept-Language). Telling it which language we are in makes its
      // single `message` field match the UI; message_ar/message_en are still
      // preferred below, so this only improves the fallback.
      final languageCode = _isArabic ? 'ar' : 'en';
      final response = await dio.postUri(
        Uri.parse(
          AppUrls.driverlogin,
        ).replace(queryParameters: {'lang': languageCode}),
        options: Options(
          // No API key here: login is the call that issues the driver's key.
          // The endpoint authenticates by phone + password only.
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept-Language': languageCode,
          },
        ),
        data: {'phone': _normalizedPhone, 'password': passCont.text.trim()},
      );

      final body = response.data;
      if (response.statusCode != 200) {
        _safeLog('Login failed with status ${response.statusCode}');
        _setError(_messageFromResponse(body, fallback: _serverErrorMessage));
        return false;
      }

      if (body is! Map) {
        _safeLog('Login response was not a JSON object');
        _setError(_malformedResponseMessage);
        return false;
      }

      final data = Map<String, dynamic>.from(body);

      // An admin-issued temporary password opens nothing but the password
      // change: the server sends a single-purpose token and no api_key.
      final changeToken = data['password_change_token']?.toString() ?? '';
      if (data['code']?.toString() == passwordChangeRequiredCode &&
          changeToken.isNotEmpty) {
        passCont.clear();
        _setLoading(false);
        Nav.to(ForcedPasswordChangePage(changeToken: changeToken));
        return false;
      }

      if (!_isSuccess(data['success'])) {
        _setError(_messageFromResponse(data, fallback: _loginFailedMessage));
        return false;
      }

      final error = await _publishSession(data);
      if (error != null) {
        _setError(error);
        return false;
      }
      return true;
    } on DioException catch (e) {
      _safeLog('Login Dio error: ${e.response?.statusCode ?? e.type}');
      _setError(_messageFromDio(e));
      return false;
    } catch (e) {
      _safeLog('Login unexpected error: ${e.runtimeType}');
      _setError(_genericErrorMessage);
      return false;
    } finally {
      if (_isLoading) {
        _setLoading(false);
      }
    }
  }

  static const String passwordChangeRequiredCode = 'PASSWORD_CHANGE_REQUIRED';

  bool _isChangingPassword = false;
  bool get isChangingPassword => _isChangingPassword;

  /// The forced change after a temporary password. The new password is sent
  /// once and never kept; on success the response carries a full session.
  /// Returns null on success, otherwise the message to show.
  Future<String?> completeForcedPasswordChange({
    required String changeToken,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (_isChangingPassword) return null;
    final policy = PasswordPolicy.message(newPassword, isArabic: _isArabic);
    if (policy != null) return policy;
    if (newPassword != confirmPassword) {
      return _isArabic
          ? 'كلمتا المرور غير متطابقتين.'
          : 'Passwords do not match.';
    }

    _isChangingPassword = true;
    notifyListeners();
    try {
      final languageCode = _isArabic ? 'ar' : 'en';
      final response = await _httpClientFactory().postUri(
        Uri.parse(
          AppUrls.driverChangePassword,
        ).replace(queryParameters: {'lang': languageCode}),
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept-Language': languageCode,
          },
        ),
        data: {
          'password_change_token': changeToken,
          'new_password': newPassword,
          'confirm_password': confirmPassword,
          'lang': languageCode,
        },
      );
      final body = response.data;
      if (body is! Map) return _malformedResponseMessage;
      final data = Map<String, dynamic>.from(body);
      if (!_isSuccess(data['success'])) {
        return _messageFromResponse(data, fallback: _genericErrorMessage);
      }
      return await _publishSession(data);
    } on DioException catch (e) {
      _safeLog(
        'Password change Dio error: ${e.response?.statusCode ?? e.type}',
      );
      return _messageFromDio(e);
    } catch (e) {
      _safeLog('Password change unexpected error: ${e.runtimeType}');
      return _genericErrorMessage;
    } finally {
      _isChangingPassword = false;
      notifyListeners();
    }
  }

  /// Publishes a signed-in session from a login-shaped response and opens the
  /// app. Returns null on success, otherwise the message to show.
  Future<String?> _publishSession(Map<String, dynamic> data) async {
    {
      final rawDriver = data['data'];
      if (rawDriver is! Map) {
        _safeLog('Login success response is missing data object');
        return _malformedResponseMessage;
      }

      final loginResponse = LoginResponse.fromJson(data);
      final driver = loginResponse.driver;
      final apiKey = driver.apiKey.trim();
      final driverId = driver.id.toString();

      if (apiKey.isEmpty || driver.id <= 0) {
        _safeLog('Login success response is missing session fields');
        return _malformedResponseMessage;
      }

      // Authentication has succeeded, so it is now safe to drop whatever the
      // previous driver left behind. Doing this before the new credentials are
      // published guarantees no stale account data is on screen for Driver B,
      // and a failed login above never touches an active session.
      AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);

      // Resolve app-wide providers before the first await in this method. They
      // remain the same root instances after the session boundary and avoid
      // using the navigation BuildContext across the refresh sequence.
      final profileProvider = Provider.of<ProfileProvider>(
        Nav.context,
        listen: false,
      );
      final shipmentFlowConfig = Provider.of<ShipmentFlowConfigProvider>(
        Nav.context,
        listen: false,
      );
      final notificationProvider = Provider.of<NotificationProvider>(
        Nav.context,
        listen: false,
      );

      await AuthService.saveDriverSession(
        apiKey: apiKey,
        id: driverId,
        dname: driver.dname,
        phone: driver.dphone.isNotEmpty ? driver.dphone : _normalizedPhone,
        latitude: driver.latitude,
        longitude: driver.longitude,
      );

      // The login response is a safe fallback, but the profile endpoint is the
      // authoritative source for the display name used on Home. Its identity
      // is server-bound to this key; a timeout or transient failure preserves
      // the freshly authenticated fallback and never revives a prior account.
      try {
        await profileProvider
            .refreshAuthoritativeIdentity()
            .timeout(const Duration(seconds: 8));
      } on TimeoutException {
        _safeLog('Authoritative profile refresh timed out after login');
      } catch (e) {
        _safeLog('Authoritative profile refresh skipped: ${e.runtimeType}');
      }

      // Load the signed, server-resolved shipment visibility before opening the
      // authenticated shell. A transport failure remains explicitly unknown;
      // ShipmentFlowConfigProvider never treats it as an Admin-OFF decision.
      try {
        await shipmentFlowConfig.restoreCachedScheduledPolicy(driverId);
        await shipmentFlowConfig.fetch(
          force: true,
        ).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        _safeLog('Shipment visibility refresh timed out after login');
      } catch (e) {
        _safeLog('Shipment visibility refresh skipped: ${e.runtimeType}');
      }

      // A 401/disabled response while refreshing ends the current session via
      // sessionDio. Do not open the authenticated shell after that teardown.
      final currentSession = await AuthService.getSessionSnapshot();
      if (currentSession.apiKey != apiKey ||
          currentSession.driverId != driverId) {
        _safeLog('Authenticated session changed during profile refresh');
        return _serverErrorMessage;
      }

      // Fire and forget, and deliberately swallowing: the session is already
      // saved above, so a push-registration failure must never turn a
      // successful login into a failed one, nor surface as an unhandled error.
      unawaited(
        NotificationSystem().registerDriverFcmTokenAfterLogin().catchError((
          Object e,
        ) {
          _safeLog(
            'FCM token registration after login failed: ${e.runtimeType}',
          );
        }),
      );
      try {
        unawaited(notificationProvider.refreshUnreadCount(force: true));
      } catch (e) {
        _safeLog('Unread notification refresh skipped: ${e.runtimeType}');
      }

      _safeLog('Login successful');
      phoneCont.clear();
      passCont.clear();
      _setLoading(false, notify: false);
      Nav.offAll(withNav: true, navIndex: 0, CustomBottomNavBar());
      return null;
    }
  }

  /// What api_driver_login.php accepts: a local Jordan mobile number, exactly
  /// ten digits beginning 077, 078 or 079. Kept here so the form and this
  /// provider cannot drift apart — previously the form allowed seven digits
  /// and the server rejected them after a round trip.
  static const int jordanPhoneLength = 10;
  static const List<String> jordanPhonePrefixes = ['077', '078', '079'];

  /// The single phone rule, shared with the form field. Returns null when the
  /// number is acceptable.
  static String? phoneValidationMessage(
    String? value, {
    required bool isArabic,
  }) {
    final phone = normalizePhone(value ?? '');
    if (phone.isEmpty) {
      return isArabic ? 'رقم الهاتف مطلوب' : 'Phone number is required';
    }
    if (phone.length != jordanPhoneLength ||
        !jordanPhonePrefixes.any(phone.startsWith)) {
      return isArabic
          ? 'أدخل رقم هاتف صحيح من 10 أرقام يبدأ بـ 077 أو 078 أو 079.'
          : 'Enter a valid 10-digit phone number starting with 077, 078, '
              'or 079.';
    }
    return null;
  }

  /// The single password rule, shared with the form field.
  static String? passwordValidationMessage(
    String? value, {
    required bool isArabic,
  }) {
    if ((value ?? '').trim().isEmpty) {
      return isArabic ? 'كلمة المرور مطلوبة' : 'Password is required';
    }
    return null;
  }

  /// Digits only. The field already rejects everything else; this also strips
  /// anything a paste or an autofill service may have inserted.
  static String normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  String? validateLoginFields() {
    return phoneValidationMessage(phoneCont.text, isArabic: _isArabic) ??
        passwordValidationMessage(passCont.text, isArabic: _isArabic);
  }

  bool validator() => validateLoginFields() == null;

  String get _normalizedPhone => normalizePhone(phoneCont.text);

  void _setLoading(bool value, {bool notify = true}) {
    _isLoading = value;
    if (value) _errorMessage = null;
    if (notify) notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _isLoading = false;
    notifyListeners();
  }

  bool _isSuccess(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().toLowerCase().trim();
    return normalized == 'true' || normalized == '1' || normalized == 'success';
  }

  String _messageFromDio(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return _networkErrorMessage;
    }
    return _messageFromResponse(
      error.response?.data,
      fallback: _serverErrorMessage,
    );
  }

  String _messageFromResponse(dynamic response, {required String fallback}) {
    if (response is Map) {
      final data = Map<dynamic, dynamic>.from(response);

      // Infrastructure failures arrive with a server-worded message. The
      // driver must never see database wording, a query, a path or a trace,
      // so these codes are answered with the neutral service message. The
      // license and feature guards that run before the endpoint word theirs
      // in English only.
      final code = data['code']?.toString().trim().toUpperCase();
      if (code == 'DB_PREPARE_ERROR' || code == 'DB_QUERY_ERROR') {
        _safeLog('Login blocked by a server-side database error');
        return _serverErrorMessage;
      }
      if (code == 'LICENSE_RESTRICTED' || code == 'FEATURE_UNAVAILABLE') {
        _safeLog('Login blocked by the installation guard: $code');
        return _serverErrorMessage;
      }

      // Only the wording in the driver's own language. Both login endpoints
      // always send message_ar and message_en; a reply with neither came from
      // something else, whose `message` may be in either language.
      final message = _isArabic ? data['message_ar'] : data['message_en'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString().trim();
      }
    }
    return fallback;
  }

  /// Reads the one authoritative language state. LocaleProvider pushes every
  /// switch into AppLocalizations before it notifies, so this can never
  /// disagree with the text and direction the driver is looking at.
  bool get _isArabic => AppLocalizations.isArabic;

  String get _loginFailedMessage =>
      _isArabic ? 'فشل تسجيل الدخول' : 'Login failed';

  String get _networkErrorMessage =>
      _isArabic
          ? 'تعذر الاتصال. يرجى المحاولة مرة أخرى.'
          : 'Unable to connect. Please try again.';

  String get _serverErrorMessage =>
      _isArabic
          ? 'الخدمة غير متاحة حاليًا. يرجى المحاولة لاحقًا.'
          : 'Service is unavailable. Please try again later.';

  String get _malformedResponseMessage =>
      _isArabic
          ? 'تعذر قراءة استجابة تسجيل الدخول. يرجى المحاولة مرة أخرى.'
          : 'Unable to read the login response. Please try again.';

  String get _genericErrorMessage =>
      _isArabic
          ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.'
          : 'Something went wrong. Please try again.';

  void _safeLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  @override
  void dispose() {
    phoneCont.dispose();
    passCont.dispose();
    super.dispose();
  }
}
