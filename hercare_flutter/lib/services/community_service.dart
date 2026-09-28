import 'dart:math';
import 'package:dio/dio.dart';
import '../data/models/community_models.dart';
import '../data/services/api_service.dart';

class CommunityService {
  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? data, Map<String, dynamic>? query}) async {
    try {
      final result = await ApiService().client.request('/community$path',
          data: data, queryParameters: query, options: Options(method: method));
      return result.data['data'];
    } on DioException catch (error) {
      final response = error.response?.data;
      throw CommunityException(response is Map && response['message'] is String
          ? response['message'] as String
          : 'Could not connect to the community. Please try again.');
    }
  }

  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await _request('GET', '/status'));
  Future<void> join(String version) async {
    await _request('POST', '/join',
        data: {'accepted': true, 'rules_version': version});
  }

  Future<CommunityPage> feed(
          {String? topic,
          String? cursor,
          bool mine = false,
          String? sessionId}) async =>
      CommunityPage(
          Map<String, dynamic>.from(await _request('GET', '/posts', query: {
        if (topic != null) 'topic': topic,
        if (cursor != null) 'cursor': cursor,
        if (mine) 'mine': 'true',
        if (sessionId != null) 'session_id': sessionId,
      })));
  Future<CommunityPost> detail(String id) async => CommunityPost(
      Map<String, dynamic>.from(await _request('GET', '/posts/$id')));
  Future<CommunityPage> comments(String id, {String? cursor}) async =>
      CommunityPage(Map<String, dynamic>.from(await _request(
          'GET', '/posts/$id/comments',
          query: {if (cursor != null) 'cursor': cursor})));
  Future<Map<String, dynamic>> submit(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await _request('POST', '/posts', data: data));
  Future<void> remove(String id) async {
    await _request('DELETE', '/posts/$id');
  }

  Future<void> react(String id, String kind, bool active) async {
    await _request('PUT', '/posts/$id/reactions',
        data: {'kind': kind, 'active': active});
  }

  Future<void> report(String id, String reason) async {
    await _request('POST', '/posts/$id/reports', data: {'reason': reason});
  }

  Future<void> block(String id, {bool active = true}) async {
    await _request(active ? 'PUT' : 'DELETE', '/blocks/$id');
  }

  Future<List<Map<String, dynamic>>> blocks() async =>
      (await _request('GET', '/blocks') as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<List<Map<String, dynamic>>> sessions() async =>
      (await _request('GET', '/sessions') as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<void> schedule(Map<String, dynamic> data) async {
    await _request('POST', '/sessions', data: data);
  }

  Future<void> cancelSession(String id) async {
    await _request('DELETE', '/sessions/$id');
  }

  Future<CommunityPage> queue({String? cursor}) async => CommunityPage(
      Map<String, dynamic>.from(await _request('GET', '/moderation',
          query: {if (cursor != null) 'cursor': cursor})));
  Future<void> review(
      CommunityPost post, String decision, String reason) async {
    await _request('PUT', '/moderation/${post.id}', data: {
      'decision': decision,
      'reason': reason,
      'version': post.version
    });
  }

  Future<void> suspend(String id, bool suspended, String reason) async {
    await _request('PUT', '/members/$id/suspension',
        data: {'suspended': suspended, 'reason': reason});
  }

  static String requestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}

class CommunityException implements Exception {
  CommunityException(this.message);
  final String message;
  @override
  String toString() => message;
}
