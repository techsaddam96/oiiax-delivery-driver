// Password Security V2 in the Driver App: the shared password policy, the
// forced change after an admin-issued temporary password, the session ending on
// a rotated key, and the removal of the fake OTP screen.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blockatie/provider/login.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/session_dio.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:blockatie/utils/localization.dart';
import 'package:blockatie/utils/nav.dart';
import 'package:blockatie/utils/password_policy.dart';
import 'package:blockatie/views/pages/auth/login/forced_password_change.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStore implements AuthSecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LoginProvider _provider(_Adapter adapter) => LoginProvider(
      httpClientFactory: () {
        final dio = Dio(BaseOptions(validateStatus: (_) => true));
        dio.httpClientAdapter = adapter;
        return dio;
      },
    );

const _changeToken =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;

  setUp(() async {
    store = _FakeSecureStore();
    SharedPreferences.setMockInitialValues({'selected_language': 'en'});
    await AppLocalizations.initialize();
    AuthService.configureForTesting(secureStore: store);
  });

  tearDown(AuthService.resetForTesting);

  group('shared password policy (matches the server)', () {
    test('accepts 10+ characters with upper, lower and digit', () {
      expect(PasswordPolicy.message('Abcdefgh12', isArabic: false), isNull);
      expect(PasswordPolicy.message("Pa'ss\"wo\\rd1", isArabic: false), isNull);
    });

    test('refuses short, over 72 bytes, missing classes and edge spaces', () {
      for (final weak in [
        'Abc12',
        'Aa1${'a' * 70}',
        'abcdefgh12',
        'ABCDEFGH12',
        'Abcdefghij',
        ' Abcdefg12',
        'Abcdefg12 ',
      ]) {
        expect(
          PasswordPolicy.message(weak, isArabic: false),
          isNotNull,
          reason: weak,
        );
      }
    });

    test('Arabic message is provided', () {
      expect(PasswordPolicy.message('x', isArabic: true), contains('10'));
    });
  });

  group('a rotated key ends the session', () {
    Future<bool> endsSession(int status, Map<String, dynamic> body) async {
      store.values['driver_api_key'] = 'old-key';
      store.values['driver_session_id'] = '901';
      final before = UserSessionState.generation;
      final dio = sessionDio(
        BaseOptions(
          baseUrl: 'https://example.invalid',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = _Adapter(status, body);
      try {
        await dio.get<dynamic>('/x');
      } catch (_) {
        // A response that ended the session is rejected as stale.
      }
      return UserSessionState.generation != before;
    }

    test('403 INVALID_API_KEY signs out and clears stored credentials', () async {
      expect(
        await endsSession(403, {'success': false, 'code': 'INVALID_API_KEY'}),
        isTrue,
      );
      expect(store.values['driver_api_key'], isNull);
    });

    test('401 signs out', () async {
      expect(await endsSession(401, {'success': false}), isTrue);
    });

    test('an ordinary 403 does not sign out', () async {
      expect(
        await endsSession(403, {'success': false, 'code': 'NOT_AUTHORIZED'}),
        isFalse,
      );
    });

    test('the key rotated by a settings change replaces the old one', () async {
      store.values['driver_api_key'] = 'old-key';
      store.values['driver_session_id'] = '901';
      await AuthService.replaceApiKey(
        'rotated-key',
        expectedGeneration: UserSessionState.generation,
      );
      expect(store.values['driver_api_key'], 'rotated-key');
      expect(store.values['driver_session_id'], '901');
    });

    test('a rotated key arriving after sign-out is not stored', () async {
      store.values['driver_api_key'] = 'old-key';
      store.values['driver_session_id'] = '901';
      final generation = UserSessionState.generation;
      await AuthService.clearSession();
      await expectLater(
        AuthService.replaceApiKey('rotated-key', expectedGeneration: generation),
        throwsA(isA<SessionChanged>()),
      );
      expect(store.values['driver_api_key'], isNull);
    });
  });

  group('forced password change', () {
    testWidgets('a temporary password opens only the change screen; no key is stored', (
      tester,
    ) async {
      final adapter = _Adapter(200, {
        'success': false,
        'code': 'PASSWORD_CHANGE_REQUIRED',
        'message_en': 'You must set a new password before continuing.',
        'password_change_token': _changeToken,
      });
      final provider = _provider(adapter);
      await tester.pumpWidget(
        ChangeNotifierProvider<LoginProvider>.value(
          value: provider,
          child: MaterialApp(navigatorKey: Nav.key, home: const SizedBox()),
        ),
      );
      provider.phoneCont.text = '0781000901';
      provider.passCont.text = 'TempPass12xy';

      final signedIn = await tester.runAsync(provider.logIn);
      await tester.pumpAndSettle();

      expect(signedIn, isFalse);
      expect(find.byType(ForcedPasswordChangePage), findsOneWidget);
      expect(store.values['driver_api_key'], isNull);
      expect(provider.passCont.text, isEmpty, reason: 'the temporary password is not kept');

      // A weak new password is refused on the device, without a request.
      final requestsBefore = adapter.seen.length;
      await tester.enterText(find.byKey(const Key('forcedNewPassword')), 'weak');
      await tester.enterText(find.byKey(const Key('forcedConfirmPassword')), 'weak');
      await tester.tap(find.byKey(const Key('forcedSubmit')));
      await tester.pumpAndSettle();
      expect(find.text(PasswordPolicy.rules(isArabic: false)), findsWidgets);
      expect(adapter.seen.length, requestsBefore);
    });

    test('the change sends the token once and stores the fresh key from the server', () async {
      final adapter = _Adapter(200, {
        'success': true,
        'code': 'PASSWORD_CHANGED',
        'data': {'id': 901, 'api_key': 'fresh-key-from-server', 'dname': 'D901', 'dphone': '0781000901'},
      });
      final provider = _provider(adapter);

      // Navigation needs the full app; the session is published before it.
      await provider.completeForcedPasswordChange(
        changeToken: _changeToken,
        newPassword: 'NewDriver12x',
        confirmPassword: 'NewDriver12x',
      );

      expect(adapter.seen.single.data['password_change_token'], _changeToken);
      expect(store.values['driver_api_key'], 'fresh-key-from-server');
      expect(
        store.values.values.any((v) => v.contains(_changeToken) || v.contains('NewDriver12x')),
        isFalse,
        reason: 'neither the token nor the password is persisted',
      );
    });

    test('policy and mismatch are refused before any request', () async {
      final adapter = _Adapter(200, {'success': true});
      final provider = _provider(adapter);
      expect(
        await provider.completeForcedPasswordChange(
          changeToken: _changeToken,
          newPassword: 'short',
          confirmPassword: 'short',
        ),
        isNotNull,
      );
      expect(
        await provider.completeForcedPasswordChange(
          changeToken: _changeToken,
          newPassword: 'NewDriver12x',
          confirmPassword: 'NewDriver12y',
        ),
        isNotNull,
      );
      expect(adapter.seen, isEmpty);
    });
  });

  test('the fake OTP screen is gone and nothing refers to it', () {
    expect(
      File('lib/views/pages/auth/verifyOtp/verify_otp.dart').existsSync(),
      isFalse,
    );
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('VerifyOtpPage'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
