import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../../core/constants/app_constants.dart';

/// Auth repository — the single point of contact between the app and
/// the /api/v1/auth/* endpoints.
///
/// Handles token persistence internally so [AuthProvider] stays clean.
class AuthRepository {
  final ApiService _api;
  final LocalStorageService _storage;

  AuthRepository({
    ApiService? api,
    LocalStorageService? storage,
  })  : _api = api ?? ApiService(),
        _storage = storage ?? LocalStorageService();

  // ─── Register ─────────────────────────────────────────────────────────────
  Future<UserModel> register({
    required String phone,
    required String password,
    required String role,
    String language = 'en',
  }) async {
    try {
      final response = await _api.post('/auth/register', data: {
        'phone': phone,
        'password': password,
        'confirm_password': password,
        'role': role,
        'language': language,
      });

      final data = response.data['data'] as Map<String, dynamic>;
      await _persistTokens(data);
      return UserModel.fromJson(data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ─── Login ────────────────────────────────────────────────────────────────
  Future<UserModel> login({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _api.post('/auth/login', data: {
        'phone': phone,
        'password': password,
      });

      final data = response.data['data'] as Map<String, dynamic>;
      await _persistTokens(data);
      return UserModel.fromJson(data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ─── Get Current User ─────────────────────────────────────────────────────
  Future<UserModel?> getMe() async {
    try {
      final response = await _api.get('/auth/me');
      return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Even if the request fails, clear local session
    } finally {
      await _storage.clearUserSession();
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Future<void> _persistTokens(Map<String, dynamic> data) async {
    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;

    if (accessToken != null) {
      await _storage.setSecureString(AppConstants.accessTokenKey, accessToken);
    }
    if (refreshToken != null) {
      await _storage.setSecureString(
          AppConstants.refreshTokenKey, refreshToken);
    }
  }

  /// Converts DioException to a readable message for the UI.
  Exception _parseError(DioException e) {
    final responseData = e.response?.data;

    if (responseData is Map<String, dynamic>) {
      final message = responseData['message'] as String?;
      if (message != null) return Exception(message);

      // Field-level errors
      final errors = responseData['errors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        final first = errors.first as Map;
        return Exception(first['message'] as String? ?? 'Validation error');
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timed out. Check your internet.');
      case DioExceptionType.connectionError:
        return Exception('Could not connect to server. Check your internet.');
      default:
        return Exception('Something went wrong. Please try again.');
    }
  }
}
