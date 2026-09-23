import 'package:flutter/foundation.dart';
import '../data/repositories/auth_repository.dart';
import '../data/models/user_model.dart';

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

  AuthProvider({AuthRepository? repo}) : _repo = repo ?? AuthRepository();

  // ─── Getters ──────────────────────────────────────────────────────────────
  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

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
      notifyListeners();
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
      notifyListeners();
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
      await _repo.logout();
    } finally {
      _user = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  // ─── Session Restore ──────────────────────────────────────────────────────
  Future<void> tryRestoreSession() async {
    _setLoading();
    try {
      _user = await _repo.getMe();
      _status =
          _user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<UserModel?> refreshCurrentUser() async {
    try {
      _user = await _repo.getMe();
      _status =
          _user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
      notifyListeners();
      return _user;
    } catch (error) {
      _setError(error.toString());
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
