import 'package:flutter/foundation.dart';

import '../services/guardian_service.dart';

class GuardianProvider extends ChangeNotifier {
  GuardianProvider({GuardianService? service})
      : _service = service ?? GuardianService();

  final GuardianService _service;
  int _activeRequests = 0;
  String? _error;

  Map<String, dynamic>? _link;
  Map<String, dynamic>? _inviteData;
  Map<String, dynamic>? _dashboard;
  final Map<String, List<dynamic>> _reportsByType = {};
  List<dynamic> _alerts = [];

  bool get isLoading => _activeRequests > 0;
  String? get error => _error;
  Map<String, dynamic>? get link => _link;
  Map<String, dynamic>? get inviteData => _inviteData;
  Map<String, dynamic>? get dashboard => _dashboard;
  List<dynamic> get alerts => List.unmodifiable(_alerts);
  bool get hasActiveLink => _link != null;
  String? get inviteCode => _inviteData?['invite_code'] as String?;

  List<dynamic> reportsFor(String type) =>
      List.unmodifiable(_reportsByType[type] ?? const []);

  void _begin() {
    _activeRequests += 1;
    _error = null;
    notifyListeners();
  }

  void _end() {
    _activeRequests = (_activeRequests - 1).clamp(0, 1 << 30).toInt();
    notifyListeners();
  }

  void _capture(Object error) {
    _error = error.toString().replaceFirst('Exception: ', '');
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> loadOrGenerateInvite() async {
    _begin();
    try {
      final result = await _service.generateInvite();
      _inviteData = result['data'] as Map<String, dynamic>?;
    } catch (error) {
      _capture(error);
    } finally {
      _end();
    }
  }

  Future<void> refreshInvite() async {
    _begin();
    try {
      final result = await _service.refreshInvite();
      _inviteData = result['data'] as Map<String, dynamic>?;
    } catch (error) {
      _capture(error);
    } finally {
      _end();
    }
  }

  Future<bool> acceptInvite({
    required String code,
    required String name,
    required String relationship,
  }) async {
    _begin();
    try {
      await _service.acceptInvite(
        inviteCode: code,
        guardianName: name,
        relationship: relationship,
      );
      _link = await _service.getLink();
      return true;
    } catch (error) {
      _capture(error);
      return false;
    } finally {
      _end();
    }
  }

  Future<void> loadLink() async {
    _begin();
    try {
      _link = await _service.getLink();
    } catch (error) {
      _capture(error);
    } finally {
      _end();
    }
  }

  Future<bool> revokeLink() async {
    _begin();
    try {
      await _service.revokeLink();
      _link = null;
      _inviteData = null;
      return true;
    } catch (error) {
      _capture(error);
      return false;
    } finally {
      _end();
    }
  }

  Future<void> loadDashboard({String lang = 'en'}) async {
    _begin();
    try {
      _dashboard = await _service.getDashboard(lang: lang);
    } catch (error) {
      _capture(error);
    } finally {
      _end();
    }
  }

  Future<void> loadReports({String type = 'weekly'}) async {
    _begin();
    try {
      _reportsByType[type] = await _service.getReports(type: type);
    } catch (error) {
      _capture(error);
    } finally {
      _end();
    }
  }

  Future<bool> generateReport({required String type}) async {
    _begin();
    try {
      await _service.generateReport(periodType: type);
      _reportsByType[type] = await _service.getReports(type: type);
      return true;
    } catch (error) {
      _capture(error);
      return false;
    } finally {
      _end();
    }
  }

  Future<void> loadAlerts() async {
    _begin();
    try {
      _alerts = await _service.getAlerts();
    } catch (error) {
      _capture(error);
    } finally {
      _end();
    }
  }

  Future<void> markAlertsRead({List<String> alertIds = const []}) async {
    try {
      await _service.markAlertsRead(alertIds: alertIds);
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
      _capture(error);
      notifyListeners();
    }
  }

  int get unreadAlertCount =>
      _alerts.where((alert) => alert['is_read'] == false).length;

  void reset() {
    _activeRequests = 0;
    _error = null;
    _link = null;
    _inviteData = null;
    _dashboard = null;
    _reportsByType.clear();
    _alerts = [];
    notifyListeners();
  }
}
