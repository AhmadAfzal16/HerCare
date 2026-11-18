import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/risk_models.dart';
import '../services/risk_service.dart';

class RiskProvider extends ChangeNotifier {
  RiskProvider({RiskService? service}) : _service = service ?? RiskService();

  static const _noPermissions = TelemetryPermissions(
    isAndroid: false,
    notificationAccess: false,
    usageAccess: false,
  );
  final RiskService _service;
  RiskStatus? _status;
  RiskPrediction? _latest;
  TelemetryPermissions _permissions = _noPermissions;
  TelemetrySnapshot? _snapshot;
  bool _loading = false;
  bool _working = false;
  bool _savingDetails = false;
  bool _generatingBaseline = false;
  String? _error;
  Map<String, dynamic>? _recovery;
  Map<String, dynamic>? _context;
  Map<String, dynamic>? _research;
  Map<String, dynamic>? _m4;
  String? _recoveryError;
  String? _baselineError;
  bool _bound = false, _disposed = false;
  String? _accountId;
  int _generation = 0;
  Future<void> _monitoringTail = Future.value();

  bool get _available => !_disposed && (!_bound || _accountId != null);
  bool _current(int generation) => _available && generation == _generation;
  String? get accountId => _accountId;

  void bindAccount(String? id) {
    if (_bound && id == _accountId) return;
    final prior = _accountId;
    _bound = true;
    _accountId = id;
    _generation++;
    _service.bindAccount(id);
    _status = null;
    _latest = null;
    _permissions = _noPermissions;
    _snapshot = null;
    _loading = false;
    _working = false;
    _savingDetails = false;
    _generatingBaseline = false;
    _error = null;
    _recovery = null;
    _context = null;
    _research = null;
    _m4 = null;
    _recoveryError = null;
    _baselineError = null;
    if (prior != null || id == null) {
      // Native disabling also clears the previous account's notification counts.
      unawaited(_setMonitoring(false));
    }
    notifyListeners();
  }

  Future<void> _setMonitoring(bool enabled, [int? generation]) {
    final task = _monitoringTail.then((_) async {
      if (generation == null || _current(generation)) {
        await _service.setMonitoringEnabled(enabled);
      }
    });
    _monitoringTail = task.catchError((Object _) {});
    return _monitoringTail;
  }

  Map<String, dynamic>? get recovery => _recovery;
  Map<String, dynamic>? get modelContext => _context;
  Map<String, dynamic>? get research => _research;
  Map<String, dynamic>? get m4 => _m4;
  String? get recoveryError => _recoveryError;
  bool get savingDetails => _savingDetails;
  bool get generatingBaseline => _generatingBaseline;
  String? get baselineError => _baselineError;
  RiskStatus? get status => _status;
  RiskPrediction? get latest => _latest;
  TelemetryPermissions get permissions => _permissions;
  TelemetrySnapshot? get snapshot => _snapshot;
  bool get loading => _loading;
  bool get working => _working;
  String? get error => _error;

  Future<void> initialize() async {
    if (!_available || _loading || _working || _savingDetails) return;
    final generation = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([
        _loadM4(generation),
        _loadDetails(generation),
        _loadStatus(generation),
        _service.latest().then<void>((value) {
          if (_current(generation)) _latest = value;
        }).catchError((Object _) {
          if (_current(generation)) _latest = null;
        }),
      ]);
    } finally {
      if (_current(generation)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadStatus(int generation) async {
    try {
      final results =
          await Future.wait([_service.getStatus(), _service.permissions()]);
      if (!_current(generation)) return;
      _status = results[0] as RiskStatus;
      _permissions = results[1] as TelemetryPermissions;
      await _setMonitoring(_status!.consentTier3, generation);
    } catch (error) {
      if (_current(generation)) {
        _status = null;
        _permissions = _noPermissions;
        _snapshot = null;
        _error = _message(error);
        await _setMonitoring(false, generation);
      }
    }
  }

  Future<void> _loadM4(int generation) async {
    if (!_current(generation)) return;
    try {
      final report = await _service.m4Reports();
      if (_current(generation)) _m4 = report;
    } catch (_) {
      if (_current(generation)) _m4 = null;
    }
  }

  Future<void> _loadDetails(int generation) async {
    if (!_current(generation)) return;
    _recoveryError = null;
    await Future.wait([
      _service.recovery().then<void>((value) {
        if (_current(generation)) _recovery = value;
      }).catchError((Object _) {
        if (_current(generation)) {
          _recovery = null;
          _recoveryError = 'Recovery summary is unavailable.';
        }
      }),
      _service.modelContext().then<void>((value) {
        if (_current(generation)) _context = value;
      }).catchError((Object _) {
        if (_current(generation)) _context = null;
      }),
      _service.researchConsent().then<void>((value) {
        if (_current(generation)) _research = value;
      }).catchError((Object _) {
        if (_current(generation)) _research = null;
      }),
    ]);
  }

  Future<bool> _saveDetails(Future<void> Function(int) action) async {
    if (!_available || _loading || _working || _savingDetails) return false;
    final generation = _generation;
    _savingDetails = true;
    _error = null;
    notifyListeners();
    try {
      await action(generation);
      return _current(generation);
    } catch (error) {
      if (_current(generation)) _error = _message(error);
      return false;
    } finally {
      if (_current(generation)) {
        _savingDetails = false;
        notifyListeners();
      }
    }
  }

  Future<bool> saveM4Checkin(
    Map<String, int?> values, {
    required String date,
  }) =>
      _saveDetails((generation) async {
        Map<String, dynamic> checkin;
        try {
          checkin = await _service.saveM4Checkin(values, date: date);
        } catch (_) {
          // The server date may have changed while the form was open.
          await _loadM4(generation);
          rethrow;
        }
        if (!_current(generation)) return;
        if (_m4 != null) _m4 = {..._m4!, 'checkin': checkin};
        await _loadM4(generation);
      });

  Future<bool> setM4TextConsent(bool enabled) =>
      _saveDetails((generation) async {
        // Remove reports calculated with the previous text permission before
        // requesting fresh ones.
        if (_m4 != null) {
          _m4 = {..._m4!, 'reports': const []};
          notifyListeners();
        }
        try {
          await _service.setM4TextConsent(enabled);
        } finally {
          await _loadM4(generation);
        }
      });

  Future<bool> saveModelContext(Map<String, dynamic> values) =>
      _saveDetails((generation) async {
        await _service.saveModelContext(values);
        if (!_current(generation)) return;
        _context = Map<String, dynamic>.from(values);
        _latest = null;
        await _loadM4(generation);
      });

  Future<void> generateBaseline() async {
    await _saveDetails((generation) async {
      _generatingBaseline = true;
      _baselineError = null;
      notifyListeners();
      try {
        final prediction = await _service.generatePrediction();
        if (_current(generation)) _latest = prediction;
      } catch (error) {
        if (_current(generation)) _baselineError = _message(error);
      } finally {
        if (_current(generation)) _generatingBaseline = false;
      }
    });
  }

  Future<bool> setResearchConsent(bool enabled) =>
      _saveDetails((generation) async {
        final result = await _service.setResearchConsent(enabled);
        if (_current(generation)) _research = result;
      });

  Future<void> refreshPermissions() async {
    if (!_available) return;
    final generation = _generation;
    final permissions = await _service.permissions();
    if (!_current(generation)) return;
    _permissions = permissions;
    notifyListeners();
  }

  Future<bool> setConsent(bool enabled) => _saveDetails((generation) async {
        final status = await _service.updateConsent(enabled);
        if (!_current(generation)) return;
        _status = status;
        if (!status.consentTier3) _snapshot = null;
        await _setMonitoring(status.consentTier3, generation);
        await _loadM4(generation);
      });

  Future<void> openNotificationSettings() =>
      _service.openNotificationSettings();

  Future<void> openUsageSettings() => _service.openUsageSettings();

  Future<bool> refreshReports() => _syncReports(uploadTelemetry: true);

  Future<bool> _syncReports({required bool uploadTelemetry}) async {
    if (!_available || _loading || _working || _savingDetails) return false;
    final generation = _generation;
    _working = true;
    _error = null;
    notifyListeners();
    try {
      if (uploadTelemetry &&
          _status?.consentTier3 == true &&
          _permissions.isAndroid &&
          (_permissions.notificationAccess || _permissions.usageAccess)) {
        try {
          final snapshot = await _service.collectAndSync();
          if (!_current(generation)) return false;
          _snapshot = snapshot;
          _status =
              RiskStatus(consentTier3: true, lastTelemetryAt: DateTime.now());
        } catch (_) {
          if (!_current(generation)) return false;
          _error =
              'Phone signals could not sync. Other records can still be reviewed.';
        }
      }
      await Future.wait([_loadM4(generation), _loadDetails(generation)]);
      return _current(generation) && _m4 != null;
    } finally {
      if (_current(generation)) {
        _working = false;
        notifyListeners();
      }
    }
  }

  Future<void> syncIfDue() async {
    final generation = _generation;
    await initialize();
    if (!_current(generation) || _status?.consentTier3 != true) return;
    final now = DateTime.now();
    final last = _status?.lastTelemetryAt?.toLocal();
    if (_permissions.isAndroid &&
        (last == null ||
            last.year != now.year ||
            last.month != now.month ||
            last.day != now.day)) {
      await refreshReports();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
