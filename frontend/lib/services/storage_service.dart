import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around secure, encrypted device storage (Android
/// Keystore / iOS Keychain) so the rest of the app never touches the
/// plugin directly.
///
/// Security audit fix (High: "Session Security" / "Sensitive Data
/// Exposure"): this previously used plain SharedPreferences, which on
/// Android is just an unencrypted XML file in app-private storage -
/// readable on a rooted device, via an ADB backup, or by any tool with
/// root/debug access. The auth token (and everything else stored here)
/// now lives in encrypted, OS-backed secure storage instead.
class StorageService {
  static const _storage = FlutterSecureStorage();

  Future<void> setString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> getString(String key) async {
    return _storage.read(key: key);
  }

  Future<void> setInt(String key, int value) async {
    await _storage.write(key: key, value: value.toString());
  }

  Future<int?> getInt(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) return null;
    return int.tryParse(value);
  }

  Future<void> remove(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
