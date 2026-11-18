import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/content_models.dart';

class CachedContent {
  const CachedContent(
      this.items, this.preferences, this.revision, this.savedAt);
  final List<ContentItem> items;
  final ContentPreferences preferences;
  final String revision;
  final DateTime savedAt;
}

/// Short-lived, encrypted native-device copies of explicitly saved text only.
/// Nothing is stored in browser localStorage. No audio/video is downloaded.
class ContentCache {
  ContentCache({FlutterSecureStorage? storage, DateTime Function()? now})
      : _storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true),
                iOptions: IOSOptions(
                    accessibility:
                        KeychainAccessibility.first_unlock_this_device)),
        _now = now ?? DateTime.now;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  static const lifetime = Duration(hours: 24);
  static const maxBytes = 160000;
  bool get available => !kIsWeb;
  bool _availableNow(ContentItem item) {
    final now = _now().toUtc();
    return (item.reviewAfter == null || now.isBefore(item.reviewAfter!)) &&
        (item.availableUntil == null || now.isBefore(item.availableUntil!)) &&
        (item.availableFrom == null || !now.isBefore(item.availableFrom!));
  }

  String _key(String owner, String origin) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(owner)) {
      throw const FormatException('Invalid content owner');
    }
    return 'm11_text_v1_${base64Url.encode(utf8.encode('$origin|$owner'))}';
  }

  Future<CachedContent?> read(String owner, String origin) async {
    if (!available) return null;
    final key = _key(owner, origin);
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      if (utf8.encode(raw).length > maxBytes) {
        throw const FormatException('Too large');
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(json['saved_at'] as String).toUtc();
      final age = _now().toUtc().difference(savedAt);
      if (json['owner'] != owner ||
          json['origin'] != origin ||
          json['version'] != 1 ||
          age.isNegative ||
          age > lifetime) {
        throw const FormatException('Expired');
      }
      final values = json['items'] as List;
      if (values.length > 20) throw const FormatException('Too many items');
      final preferences = ContentPreferences.fromJson(
          Map<String, dynamic>.from(json['preferences'] as Map));
      final items = values
          .map((value) =>
              ContentItem.fromJson(Map<String, dynamic>.from(value as Map)))
          .where((item) =>
              item.saved &&
              item.canSaveOffline &&
              preferences.allows(item) &&
              _availableNow(item))
          .toList();
      return CachedContent(
          items, preferences, json['revision'] as String, savedAt);
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }

  Future<void> save(String owner, String origin, List<ContentItem> items,
      ContentPreferences preferences, String revision) async {
    if (!available) return;
    final safeItems = <Map<String, dynamic>>[];
    for (final item in items
        .where((item) =>
            item.saved &&
            item.canSaveOffline &&
            preferences.allows(item) &&
            _availableNow(item))
        .take(20)) {
      final next = item.toOfflineJson();
      if (utf8.encode(jsonEncode([...safeItems, next])).length <
          maxBytes - 5000) {
        safeItems.add(next);
      }
    }
    await _storage.write(
        key: _key(owner, origin),
        value: jsonEncode({
          'version': 1,
          'owner': owner,
          'origin': origin,
          'saved_at': _now().toUtc().toIso8601String(),
          'preferences': preferences.toJson(),
          'revision': revision,
          'items': safeItems,
        }));
  }

  Future<void> clear(String owner, String origin) async {
    if (available) await _storage.delete(key: _key(owner, origin));
  }
}
