import 'package:url_launcher/url_launcher.dart';

/// Only dialer actions and fixed, non-personal map searches leave this module.
/// Never requests CALL_PHONE, GPS access, addresses, clinical text or contacts.
class CrisisLinks {
  Future<bool> call(String phone) async =>
      launchUrl(phoneUri(phone), mode: LaunchMode.externalApplication);

  Future<bool> openDialer() async =>
      launchUrl(Uri(scheme: 'tel'), mode: LaunchMode.externalApplication);

  Future<bool> map({bool mentalHealth = false}) async =>
      launchUrl(mapUri(mentalHealth: mentalHealth),
          mode: LaunchMode.externalApplication);

  static Uri phoneUri(String value) {
    final phone = value.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?[0-9]{3,15}$').hasMatch(phone)) {
      throw const FormatException('Invalid dial number');
    }
    return Uri(scheme: 'tel', path: phone);
  }

  static Uri mapUri({bool mentalHealth = false}) =>
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': mentalHealth
            ? 'mental health clinic near me'
            : 'nearest emergency department',
      });
}
