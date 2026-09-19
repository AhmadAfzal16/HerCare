import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../core/constants/app_constants.dart';
import '../services/local_storage_service.dart';

/// Dio-based HTTP client.
///
/// - Automatically attaches Bearer token to all requests
/// - Handles 401 TOKEN_EXPIRED by refreshing the token once
/// - Logs requests in debug mode
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _init();
  }

  late final Dio _dio;

  void _init() {
    // Prefer runtime dotenv value, fallback to hardcoded constant (10.0.2.2)
    String baseUrl = AppConstants.apiBaseUrl;
    try {
      final envUrl = dotenv.maybeGet('API_BASE_URL');
      if (envUrl != null && envUrl.isNotEmpty) baseUrl = envUrl;
    } catch (_) {
      // dotenv not loaded — use constant
    }

    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      sendTimeout: AppConstants.apiTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept':        'application/json',
        'Bypass-Tunnel-Reminder': 'true', // Bypasses localtunnel warning page
      },
    ));

    // Debug logger (disabled in release)
    assert(() {
      _dio.interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        error: true,
        compact: true,
      ));
      return true;
    }());

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
  bool _isRefreshing = false;

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
    final code = response?.data?['code'];

    if (response?.statusCode == 401 &&
        code == 'TOKEN_EXPIRED' &&
        !_isRefreshing) {
      _isRefreshing = true;
      try {
        final storage = LocalStorageService();
        final refreshToken =
            await storage.getSecureString(AppConstants.refreshTokenKey);
        if (refreshToken == null) throw Exception('No refresh token');

        // Bypass interceptor for refresh call
        final refreshDio = Dio(BaseOptions(baseUrl: _dio.options.baseUrl));
        final res = await refreshDio.post('/auth/refresh', data: {
          'refresh_token': refreshToken,
        });

        final newAccess  = res.data['data']['accessToken'] as String;
        final newRefresh = res.data['data']['refreshToken'] as String;

        await storage.setSecureString(AppConstants.accessTokenKey, newAccess);
        await storage.setSecureString(AppConstants.refreshTokenKey, newRefresh);

        // Retry original request
        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResponse = await _dio.fetch(err.requestOptions);
        handler.resolve(retryResponse);
      } catch (_) {
        // Refresh failed — force logout
        final storage = LocalStorageService();
        await storage.clearUserSession();
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
}
