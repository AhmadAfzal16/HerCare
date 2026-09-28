/// UserModel — core user data returned from the API.
/// Intentionally lightweight; no sensitive data stored in the model.
class UserModel {
  final String id;
  final String phone;
  final String role;
  final String language;
  final bool onboardingComplete;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.phone,
    required this.role,
    required this.language,
    required this.onboardingComplete,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:                 json['id'] as String,
      phone:              json['phone'] as String,
      role:               json['role'] as String? ?? 'mother',
      language:           json['language'] as String? ?? 'en',
      onboardingComplete: json['onboarding_complete'] as bool? ?? false,
      createdAt: DateTime.tryParse(
            json['created_at'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':                  id,
    'phone':               phone,
    'role':                role,
    'language':            language,
    'onboarding_complete': onboardingComplete,
    'created_at':          createdAt.toIso8601String(),
  };

  bool get isMother   => role == 'mother';
  bool get isGuardian => role == 'guardian';
}
