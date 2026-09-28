import 'package:flutter/material.dart';
import '../data/services/local_storage_service.dart';
import '../../core/constants/app_constants.dart';

/// Centralized LanguageProvider.
/// Persists locale selection and notifies all dependents on change.
class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  bool get isUrdu => _locale.languageCode == 'ur';
  bool get isEnglish => _locale.languageCode == 'en';

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ur'),
  ];

  LanguageProvider() {
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final storage = LocalStorageService();
    final code = await storage.getString(AppConstants.languageKey);
    if (code != null) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final storage = LocalStorageService();
    await storage.setString(AppConstants.languageKey, locale.languageCode);
  }

  Future<void> toggleLocale() async {
    await setLocale(isUrdu ? const Locale('en') : const Locale('ur'));
  }
}
