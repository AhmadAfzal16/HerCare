import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified local storage service.
///
/// - Sensitive data (tokens, user ID) → flutter_secure_storage (encrypted keychain)
/// - Non-sensitive preferences (language, flags) → SharedPreferences
/// - Structured objects → JSON-encoded in SharedPreferences
///
/// On web, secure storage falls back to SharedPreferences (acceptable for dev).
class LocalStorageService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  // ─── Secure Storage (tokens, sensitive data) ──────────────────────────────
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> setSecureString(String key, String value) async {
    if (kIsWeb) {
      final prefs = await _prefs;
      await prefs.setString('_secure_$key', value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<String?> getSecureString(String key) async {
    if (kIsWeb) {
      final prefs = await _prefs;
      return prefs.getString('_secure_$key');
    }
    return _secureStorage.read(key: key);
  }

  Future<void> deleteSecureString(String key) async {
    if (kIsWeb) {
      final prefs = await _prefs;
      await prefs.remove('_secure_$key');
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  Future<void> clearSecureStorage() async {
    if (kIsWeb) {
      final prefs = await _prefs;
      final keys = prefs.getKeys().where((k) => k.startsWith('_secure_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
    } else {
      await _secureStorage.deleteAll();
    }
  }

  // ─── Preferences (language, flags) ───────────────────────────────────────

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(key, value);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await _prefs;
    return prefs.getBool(key);
  }

  Future<void> setInt(String key, int value) async {
    final prefs = await _prefs;
    await prefs.setInt(key, value);
  }

  Future<int?> getInt(String key) async {
    final prefs = await _prefs;
    return prefs.getInt(key);
  }

  // ─── JSON Object Storage ──────────────────────────────────────────────────

  Future<void> setObject(String key, Map<String, dynamic> value) async {
    final prefs = await _prefs;
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> getObject(String key) async {
    final prefs = await _prefs;
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Clear ────────────────────────────────────────────────────────────────

  /// Full logout — clears tokens and user preferences.
  /// Does NOT clear language preference.
  Future<void> clearUserSession() async {
    await clearSecureStorage();
    final prefs = await _prefs;
    final language = prefs.getString('app_language');
    await prefs.clear();
    // Restore language preference
    if (language != null) {
      await prefs.setString('app_language', language);
    }
  }
}
