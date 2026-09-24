import 'package:flutter/foundation.dart';

import '../data/models/risk_models.dart';
import '../services/risk_service.dart';

class RiskProvider extends ChangeNotifier {
  RiskProvider({RiskService? service}) : _service = service ?? RiskService();

  final RiskService _service;
  RiskStatus? _status;
  RiskPrediction? _latest;
  TelemetryPermissions _permissions = const TelemetryPermissions(
    isAndroid: false,
    notificationAccess: false,
    usageAccess: false,
  );
  TelemetrySnapshot? _snapshot;
  bool _loading = false;
  bool _working = false;
  String? _error;

  RiskStatus? get status => _status;
  RiskPrediction? get latest => _latest;
  TelemetryPermissions get permissions => _permissions;
  TelemetrySnapshot? get snapshot => _snapshot;
  bool get loading => _loading;
  bool get working => _working;
  String? get error => _error;

  Future<void> initialize() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        _service.getStatus(),
        _service.latest(),
        _service.permissions(),
      ]);
      _status = values[0] as RiskStatus;
      _latest = values[1] as RiskPrediction?;
      _permissions = values[2] as TelemetryPermissions;
      await _service.setMonitoringEnabled(_status!.consentTier3);
    } catch (error) {
      _error = _message(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshPermissions() async {
    _permissions = await _service.permissions();
    notifyListeners();
  }

  Future<bool> setConsent(bool enabled) async {
    _working = true;
    _error = null;
    notifyListeners();
    try {
      _status = await _service.updateConsent(enabled);
      return true;
    } catch (error) {
      _error = _message(error);
      return false;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<void> openNotificationSettings() =>
      _service.openNotificationSettings();

  Future<void> openUsageSettings() => _service.openUsageSettings();

  Future<bool> syncAndPredict() async {
    if (_working) return false;
    _working = true;
    _error = null;
    notifyListeners();
    try {
      if (_status?.consentTier3 == true && _permissions.isAndroid) {
        _snapshot = await _service.collectAndSync();
        _status = RiskStatus(
          consentTier3: true,
          lastTelemetryAt: DateTime.now(),
        );
      }
      _latest = await _service.generatePrediction();
      return true;
    } catch (error) {
      _error = _message(error);
      return false;
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<void> syncIfDue() async {
    await initialize();
    if (_error != null || _working) return;
    final now = DateTime.now();
    final lastTelemetry = _status?.lastTelemetryAt?.toLocal();
    final telemetryDue = _status?.consentTier3 == true &&
        _permissions.isAndroid &&
        (lastTelemetry == null ||
            lastTelemetry.year != now.year ||
            lastTelemetry.month != now.month ||
            lastTelemetry.day != now.day);
    final generated = _latest?.generatedAt.toLocal();
    final predictionDue =
        generated == null || now.difference(generated).inHours >= 24;
    if (telemetryDue || predictionDue) await syncAndPredict();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
