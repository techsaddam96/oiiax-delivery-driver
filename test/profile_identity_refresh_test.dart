import 'dart:convert';
import 'dart:typed_data';

import 'package:blockatie/provider/profile.dart';
import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureStore implements AuthSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _ProfileAdapter implements HttpClientAdapter {
  _ProfileAdapter(this.body);

  final Object? body;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (body == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioFor(_ProfileAdapter adapter) =>
    Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = adapter
      ..transformer = SyncTransformer();

Map<String, Object> _profile(String name) => <String, Object>{
  'status': 'success',
  'profile': <String, Object>{
    'id': 42,
    'dname': name,
    'dpercent': 0,
    'dphone': '0790000042',
    'img': '',
    'numcd': '',
    'latitude': '',
    'longitude': '',
    'subscription': 1,
    'status': 0,
    'created_at': '2026-10-27 00:00:00',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemorySecureStore store;

  setUp(() async {
    store = _MemorySecureStore();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.configureForTesting(secureStore: store);
    await AuthService.saveDriverSession(
      apiKey: 'driver-key-a',
      id: '42',
      dname: 'Cached login name',
    );
  });

  tearDown(AuthService.resetForTesting);

  test(
    'authoritative profile refresh replaces the login-name fallback',
    () async {
      final adapter = _ProfileAdapter(_profile('Current profile name'));
      final provider = ProfileProvider(
        httpClient: _dioFor(adapter),
        loadProfile: false,
      );
      addTearDown(provider.dispose);

      final result = await provider.refreshAuthoritativeIdentity();

      expect(result?.dname, 'Current profile name');
      expect(provider.profileInfo?.dname, 'Current profile name');
      expect(await AuthService.getDrivername(), 'Current profile name');
      expect(adapter.request?.headers['X-API-KEY'], 'driver-key-a');
      expect(adapter.request?.data, <String, String>{'driverId': '42'});
    },
  );

  test(
    'a failed profile refresh retains the same-session login fallback',
    () async {
      final provider = ProfileProvider(
        httpClient: _dioFor(_ProfileAdapter(null)),
        loadProfile: false,
      );
      addTearDown(provider.dispose);

      expect(await provider.refreshAuthoritativeIdentity(), isNull);
      expect(provider.hasProfileError, isTrue);
      expect(await AuthService.getDrivername(), 'Cached login name');
    },
  );

  test(
    'a prior session cannot overwrite a newly signed-in driver name',
    () async {
      final generationA = UserSessionState.generation;
      AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);
      await AuthService.saveDriverSession(
        apiKey: 'driver-key-b',
        id: '43',
        dname: 'Driver B',
      );

      final saved = await AuthService.saveProfileNameIfCurrent(
        dname: 'Late Driver A profile',
        expectedGeneration: generationA,
        apiKey: 'driver-key-a',
        driverId: '42',
      );

      expect(saved, isFalse);
      expect(await AuthService.getDrivername(), 'Driver B');
    },
  );
}
