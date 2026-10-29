import 'package:blockatie/constants/app_urls.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Why a registration attempt ended the way it did.
///
/// These are the backend's own stable codes plus two the app owns. The page
/// turns them into wording; nothing here decides what a driver reads, which is
/// what let a previous version render `DB_PREPARE_ERROR` — "Database prepare
/// error." — straight onto the screen.
enum RegisterOutcome {
  /// The account was created and is waiting for an Admin to activate it.
  /// Registration is not a login: no session, no credential.
  success,

  requiredFields,
  nameTooLong,
  phoneTooLong,
  phoneTooShort,
  invalidPhonePrefix,
  weakPassword,
  passwordTooLong,
  tooManyAttempts,
  phoneExists,

  /// The server answered, but not in a shape this app can trust.
  invalidResponse,

  /// Anything else the server reports, plus transport failures.
  serverError,
  network,
}

/// The result of one registration attempt.
@immutable
class RegisterResult {
  const RegisterResult(this.outcome, {this.driverId});

  final RegisterOutcome outcome;

  /// Present on success only, and only informational — it is not a credential
  /// and authorizes nothing.
  final int? driverId;

  bool get isSuccess => outcome == RegisterOutcome.success;
}

/// Creates a pending driver account.
///
/// It owns the request and the form's text, nothing else. It shows no dialogs,
/// reads no global navigator context and makes no decision about language: an
/// earlier version did all three, so a validation dialog could appear after the
/// page had gone, on the root navigator, in whichever language a static flag
/// happened to hold.
class RegisterProvider extends UserScopedNotifier {
  RegisterProvider({Dio? httpClient}) : _dio = httpClient ?? Dio();

  /// The transport. Injectable so a test can drive the real [register] — and
  /// with it the busy flag and the parsing — instead of replacing the method
  /// and testing a stand-in.
  final Dio _dio;

  /// Registration is pre-auth, but the form must not carry across accounts.
  @override
  void clearUserState() {
    nameCont.clear();
    phoneCont.clear();
    passCont.clear();
    confirmPassCont.clear();
    _isChecked = false;
    _isLoading = false;
  }

  final TextEditingController nameCont = TextEditingController();
  final TextEditingController phoneCont = TextEditingController();
  final TextEditingController passCont = TextEditingController();

  /// Never sent anywhere. It exists only so the page can compare it with
  /// [passCont] before a password the driver mistyped becomes their password.
  final TextEditingController confirmPassCont = TextEditingController();

  bool _isChecked = false;
  bool _isLoading = false;

  bool get isChecked => _isChecked;
  bool get isLoading => _isLoading;

  void toggleCheckbox() {
    _isChecked = !_isChecked;
    notifyListeners();
  }

  /// Posts the registration and reports what happened.
  ///
  /// Takes no BuildContext: the caller decides what to show and whether it is
  /// still on screen to show it.
  Future<RegisterResult> register() async {
    if (_isLoading) {
      return const RegisterResult(RegisterOutcome.serverError);
    }
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _dio.post(
        AppUrls.driverregister,
        data: FormData.fromMap({
          'dname': nameCont.text.trim(),
          'dphone': phoneCont.text.trim(),
          'dpass': passCont.text,
        }),
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
          // The endpoint answers with a code on every path, so its own reply is
          // always more useful than a transport-level throw.
          validateStatus: (_) => true,
        ),
      );

      final data = response.data;
      if (data is! Map) {
        return const RegisterResult(RegisterOutcome.invalidResponse);
      }

      final code = data['code']?.toString().trim().toUpperCase() ?? '';
      final succeeded = data['success'] == true && code == 'REGISTER_SUCCESS';

      if (!succeeded) {
        return RegisterResult(_outcomeFor(code));
      }

      // Parsed defensively and never cast. The previous version read
      // `data['data']['api_key']` into a non-nullable String; the endpoint no
      // longer sends one, so that line would throw on every success.
      final payload = data['data'];
      final driverId =
          payload is Map ? int.tryParse('${payload['driver_id']}') : null;
      if (driverId == null || driverId < 1) {
        return const RegisterResult(RegisterOutcome.invalidResponse);
      }

      // Deliberately absent: no api_key is read, no session is saved and no FCM
      // topic is subscribed. Registration creates a pending account; the
      // authenticated shell and login own all three.
      return RegisterResult(RegisterOutcome.success, driverId: driverId);
    } on DioException catch (e) {
      debugPrint('Driver registration transport failed: ${e.type}');
      return const RegisterResult(RegisterOutcome.network);
    } catch (e) {
      debugPrint('Driver registration failed: ${e.runtimeType}');
      return const RegisterResult(RegisterOutcome.serverError);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Maps the endpoint's stable code onto an outcome.
  ///
  /// An unknown code — including every `DB_*` value — collapses to
  /// [RegisterOutcome.serverError], so a new internal failure can never reach
  /// the screen just because nobody taught the app about it yet.
  @visibleForTesting
  static RegisterOutcome outcomeForCode(String code) => _outcomeFor(code);

  static RegisterOutcome _outcomeFor(String code) {
    return switch (code) {
      'REQUIRED_FIELDS' => RegisterOutcome.requiredFields,
      'NAME_TOO_LONG' => RegisterOutcome.nameTooLong,
      'PHONE_TOO_LONG' => RegisterOutcome.phoneTooLong,
      'PHONE_TOO_SHORT' => RegisterOutcome.phoneTooShort,
      'INVALID_PHONE_PREFIX' => RegisterOutcome.invalidPhonePrefix,
      'WEAK_PASSWORD' => RegisterOutcome.weakPassword,
      'PASSWORD_TOO_LONG' => RegisterOutcome.passwordTooLong,
      'TOO_MANY_ATTEMPTS' => RegisterOutcome.tooManyAttempts,
      'PHONE_EXISTS' => RegisterOutcome.phoneExists,
      _ => RegisterOutcome.serverError,
    };
  }

  @override
  void dispose() {
    nameCont.dispose();
    phoneCont.dispose();
    passCont.dispose();
    confirmPassCont.dispose();
    super.dispose();
  }
}
