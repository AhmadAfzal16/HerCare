import '../core/routing/app_router.dart';

/// A push can select an allow-listed destination, never an arbitrary deep link.
String? pushDestination(
  Map<String, dynamic> data, {
  required String userId,
  required String role,
  required bool onboardingComplete,
}) {
  final recipient = data['recipient_id'];
  if (recipient != null && recipient != userId) return null;
  if (data['route'] == AppRoutes.tests &&
      data['type'] == 'screening_reminder' &&
      recipient == userId &&
      role == 'mother' &&
      onboardingComplete) {
    return AppRoutes.tests;
  }
  if (data['route'] == AppRoutes.notifications &&
      data['type'] == 'guardian_alert' &&
      role == 'guardian') {
    return AppRoutes.notifications;
  }
  return null;
}
