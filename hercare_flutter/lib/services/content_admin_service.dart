import 'package:dio/dio.dart';
import '../data/services/api_service.dart';

class ContentAdminException implements Exception {
  const ContentAdminException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get accessDenied => statusCode == 401 || statusCode == 403;
  @override
  String toString() => message;
}

/// Operator-only catalog requests; pin the exact opening account and API.
class ContentAdminService {
  ContentAdminService({required this.accountId, Dio? client})
      : _client = client ?? ApiService().client {
    _origin = _client.options.baseUrl;
  }
  final String accountId;
  final Dio _client;
  late final String _origin;

  static bool _id(String value) => RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[1-8][a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$')
      .hasMatch(value);

  static void _checkId(String value) {
    if (!_id(value)) {
      throw const ContentAdminException(
          'Invalid content identifier. Refresh the catalog.');
    }
  }

  static Map<String, dynamic> _receipt(Map<String, dynamic> value,
      {required String status, String? id}) {
    final receivedId = value['id'];
    if (receivedId is! String ||
        !_id(receivedId) ||
        (id != null && receivedId != id) ||
        value['version'] is! int ||
        (value['version'] as int) < 1 ||
        value['status'] != status) {
      throw const ContentAdminException(
          'The draft status was not confirmed. Refresh before trying again.');
    }
    return value;
  }

  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? data, Map<String, dynamic>? query}) async {
    if (_client.options.baseUrl != _origin) {
      throw const ContentAdminException(
          'The server changed. Reopen the catalog.');
    }
    try {
      final response = await _client.request('/content/admin$path',
          data: data,
          queryParameters: query,
          options: Options(
              method: method,
              followRedirects: false,
              headers: {'X-Content-Account-Id': accountId}));
      if (_client.options.baseUrl != _origin) {
        throw const ContentAdminException(
            'The server changed. Reopen the catalog.');
      }
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw const ContentAdminException(
            'Invalid catalog response. Please refresh.');
      }
      return Map<String, dynamic>.from(body['data'] as Map);
    } on ContentAdminException {
      rethrow;
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      throw ContentAdminException(
          code == 409
              ? 'This item changed. Refresh before trying again.'
              : code == 401 || code == 403
                  ? 'Administrator access is unavailable.'
                  : code == 422
                      ? 'Check the fields, trusted source, rights and activity ID.'
                      : 'The catalog could not be updated. Please retry.',
          statusCode: code);
    } on Object {
      // Do not surface response values, parser details or interceptor exceptions.
      throw const ContentAdminException(
          'Invalid catalog response. Please refresh.');
    }
  }

  Future<Map<String, dynamic>> list({String? status, int offset = 0}) async {
    final result = await request('GET', '/items', query: {
      'limit': 30,
      'offset': offset,
      if (status != null) 'status': status,
    });
    final items = result['items'];
    if (items is! List ||
        items.length > 30 ||
        items.any((item) =>
            item is! Map ||
            item['id'] is! String ||
            !_id(item['id'] as String) ||
            item['version'] is! int ||
            (item['version'] as int) < 1 ||
            !{'draft', 'reviewed', 'published', 'archived'}
                .contains(item['status']) ||
            item['title_en'] is! String ||
            item['title_ur'] is! String ||
            item['summary_en'] is! String ||
            item['summary_ur'] is! String)) {
      throw const ContentAdminException(
          'Invalid catalog response. Please refresh.');
    }
    return result;
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> item) async =>
      _receipt(await request('POST', '/items', data: item), status: 'draft');
  Future<Map<String, dynamic>> update(
      String id, Map<String, dynamic> item) async {
    _checkId(id);
    return _receipt(await request('PUT', '/items/$id', data: item),
        status: 'draft', id: id);
  }

  Future<Map<String, dynamic>> review(
      String id, Map<String, dynamic> decision) async {
    _checkId(id);
    return _receipt(await request('PUT', '/items/$id/review', data: decision),
        status: decision['decision'] == 'approved' ? 'reviewed' : 'draft',
        id: id);
  }

  Future<Map<String, dynamic>> publication(
      String id, int version, bool published) async {
    _checkId(id);
    return _receipt(
        await request('PUT', '/items/$id/publication',
            data: {'version': version, 'published': published}),
        status: published ? 'published' : 'draft',
        id: id);
  }

  Future<Map<String, dynamic>> archive(String id, int version) async {
    _checkId(id);
    return _receipt(
        await request('DELETE', '/items/$id', query: {'version': version}),
        status: 'archived',
        id: id);
  }
}
