import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../data/models/care_directory.dart';

/// The release catalog cannot add its own trusted web domains.
const careInstitutionHosts = <String>{
  'pimh.punjab.gov.pk',
  'pims.gov.pk',
  'www.pims.gov.pk',
  'www.jpmc.edu.pk',
  'hospitals.aku.edu',
  'www.aku.edu',
  'kth.edu.pk',
  'www.mayohospital.gop.pk',
  'www.lrh.edu.pk',
  'bipbs.gob.pk',
};

class CareDirectorySnapshot {
  const CareDirectorySnapshot(this.directory,
      {this.downloaded = false, this.savedAt});
  final CareDirectory directory;
  final bool downloaded;
  final DateTime? savedAt;
}

/// Public catalog only. No session token, GPS, city choice or clinical fields
/// enter this client or its bounded public cache.
class CareDirectoryService {
  CareDirectoryService({
    Dio? client,
    Set<String>? approvedHosts,
    Future<String> Function()? loadAsset,
    DateTime Function()? now,
  })  : _client = client,
        _hosts = approvedHosts ?? careInstitutionHosts,
        _loadAsset = loadAsset ??
            (() => rootBundle.loadString('assets/care_facilities.json')),
        _now = now ?? DateTime.now;

  Dio? _client;
  final Set<String> _hosts;
  final Future<String> Function() _loadAsset;
  final DateTime Function() _now;
  static const maxBytes = 128 * 1024;
  static const cacheLifetime = Duration(days: 7);
  static const refreshAfter = Duration(hours: 6);
  Future<CareDirectorySnapshot>? _refreshInFlight;

  String get _cacheKey {
    final encoded = base64Url.encode(utf8.encode(_dio.options.baseUrl));
    return 'm10_public_care_v1_$encoded';
  }

  Dio get _dio => _client ??= _publicClient();

  static Dio _publicClient() {
    var baseUrl = AppConstants.apiBaseUrl;
    if (baseUrl.isEmpty) {
      try {
        baseUrl = dotenv.maybeGet('API_BASE_URL') ?? '';
      } catch (_) {}
    }
    if (baseUrl.isEmpty && !kReleaseMode) {
      baseUrl = 'http://localhost:5000/api/v1';
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['https', 'http'].contains(uri.scheme) ||
        (kReleaseMode && uri.scheme != 'https')) {
      throw StateError('Public care API requires a configured HTTPS origin.');
    }
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      followRedirects: false,
      responseType: ResponseType.stream,
      headers: {'Accept': 'application/json', 'Bypass-Tunnel-Reminder': 'true'},
    ));
  }

  CareDirectory _parse(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Public catalog exceeds size limit');
    }
    final body = jsonDecode(raw);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid public catalog');
    }
    return CareDirectory.fromJson(body, approvedHosts: _hosts);
  }

  Future<CareDirectorySnapshot?> _readCache() async {
    SharedPreferences? cachePrefs;
    String? cacheKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _cacheKey;
      cachePrefs = prefs;
      cacheKey = key;
      final raw = prefs.getString(key);
      if (raw == null) return null;
      if (utf8.encode(raw).length > maxBytes * 2 + 256) {
        await prefs.remove(key);
        return null;
      }
      final value = jsonDecode(raw);
      final savedAt = value is Map && value['saved_at'] is String
          ? DateTime.tryParse(value['saved_at'])
          : null;
      final age = savedAt == null ? null : _now().difference(savedAt);
      if (value is! Map ||
          value.length != 2 ||
          value.keys.any((key) => key != 'saved_at' && key != 'catalog') ||
          value['catalog'] is! String ||
          age == null ||
          age.isNegative ||
          age > cacheLifetime) {
        await prefs.remove(key);
        return null;
      }
      return CareDirectorySnapshot(_parse(value['catalog']),
          downloaded: true, savedAt: savedAt);
    } catch (_) {
      if (cachePrefs != null && cacheKey != null) {
        try {
          await cachePrefs.remove(cacheKey);
        } catch (_) {
          // Storage failure must not disable the packaged public directory.
        }
      }
      // A missing API origin/cache/plugin never disables the packaged catalog.
      return null;
    }
  }

  Future<CareDirectorySnapshot> offline() async {
    final cached = await _readCache();
    if (cached != null) return cached;
    return CareDirectorySnapshot(_parse(await _loadAsset()));
  }

  Future<CareDirectorySnapshot> refresh() => _refreshInFlight ??=
      _refresh().whenComplete(() => _refreshInFlight = null);

  Future<CareDirectorySnapshot> _refresh() async {
    final cached = await _readCache();
    if (cached?.savedAt != null &&
        _now().difference(cached!.savedAt!) < refreshAfter) {
      return cached;
    }
    final response = await _dio.get<dynamic>('/crisis/facilities');
    final responseBody = await _boundedResponse(response.data);
    final value = jsonDecode(utf8.decode(responseBody));
    if (value is! Map<String, dynamic> ||
        value.keys.any((key) => key != 'data' && key != 'success') ||
        (value.containsKey('success') && value['success'] != true)) {
      throw const FormatException('Invalid public catalog envelope');
    }
    final catalog = value['data'];
    if (catalog is! Map<String, dynamic>) {
      throw const FormatException('Invalid public catalog response');
    }
    final raw = jsonEncode(catalog),
        parsed = _parse(raw),
        savedAt = _now().toUtc();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey,
          jsonEncode({'saved_at': savedAt.toIso8601String(), 'catalog': raw}));
    } catch (_) {
      // A public refresh remains usable even when device cache writes fail.
    }
    return CareDirectorySnapshot(parsed, downloaded: true, savedAt: savedAt);
  }

  Future<List<int>> _boundedResponse(dynamic body) async {
    const responseLimit = maxBytes + 256;
    // The list branch supports injected, already-bounded test adapters only.
    if (body is List<int> && body.length <= responseLimit) return body;
    if (body is! ResponseBody) {
      throw const FormatException('Invalid public catalog response');
    }
    final declared = int.tryParse(
        body.headers[Headers.contentLengthHeader]?.firstOrNull ?? '');
    if (declared != null && declared > responseLimit) {
      await body.stream.listen(null).cancel();
      throw const FormatException('Public catalog exceeds size limit');
    }
    final collected = BytesBuilder(copy: false);
    await for (final chunk in body.stream.timeout(const Duration(seconds: 8))) {
      if (collected.length + chunk.length > responseLimit) {
        throw const FormatException('Public catalog exceeds size limit');
      }
      collected.add(chunk);
    }
    return collected.takeBytes();
  }
}

/// Optional, one-shot foreground approximate location. Never serializes,
/// uploads or persists coordinates. Missing platforms fall back to city/Maps.
class CareLocationService {
  static const channel = MethodChannel('com.hercare/care_location');

  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancelCurrentApproximatePosition');
    } on MissingPluginException {
      // Unsupported platforms already use the city/Maps fallback.
    } on PlatformException {
      // Cancelling never changes the availability of public support.
    }
  }

  Future<CarePosition?> current() async {
    try {
      final raw = await channel
          .invokeMethod<Map<dynamic, dynamic>>('getCurrentApproximatePosition');
      if (raw == null) return null;
      return CarePosition.fromNative(raw, now: DateTime.now().toUtc());
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

class CareDirectoryLinks {
  Future<bool> maps(CareFacility facility) async =>
      launchUrl(mapUri(facility), mode: LaunchMode.externalApplication);

  Future<bool> source(Uri uri) async {
    sourceUri(uri.toString(), careInstitutionHosts);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Uri mapUri(CareFacility facility) =>
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '${facility.nameEn}, ${facility.addressEn}',
      });
}
