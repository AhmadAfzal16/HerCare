import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../../core/constants/app_constants.dart';

/// Auth repository — the single point of contact between the app and
/// the /api/v1/auth/* endpoints.
///
/// Handles token persistence internally so [AuthProvider] stays clean.
class AuthRepository {
  final Dio _api;
  final LocalStorageService _storage;
  static const sessionCacheKey = 'session_identity_v1';
  static const offlineSessionLifetime = Duration(days: 7);
  bool restoredOffline = false;

  AuthRepository({
    ApiService? api,
    Dio? client,
    LocalStorageService? storage,
  })  : _api = client ?? (api ?? ApiService()).client,
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
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      await _cacheUser(user);
      return user;
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
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      await _cacheUser(user);
      return user;
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  // ─── Get Current User ─────────────────────────────────────────────────────
  Future<UserModel?> getMe({bool allowCached = true}) async {
    restoredOffline = false;
    if (await _storage.getSecureString(AppConstants.accessTokenKey) == null) {
      return null;
    }
    try {
      final response =
          await _api.get('/auth/me').timeout(const Duration(seconds: 8));
      final user =
          UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
      await _cacheUser(user);
      return user;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        await _storage.clearUserSession();
        return null;
      }
      final transient = [
            DioExceptionType.connectionError,
            DioExceptionType.connectionTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.sendTimeout
          ].contains(error.type) ||
          (error.response?.statusCode ?? 0) >= 500 ||
          error.response?.statusCode == 429;
      if (!transient) rethrow;
      return _offlineUser(allowCached);
    } on TimeoutException {
      return _offlineUser(allowCached);
    }
  }

  Future<void> _cacheUser(UserModel user) async {
    restoredOffline = false;
    if (kIsWeb) {
      return; // Do not add identity caching to the web plaintext fallback.
    }
    await _storage.setSecureString(
        sessionCacheKey,
        jsonEncode({
          'user': user.toJson(),
          'verified_at': DateTime.now().toUtc().toIso8601String(),
          'api_origin': _api.options.baseUrl,
        }));
  }

  Future<UserModel?> _offlineUser(bool allowed) async {
    // A cache grants local continuity, never server-side authorization.
    if (!kIsWeb &&
        allowed &&
        await _storage.getSecureString(AppConstants.refreshTokenKey) != null) {
      final raw = await _storage.getSecureString(sessionCacheKey);
      try {
        if (raw != null) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final age = DateTime.now()
              .toUtc()
              .difference(DateTime.parse(data['verified_at'] as String));
          final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
          if (data['api_origin'] == _api.options.baseUrl &&
              !age.isNegative &&
              age <= offlineSessionLifetime &&
              (user.isMother || user.isGuardian)) {
            restoredOffline = true;
            return user;
          }
        }
      } on FormatException {
        /* Invalid cache is not an authenticated session. */
      } on TypeError {
        /* Old or malformed cache requires online verification. */
      }
    }
    throw const SessionUnavailableException();
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Even if the request fails, clear local session
    } finally {
      restoredOffline = false;
      await _storage.clearUserSession();
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Future<void> _persistTokens(Map<String, dynamic> data) async {
    await _storage.deleteSecureString(sessionCacheKey);
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

class SessionUnavailableException implements Exception {
  const SessionUnavailableException();
  @override
  String toString() =>
      'Cannot reach HerCare to verify your session. Your saved sign-in has not been removed. Reconnect and retry.';
}
