import 'package:flutter/foundation.dart';
import '../data/repositories/auth_repository.dart';
import '../data/models/user_model.dart';
import '../services/push_notification_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

/// Authentication state manager.
///
/// Responsibilities:
///   - Holds current [AuthStatus] and [UserModel]
///   - Delegates all auth operations to [AuthRepository]
///   - Exposes error messages for the UI layer
class AuthProvider extends ChangeNotifier {
  final AuthRepository _repo;

  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _errorMessage;
  bool _offlineSession = false;

  AuthProvider({AuthRepository? repo}) : _repo = repo ?? AuthRepository();

  // ─── Getters ──────────────────────────────────────────────────────────────
  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isOfflineSession => _offlineSession;

  // ─── Register ─────────────────────────────────────────────────────────────
  Future<bool> register({
    required String phone,
    required String password,
    required String role,
    String language = 'en',
  }) async {
    _setLoading();
    try {
      _user = await _repo.register(
        phone: phone,
        password: password,
        role: role,
        language: language,
      );
      _status = AuthStatus.authenticated;
      _offlineSession = false;
      notifyListeners();
      await PushNotificationService.instance.onAuthenticated();
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  // ─── Login ────────────────────────────────────────────────────────────────
  Future<bool> login({
    required String phone,
    required String password,
  }) async {
    _setLoading();
    try {
      _user = await _repo.login(phone: phone, password: password);
      _status = AuthStatus.authenticated;
      _offlineSession = false;
      notifyListeners();
      await PushNotificationService.instance.onAuthenticated();
      return true;
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    _setLoading();
    try {
      await PushNotificationService.instance.beforeLogout();
      await _repo.logout();
    } finally {
      _user = null;
      _offlineSession = false;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  // ─── Session Restore ──────────────────────────────────────────────────────
  Future<void> tryRestoreSession() async {
    _setLoading();
    try {
      _user = await _repo.getMe();
      _offlineSession = _repo.restoredOffline;
      _status =
          _user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      if (_user != null && !_offlineSession) {
        await PushNotificationService.instance.onAuthenticated();
      }
    } catch (error) {
      _errorMessage = error.toString();
      _status = AuthStatus.error;
    }
    notifyListeners();
  }

  Future<UserModel?> refreshCurrentUser() async {
    try {
      _user = await _repo.getMe(allowCached: false);
      _offlineSession = false;
      _status =
          _user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
      notifyListeners();
      return _user;
    } catch (error) {
      _errorMessage = error.toString();
      // Failed revalidation is not a logout. Keep a previously restored shell.
      if (_user != null) {
        _offlineSession = true;
        _status = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.error;
      }
      notifyListeners();
      return null;
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────
  void _setLoading() {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = AuthStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
