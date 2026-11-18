import '../../data/models/content_models.dart';
import '../../data/models/therapy_models.dart';

/// Catalogue data cannot navigate to arbitrary routes or invoke native intents.
abstract final class ContentActions {
  static String? activityRoute(ContentItem item, {required String role}) {
    if (role != 'mother' || item.format != 'activity') return null;
    final matches = TherapyCatalog.activities.where((activity) =>
        activity.id == item.activityId && activity.type == item.activityType);
    if (matches.isEmpty) return null;
    final path = switch (item.activityType) {
      'breathing' => '/therapy/breathing',
      'meditation' => '/therapy/meditation',
      'cbt' => '/therapy/cbt',
      'game' => '/therapy/game',
      _ => null,
    };
    return path == null
        ? null
        : '$path?id=${Uri.encodeComponent(item.activityId!)}';
  }

  static Uri? httpsLink(String? value) {
    if (value == null || value.length > 2048) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    final host = uri.host.toLowerCase();
    // No local/private destinations, credential URLs or custom app schemes.
    if (!host.contains('.') ||
        host == 'localhost' ||
        host.endsWith('.local') ||
        host.endsWith('.localhost') ||
        host.contains(':') ||
        RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(host)) {
      return null;
    }
    return uri;
  }

  static Uri? mediaLink(String? value, List<String> allowedHosts) {
    final uri = httpsLink(value);
    return uri != null && allowedHosts.contains(uri.host.toLowerCase())
        ? uri
        : null;
  }
}
