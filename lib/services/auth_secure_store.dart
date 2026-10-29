import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage seam for driver credentials.
///
/// Kept as an interface so tests can substitute an in-memory store without a
/// platform channel, and so the backing implementation can change without
/// touching AuthService.
abstract interface class AuthSecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterAuthSecureStore implements AuthSecureStore {
  const FlutterAuthSecureStore({
    this.storage = const FlutterSecureStorage(
      // Android keeps credentials in EncryptedSharedPreferences rather than the
      // plaintext store; iOS uses the Keychain by default.
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  });

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}
