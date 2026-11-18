import 'package:flutter/foundation.dart';

import '../services/guardian_service.dart';

class GuardianProvider extends ChangeNotifier {
  GuardianProvider({GuardianService? service})
      : _service = service ?? GuardianService();

  final GuardianService _service;
  int _activeRequests = 0;
  int _generation = 0;
  bool _disposed = false, _bound = false;
  String? _accountId;
  bool _valid(int generation) => !_disposed && generation == _generation;
  bool get _available => !_disposed && (!_bound || _accountId != null);

  void bindAccount(String? accountId) {
    if (_bound && _accountId == accountId) return;
    _bound = true;
    _accountId = accountId;
    _service.bindAccount(accountId);
    reset();
  }

  String? _error;

  Map<String, dynamic>? _link;
  Map<String, dynamic>? _inviteData;
  Map<String, dynamic>? _dashboard;
  final Map<String, List<dynamic>> _reportsByType = {};
  Map<String, dynamic>? _wellbeingTrends;
  bool _loadingWellbeingTrends = false;
  List<dynamic> _alerts = [];

  bool get isLoading => _activeRequests > 0;
  String? get error => _error;
  Map<String, dynamic>? get link => _link;
  Map<String, dynamic>? get inviteData => _inviteData;
  Map<String, dynamic>? get dashboard => _dashboard;
  List<dynamic> get alerts => List.unmodifiable(_alerts);
  bool get hasActiveLink => _link != null;
  Map<String, dynamic>? get wellbeingTrends => _wellbeingTrends;
  bool get loadingWellbeingTrends => _loadingWellbeingTrends;
  String? get inviteCode => _inviteData?['invite_code'] as String?;

  List<dynamic> reportsFor(String type) =>
      List.unmodifiable(_reportsByType[type] ?? const []);

  void _begin() {
    _activeRequests += 1;
    _error = null;
    notifyListeners();
  }

  void _end(int generation) {
    if (!_valid(generation)) return;
    _activeRequests = (_activeRequests - 1).clamp(0, 1 << 30).toInt();
    notifyListeners();
  }

  void _capture(Object error, int generation) {
    if (!_valid(generation)) return;
    if (error is GuardianAccessException) reset();
    _error = error.toString().replaceFirst('Exception: ', '');
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> loadOrGenerateInvite() async {
    if (!_available) return;
    final generation = _generation;
    _begin();
    try {
      final result = await _service.generateInvite();
      if (!_valid(generation)) return;
      _inviteData = result['data'] as Map<String, dynamic>?;
    } catch (error) {
      _capture(error, generation);
    } finally {
      _end(generation);
    }
  }

  Future<void> refreshInvite() async {
    if (!_available) return;
    final generation = _generation;
    _begin();
    try {
      final result = await _service.refreshInvite();
      if (!_valid(generation)) return;
      _inviteData = result['data'] as Map<String, dynamic>?;
    } catch (error) {
      _capture(error, generation);
    } finally {
      _end(generation);
    }
  }

  Future<bool> acceptInvite({
    required String code,
    required String name,
    required String relationship,
  }) async {
    if (!_available) return false;
    final generation = _generation;
    _begin();
    try {
      await _service.acceptInvite(
        inviteCode: code,
        guardianName: name,
        relationship: relationship,
      );
      if (!_valid(generation)) return false;
      final link = await _service.getLink();
      if (!_valid(generation)) return false;
      if (link == null || link['id'] != _link?['id']) _clearLinkedData();
      _link = link;
      return _valid(generation);
    } catch (error) {
      _capture(error, generation);
      return false;
    } finally {
      _end(generation);
    }
  }

  Future<void> loadLink() async {
    if (!_available) return;
    final generation = _generation;
    _begin();
    try {
      final link = await _service.getLink();
      if (!_valid(generation)) return;
      if (link == null || link['id'] != _link?['id']) reset();
      _link = link;
      notifyListeners();
    } catch (error) {
      _capture(error, generation);
    } finally {
      _end(generation);
    }
  }

  Future<bool> revokeLink() async {
    if (!_available) return false;
    final generation = _generation;
    _begin();
    try {
      await _service.revokeLink();
      if (!_valid(generation)) return false;
      reset();
      return true;
    } catch (error) {
      _capture(error, generation);
      return false;
    } finally {
      _end(generation);
    }
  }

  Future<void> loadDashboard({String lang = 'en'}) async {
    if (!_available) return;
    final generation = _generation;
    _begin();
    try {
      final dashboard = await _service.getDashboard(lang: lang);
      if (_valid(generation)) _dashboard = dashboard;
    } catch (error) {
      _capture(error, generation);
    } finally {
      _end(generation);
    }
  }

  Future<void> loadReports({String type = 'weekly'}) async {
    if (!_available) return;
    final generation = _generation;
    _begin();
    try {
      final reports = await _service.getReports(type: type);
      if (_valid(generation)) _reportsByType[type] = reports;
    } catch (error) {
      _capture(error, generation);
    } finally {
      _end(generation);
    }
  }

  Future<void> loadWellbeingTrends() async {
    if (!_available || _loadingWellbeingTrends) return;
    final generation = _generation;
    _wellbeingTrends = null;
    _loadingWellbeingTrends = true;
    notifyListeners();
    try {
      final trends = await _service.getWellbeingTrends();
      if (_valid(generation)) _wellbeingTrends = trends;
    } catch (error) {
      if (!_valid(generation)) return;
      if (error is GuardianAccessException) reset();
    } finally {
      if (_valid(generation)) {
        _loadingWellbeingTrends = false;
        notifyListeners();
      }
    }
  }

  Future<bool> generateReport({required String type}) async {
    if (!_available) return false;
    final generation = _generation;
    _begin();
    try {
      await _service.generateReport(periodType: type);
      if (!_valid(generation)) return false;
      final reports = await _service.getReports(type: type);
      if (_valid(generation)) _reportsByType[type] = reports;
      return _valid(generation);
    } catch (error) {
      _capture(error, generation);
      return false;
    } finally {
      _end(generation);
    }
  }

  Future<void> loadAlerts() async {
    if (!_available) return;
    final generation = _generation;
    _begin();
    try {
      final alerts = await _service.getAlerts();
      if (_valid(generation)) _alerts = alerts;
    } catch (error) {
      _capture(error, generation);
    } finally {
      _end(generation);
    }
  }

  Future<void> markAlertsRead({List<String> alertIds = const []}) async {
    if (!_available) return;
    final generation = _generation;
    try {
      await _service.markAlertsRead(alertIds: alertIds);
      if (!_valid(generation)) return;
      final selected = alertIds.toSet();
      _alerts = _alerts.map((alert) {
        if (alert is! Map<String, dynamic>) return alert;
        if (selected.isNotEmpty && !selected.contains(alert['id'])) {
          return alert;
        }
        return {...alert, 'is_read': true};
      }).toList();
      notifyListeners();
    } catch (error) {
      _capture(error, generation);
      if (_valid(generation)) notifyListeners();
    }
  }

  int get unreadAlertCount =>
      _alerts.where((alert) => alert['is_read'] == false).length;

  void reset() {
    _generation++;
    _activeRequests = 0;
    _error = null;
    _clearLinkedData();
    if (!_disposed) notifyListeners();
  }

  void _clearLinkedData() {
    _link = null;
    _inviteData = null;
    _dashboard = null;
    _reportsByType.clear();
    _wellbeingTrends = null;
    _loadingWellbeingTrends = false;
    _alerts = [];
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
