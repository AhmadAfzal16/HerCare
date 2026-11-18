import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/crisis_models.dart';

class CachedCrisisPlan {
  const CachedCrisisPlan({required this.plan, required this.savedAt});
  final CrisisPlan plan;
  final DateTime savedAt;
}

/// Explicit opt-in, bounded, account-scoped, native encrypted download.
/// No web/localStorage fallback, guardian records, event history or alert queue.
/// The existing full logout deletes all FlutterSecureStorage keys.
class CrisisPlanCache {
  CrisisPlanCache({FlutterSecureStorage? storage, DateTime Function()? now})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                  accessibility:
                      KeychainAccessibility.first_unlock_this_device),
            ),
        _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  static const duration = Duration(days: 30);
  static const sourceVersion = 'm10-safety-plan-v1';
  bool get available => !kIsWeb;

  String _key(String accountId) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(accountId)) {
      throw const FormatException('Invalid cache owner');
    }
    return 'm10_private_plan_v1_$accountId';
  }

  Future<CachedCrisisPlan?> read(String accountId) async {
    if (!available) return null;
    final key = _key(accountId);
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      if (raw.length > 6000) throw const FormatException('Cache too large');
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['account_id'] != accountId ||
          value['source_version'] != sourceVersion) {
        throw const FormatException('Cache owner/version mismatch');
      }
      final savedAt = DateTime.parse(value['saved_at'] as String).toUtc();
      final age = _now().toUtc().difference(savedAt);
      if (age.isNegative || age > duration) {
        throw const FormatException('Expired plan download');
      }
      return CachedCrisisPlan(
          plan: CrisisPlan.fromJson(value['plan'] as Map<String, dynamic>),
          savedAt: savedAt);
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }

  Future<void> save(String accountId, CrisisPlan plan) async {
    if (!available) throw UnsupportedError('Native encrypted storage required');
    final raw = jsonEncode({
      'account_id': accountId,
      'source_version': sourceVersion,
      'saved_at': _now().toUtc().toIso8601String(),
      'plan': plan.toJson(),
    });
    if (raw.length > 6000) throw const FormatException('Plan too large');
    await _storage.write(key: _key(accountId), value: raw);
  }

  Future<void> clear(String accountId) async {
    if (available) await _storage.delete(key: _key(accountId));
  }
}
