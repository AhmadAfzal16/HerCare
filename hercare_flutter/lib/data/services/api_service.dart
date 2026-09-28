import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/constants/app_constants.dart';
import '../services/local_storage_service.dart';

/// Dio-based HTTP client.
///
/// - Automatically attaches Bearer token to all requests
/// - Handles 401 TOKEN_EXPIRED by refreshing the token once
/// - Never logs private request or response payloads
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _init();
  }

  late final Dio _dio;

  void _init() {
    // Prefer a build-time value for deployments, then local dotenv for development.
    String baseUrl = AppConstants.apiBaseUrl;
    try {
      final envUrl = dotenv.maybeGet('API_BASE_URL');
      if (baseUrl.isEmpty && envUrl != null && envUrl.isNotEmpty) {
        baseUrl = envUrl;
      }
    } catch (_) {
      // dotenv is optional when API_BASE_URL is supplied with --dart-define.
    }
    if (baseUrl.isEmpty && !kReleaseMode) {
      baseUrl = 'http://localhost:5000/api/v1';
    }

    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('API_BASE_URL must be an absolute URL.');
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw StateError('API_BASE_URL must use HTTPS in release builds.');
    }

    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      sendTimeout: AppConstants.apiTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Bypass-Tunnel-Reminder': 'true', // Bypasses localtunnel warning page
      },
    ));

    // Never log credentials, journals, messages, or response bodies.

    // Auth + refresh interceptor
    _dio.interceptors.add(_AuthInterceptor(_dio));
  }

  Dio get client => _dio;

  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters}) =>
      _dio.get<T>(path, queryParameters: queryParameters);

  Future<Response<T>> post<T>(String path, {dynamic data}) =>
      _dio.post<T>(path, data: data);

  Future<Response<T>> patch<T>(String path, {dynamic data}) =>
      _dio.patch<T>(path, data: data);

  Future<Response<T>> delete<T>(String path) => _dio.delete<T>(path);
}

/// Interceptor that:
///   1. Attaches access token to every request
///   2. On 401 TOKEN_EXPIRED, refreshes and retries once
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  Future<String>? _refreshFuture;

  _AuthInterceptor(this._dio);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final storage = LocalStorageService();
    final token = await storage.getSecureString(AppConstants.accessTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final body = response?.data;
    final code = body is Map ? body['code'] : null;

    if (response?.statusCode == 401 &&
        code == 'TOKEN_EXPIRED' &&
        err.requestOptions.extra['authRetried'] != true) {
      final refresh = _refreshFuture ??= _refreshAccessToken();
      try {
        final newAccess = await refresh;
        err.requestOptions.extra['authRetried'] = true;
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResponse = await _dio.fetch(err.requestOptions);
        handler.resolve(retryResponse);
      } catch (_) {
        // Transient failures must not erase the user's session/offline work.
        handler.next(err);
      } finally {
        if (identical(_refreshFuture, refresh)) _refreshFuture = null;
      }
    } else {
      handler.next(err);
    }
  }

  Future<String> _refreshAccessToken() async {
    final storage = LocalStorageService();
    final refreshToken =
        await storage.getSecureString(AppConstants.refreshTokenKey);
    if (refreshToken == null) throw Exception('No refresh token');

    final refreshDio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      sendTimeout: AppConstants.apiTimeout,
    ));
    try {
      final response = await refreshDio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });
      final data = response.data['data'] as Map<String, dynamic>;
      final newAccess = data['accessToken'] as String;
      final newRefresh = data['refreshToken'] as String;
      await storage.setSecureString(AppConstants.accessTokenKey, newAccess);
      await storage.setSecureString(AppConstants.refreshTokenKey, newRefresh);
      return newAccess;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        await storage.clearUserSession();
      }
      rethrow;
    } finally {
      refreshDio.close();
    }
  }
}
