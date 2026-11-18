import 'dart:math';

import 'package:dio/dio.dart';

import '../data/models/content_models.dart';
import '../data/services/api_service.dart';
import '../presentation/content/content_cache.dart';

class ContentException implements Exception {
  const ContentException(this.message, {this.statusCode, this.offline = false});
  final String message;
  final int? statusCode;
  final bool offline;
  bool get accessDenied => statusCode == 401 || statusCode == 403;
  @override
  String toString() => message;
}

class ContentAccountException implements Exception {
  @override
  String toString() => 'Your account changed. Reopen your content.';
}

class ContentService {
  ContentService({Dio? client, ContentCache? cache})
      : _injectedClient = client,
        _cache = cache ?? ContentCache();
  final Dio? _injectedClient;
  Dio get _client => _injectedClient ?? ApiService().client;
  final ContentCache _cache;
  String? _owner;
  String? _boundOrigin;
  int _generation = 0;
  Future<void> _cacheTail = Future.value();
  String get origin => _client.options.baseUrl;

  void bindAccount(String? id) {
    final currentOrigin = origin;
    if (_owner == id && _boundOrigin == currentOrigin) return;
    final previous = _owner, previousOrigin = _boundOrigin;
    _owner = id;
    _boundOrigin = currentOrigin;
    _generation++;
    if (previous != null && previousOrigin != null) {
      // Serialize after any previous write, so an in-flight write cannot
      // resurrect the old account's copy after logout or account switching.
      _cacheOperation(() => _cache.clear(previous, previousOrigin))
          .catchError((Object _) {});
    }
  }

  void _check(int generation, String apiOrigin) {
    if (_owner == null || _generation != generation || apiOrigin != origin) {
      throw ContentAccountException();
    }
  }

  Future<T> _cacheOperation<T>(Future<T> Function() action) {
    final result = _cacheTail.then((_) => action());
    _cacheTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? query, Map<String, dynamic>? data}) async {
    final generation = _generation, apiOrigin = origin;
    _check(generation, apiOrigin);
    try {
      final response = await _client.request('/content$path',
          data: data,
          queryParameters: query,
          options: Options(method: method, followRedirects: false, headers: {
            'X-Content-Account-Id': _owner,
          }));
      _check(generation, apiOrigin);
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] == null) {
        throw const FormatException('Invalid content response');
      }
      return body['data'];
    } on DioException catch (error) {
      _check(generation, apiOrigin);
      final code = error.response?.statusCode;
      final offline = error.response == null &&
          error.type != DioExceptionType.cancel &&
          error.type != DioExceptionType.badCertificate;
      throw ContentException(
          code == 409
              ? 'Your preferences changed. Refresh and try again.'
              : code == 404
                  ? 'This content is no longer available.'
                  : code == 401 || code == 403
                      ? 'Sign in again to view your content.'
                      : 'Content could not be refreshed. Please try again.',
          statusCode: code,
          offline: offline);
    } on FormatException {
      throw const ContentException('Invalid content response. Please retry.');
    } on TypeError {
      throw const ContentException('Invalid content response. Please retry.');
    }
  }

  Future<ContentFeed> feed(
      {required String language, bool savedOnly = false}) async {
    final json = await _request('GET', savedOnly ? '/saved' : '/feed', query: {
      'language': language == 'ur' ? 'ur' : 'en',
      'limit': savedOnly ? 100 : 30
    });
    try {
      final result =
          ContentFeed.fromJson(Map<String, dynamic>.from(json as Map));
      if (!savedOnly && result.items.length > 30) {
        throw const FormatException('Oversized content feed');
      }
      return result;
    } on Object {
      throw const ContentException('Invalid content response. Please retry.');
    }
  }

  Future<ContentItem> detail(String id) async {
    _validateId(id);
    final json = await _request('GET', '/items/$id');
    try {
      return ContentItem.fromJson(Map<String, dynamic>.from(json as Map));
    } on Object {
      throw const ContentException('Invalid content response. Please retry.');
    }
  }

  Future<ContentPreferences> preferences(ContentPreferences value) async =>
      ContentPreferences.fromJson(Map<String, dynamic>.from(
          await _request('PUT', '/preferences', data: value.toJson()) as Map));

  Future<void> feedback(String id, String value, String requestId) async {
    _validateId(id);
    if (!{'helpful', 'not_helpful', 'dismissed'}.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    await _request('PUT', '/items/$id/feedback',
        data: {'client_request_id': requestId, 'value': value});
  }

  Future<void> save(String id, bool saved, String requestId) async {
    _validateId(id);
    await _request('PUT', '/items/$id/saved',
        data: {'client_request_id': requestId, 'saved': saved});
  }

  Future<CachedContent?> readCache() async {
    final generation = _generation, apiOrigin = origin, owner = _owner;
    _check(generation, apiOrigin);
    final result = await _cacheOperation(() async {
      _check(generation, apiOrigin);
      return _cache.read(owner!, apiOrigin);
    });
    _check(generation, apiOrigin);
    return result;
  }

  Future<void> writeCache(List<ContentItem> items,
      ContentPreferences preferences, String revision) async {
    final generation = _generation, apiOrigin = origin, owner = _owner;
    _check(generation, apiOrigin);
    await _cacheOperation(() async {
      _check(generation, apiOrigin);
      await _cache.save(owner!, apiOrigin, items, preferences, revision);
    });
    _check(generation, apiOrigin);
  }

  Future<void> clearCache() async {
    final generation = _generation, apiOrigin = origin, owner = _owner;
    _check(generation, apiOrigin);
    await _cacheOperation(() => _cache.clear(owner!, apiOrigin));
    _check(generation, apiOrigin);
  }

  static void _validateId(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(value)) {
      throw const FormatException('Invalid content ID');
    }
  }

  static String requestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}
