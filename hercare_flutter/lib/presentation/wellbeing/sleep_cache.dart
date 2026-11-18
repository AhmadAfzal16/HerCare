import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/models/sleep_models.dart';

class CachedSleep {
  const CachedSleep(this.dashboard, this.savedAt);
  final SleepDashboard dashboard;
  final DateTime savedAt;
}

/// Own-account read cache only. No raw journals, app names, guardian records,
/// background uploads or offline save queue. Full logout clears these keys.
class SleepCache {
  SleepCache(
      {required this.apiOrigin,
      FlutterSecureStorage? storage,
      DateTime Function()? now})
      : _storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true),
                iOptions: IOSOptions(
                    accessibility:
                        KeychainAccessibility.first_unlock_this_device)),
        _now = now ?? DateTime.now;
  final String apiOrigin;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  bool get available => !kIsWeb;
  static const lifetime = Duration(days: 7);
  static const maxBytes = 64000;
  String _key(String owner) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(owner)) {
      throw const FormatException('Invalid sleep owner');
    }
    return 'm8_sleep_v1_$owner';
  }

  Future<CachedSleep?> read(String owner) async {
    if (!available) return null;
    final key = _key(owner);
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      if (utf8.encode(raw).length > maxBytes) {
        throw const FormatException('Oversized sleep cache');
      }
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(value['saved_at'] as String).toUtc();
      final age = _now().toUtc().difference(savedAt);
      if (value['owner'] != owner ||
          value['api_origin'] != apiOrigin ||
          value['version'] != 1 ||
          age.isNegative ||
          age > lifetime) {
        throw const FormatException('Expired or incompatible sleep cache');
      }
      return CachedSleep(
          SleepDashboard.fromJson(value['dashboard'] as Map<String, dynamic>),
          savedAt);
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }

  Future<void> save(String owner, SleepDashboard dashboard) async {
    if (!available) return;
    final value = jsonEncode({
      'version': 1,
      'owner': owner,
      'api_origin': apiOrigin,
      'saved_at': _now().toUtc().toIso8601String(),
      'dashboard': dashboard.toJson()
    });
    if (utf8.encode(value).length > maxBytes) {
      throw const FormatException('Oversized sleep cache');
    }
    await _storage.write(key: _key(owner), value: value);
  }

  Future<void> clear(String owner) async {
    if (available) await _storage.delete(key: _key(owner));
  }
}
