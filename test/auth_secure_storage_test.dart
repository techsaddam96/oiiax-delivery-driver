// Verifies that driver credentials live in secure storage, that an existing
// plaintext session migrates across once, and that logout leaves nothing behind.

import 'package:blockatie/services/auth_secure_store.dart';
import 'package:blockatie/services/auth_services.dart';
import 'package:blockatie/services/user_session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform keystore.
class _FakeSecureStore implements AuthSecureStore {
  _FakeSecureStore({
    this.failOnWrite = false,
    this.corruptOnWrite = false,
  });

  final Map<String, String> values = {};
  bool failOnWrite;
  bool corruptOnWrite;
  bool failOnDelete = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failOnWrite) throw StateError('keystore unavailable');
    values[key] = corruptOnWrite ? 'corrupted' : value;
  }

  @override
  Future<void> delete(String key) async {
    if (failOnDelete) throw StateError('keystore unavailable');
    values.remove(key);
  }
}

const _legacyApiKey = 'api_key';
const _legacyId = 'id';
const _legacyDriverId = 'driver_id';
const _legacyDriverIdCamel = 'driverId';
const _secureApiKey = 'driver_api_key';
const _secureDriverId = 'driver_session_id';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStore store;

  setUp(() {
    store = _FakeSecureStore();
    SharedPreferences.setMockInitialValues({});
    AuthService.configureForTesting(secureStore: store);
  });

  tearDown(AuthService.resetForTesting);

  group('migration from plaintext SharedPreferences', () {
    test('an existing logged-in driver migrates on first read', () async {
      SharedPreferences.setMockInitialValues({
        _legacyApiKey: 'legacy-key-abc',
        _legacyId: '900004',
        'dname': 'Demo Driver 4',
        'phone': '0799000004',
        'selected_language': 'Arabic',
      });
      AuthService.configureForTesting(secureStore: store);

      final session = await AuthService.getSessionSnapshot();

      expect(session.apiKey, 'legacy-key-abc');
      expect(session.driverId, '900004');
      expect(session.isAuthenticated, isTrue);

      // Value now lives in secure storage...
      expect(store.values[_secureApiKey], 'legacy-key-abc');
      expect(store.values[_secureDriverId], '900004');

      // ...and no longer in plaintext.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyApiKey), isNull);
      expect(prefs.getString(_legacyId), isNull);

      // Device preference is untouched.
      expect(prefs.getString('selected_language'), 'Arabic');
    });

    test('migration reads the driver id from any legacy alias', () async {
      SharedPreferences.setMockInitialValues({
        _legacyApiKey: 'legacy-key',
        _legacyDriverIdCamel: '900012',
      });
      AuthService.configureForTesting(secureStore: store);

      expect(await AuthService.getuserId(), '900012');
      expect(store.values[_secureDriverId], '900012');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyDriverIdCamel), isNull);
      expect(prefs.getString(_legacyDriverId), isNull);
    });

    test('name and phone migrate out of plaintext too', () async {
      SharedPreferences.setMockInitialValues({
        'dname': 'Demo Driver 4',
        'phone': '0799000004',
      });
      AuthService.configureForTesting(secureStore: store);

      expect(await AuthService.getDrivername(), 'Demo Driver 4');
      expect(await AuthService.getPhone(), '0799000004');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dname'), isNull);
      expect(prefs.getString('phone'), isNull);
    });

    test(
      'a second read is served from secure storage, not plaintext',
      () async {
        SharedPreferences.setMockInitialValues({
          _legacyApiKey: 'legacy-key',
          _legacyId: '900004',
        });
        AuthService.configureForTesting(secureStore: store);

        await AuthService.getSessionSnapshot();
        AuthService.configureForTesting(secureStore: store); // drop the cache

        final session = await AuthService.getSessionSnapshot();
        expect(session.apiKey, 'legacy-key');
        expect(session.driverId, '900004');
      },
    );

    test('a driver is not stranded when the keystore is unavailable', () async {
      SharedPreferences.setMockInitialValues({
        _legacyApiKey: 'legacy-key',
        _legacyId: '900004',
      });
      final failing = _FakeSecureStore(failOnWrite: true);
      AuthService.configureForTesting(secureStore: failing);

      final session = await AuthService.getSessionSnapshot();

      // Still authenticated from the legacy value; migration retries later.
      expect(session.apiKey, 'legacy-key');
      expect(session.isAuthenticated, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyApiKey), 'legacy-key');
    });

    test(
      'a corrupted write is rolled back and does not delete plaintext',
      () async {
        SharedPreferences.setMockInitialValues({
          _legacyApiKey: 'legacy-key',
          _legacyId: '900004',
        });
        final corrupting = _FakeSecureStore(corruptOnWrite: true);
        AuthService.configureForTesting(secureStore: corrupting);

        final session = await AuthService.getSessionSnapshot();

        expect(session.apiKey, 'legacy-key');
        expect(corrupting.values[_secureApiKey], isNull); // rolled back

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_legacyApiKey), 'legacy-key');
      },
    );

    test('no session anywhere resolves to unauthenticated', () async {
      final session = await AuthService.getSessionSnapshot();

      expect(session.apiKey, isNull);
      expect(session.driverId, isNull);
      expect(session.isAuthenticated, isFalse);
    });
  });

  group('fresh login', () {
    test('credentials are written to secure storage only', () async {
      await AuthService.saveDriverSession(
        apiKey: 'fresh-key-xyz',
        id: '900012',
        dname: 'Demo Driver 12',
        phone: '0799000012',
        latitude: '31.96',
        longitude: '35.46',
      );

      expect(store.values[_secureApiKey], 'fresh-key-xyz');
      expect(store.values[_secureDriverId], '900012');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyApiKey), isNull);
      expect(prefs.getString(_legacyId), isNull);
      expect(prefs.getString('dname'), isNull);
      expect(prefs.getString('phone'), isNull);
    });

    test('saveApiKey still works and stores securely', () async {
      await AuthService.saveApiKey('compat-key', '900004');

      expect(store.values[_secureApiKey], 'compat-key');
      expect(await AuthService.getApiKey(), 'compat-key');
      expect(await AuthService.getuserId(), '900004');
    });

    test('login wipes any plaintext left by an older build', () async {
      SharedPreferences.setMockInitialValues({
        _legacyApiKey: 'stale-plaintext',
        _legacyId: '900004',
        'is_logged_in': 'true',
      });
      AuthService.configureForTesting(secureStore: store);

      await AuthService.saveDriverSession(apiKey: 'new-key', id: '900012');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyApiKey), isNull);
      expect(prefs.getString('is_logged_in'), isNull);
      expect(await AuthService.getApiKey(), 'new-key');
    });

    test('restart restores the session from secure storage', () async {
      await AuthService.saveDriverSession(apiKey: 'persisted', id: '900004');

      // Simulate a cold start: same secure store, no in-memory cache.
      AuthService.configureForTesting(secureStore: store);

      final session = await AuthService.getSessionSnapshot();
      expect(session.apiKey, 'persisted');
      expect(session.driverId, '900004');
      expect(session.isAuthenticated, isTrue);
    });
  });

  group('logout', () {
    test(
      'removes every credential from secure and plaintext storage',
      () async {
        SharedPreferences.setMockInitialValues({'selected_language': 'Arabic'});
        AuthService.configureForTesting(secureStore: store);

        await AuthService.saveDriverSession(
          apiKey: 'key-a',
          id: '900004',
          dname: 'Demo Driver 4',
          phone: '0799000004',
        );

        await AuthService.clearSession();

        expect(store.values, isEmpty);

        final session = await AuthService.getSessionSnapshot();
        expect(session.apiKey, isNull);
        expect(session.driverId, isNull);
        expect(session.isAuthenticated, isFalse);

        // Device preference survives logout.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('selected_language'), 'Arabic');
      },
    );

    test('clearApiKey performs a full session clear', () async {
      await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');

      await AuthService.clearApiKey();

      expect(store.values, isEmpty);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
    });

    test('logout bumps the session generation', () async {
      await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');
      final before = UserSessionState.generation;

      await AuthService.clearSession();

      expect(UserSessionState.generation, greaterThan(before));
      expect(UserSessionState.isCurrent(before), isFalse);
    });

    test('a failed secure wipe remains terminal across a cold start', () async {
      await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');
      store.failOnDelete = true;

      final logout = await AuthService.clearSession();
      expect(logout.storageCleared, isFalse);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);

      // A process restart must not rehydrate the still-present credential.
      AuthService.configureForTesting(secureStore: store);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('driver_logout_pending'), isTrue);
    });
  });

  group('account switching', () {
    test('Driver B never sees Driver A credentials', () async {
      await AuthService.saveDriverSession(
        apiKey: 'driver-a-key',
        id: '900004',
        dname: 'Demo Driver 4',
        phone: '0799000004',
      );
      expect(await AuthService.getApiKey(), 'driver-a-key');

      await AuthService.clearSession();
      await AuthService.saveDriverSession(
        apiKey: 'driver-b-key',
        id: '900012',
        dname: 'Demo Driver 12',
        phone: '0799000012',
      );

      expect(await AuthService.getApiKey(), 'driver-b-key');
      expect(await AuthService.getuserId(), '900012');
      expect(await AuthService.getDrivername(), 'Demo Driver 12');
      expect(await AuthService.getPhone(), '0799000012');
      expect(store.values.values, isNot(contains('driver-a-key')));
    });

    test('switching accounts without an explicit logout still replaces all '
        'credentials', () async {
      await AuthService.saveDriverSession(
        apiKey: 'driver-a-key',
        id: '900004',
        dname: 'Demo Driver 4',
      );
      AuthService.resetAccountStateOnly(SessionResetReason.accountChanged);
      await AuthService.saveDriverSession(
        apiKey: 'driver-b-key',
        id: '900012',
        dname: 'Demo Driver 12',
      );

      expect(await AuthService.getApiKey(), 'driver-b-key');
      expect(await AuthService.getDrivername(), 'Demo Driver 12');
    });

    test('a 401 for the current session clears credentials', () async {
      await AuthService.saveDriverSession(apiKey: 'key-a', id: '900004');
      final generation = UserSessionState.generation;

      await AuthService.invalidateSessionIfCurrent(generation);

      expect(store.values, isEmpty);
      expect((await AuthService.getSessionSnapshot()).isAuthenticated, isFalse);
    });

    test('a 401 answering an older session is ignored', () async {
      await AuthService.saveDriverSession(apiKey: 'key-b', id: '900012');
      final staleGeneration = UserSessionState.generation - 1;

      await AuthService.invalidateSessionIfCurrent(staleGeneration);

      // The current driver stays signed in.
      expect(await AuthService.getApiKey(), 'key-b');
    });
  });

  group('no plaintext credential remains', () {
    test('every sensitive legacy key is gone after a migrated read', () async {
      SharedPreferences.setMockInitialValues({
        _legacyApiKey: 'k',
        _legacyId: '1',
        _legacyDriverId: '1',
        _legacyDriverIdCamel: '1',
        'dname': 'n',
        'phone': 'p',
        'latitude': '31.0',
        'longitude': '35.0',
        'selected_language': 'English',
      });
      AuthService.configureForTesting(secureStore: store);

      await AuthService.getSessionSnapshot();
      await AuthService.getDrivername();
      await AuthService.getPhone();
      await AuthService.getStoredLatitude();
      await AuthService.getStoredLongitude();

      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        _legacyApiKey,
        _legacyId,
        _legacyDriverId,
        _legacyDriverIdCamel,
        'dname',
        'phone',
        'latitude',
        'longitude',
      ]) {
        expect(prefs.getString(key), isNull, reason: '$key must not persist');
      }
      expect(prefs.getString('selected_language'), 'English');
    });
  });
}
