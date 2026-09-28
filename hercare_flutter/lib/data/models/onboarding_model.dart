// ─── Enums ────────────────────────────────────────────────────────────────────

enum DeliveryMethod { vaginal, cesarean }

enum BabyGender { male, female }

enum HouseholdType { nuclear, joint }

enum SupportSource { husband, motherInLaw, siblings, none }

// ─── Onboarding Data Model ────────────────────────────────────────────────────

/// Accumulates data across all 4 onboarding steps.
/// Designed to serialize to JSON for persistence and API submission.
///
/// Field naming convention matches PERI_DEP dataset columns
/// to facilitate direct ML feature extraction (Phase 1 M4).
class OnboardingData {
  OnboardingData();

  // Step 1 – Personal
  String? fullName;
  int? age;
  String? educationLevel;
  String? city;
  int? monthsSinceBirth;

  // Step 2 – Obstetric
  DeliveryMethod? deliveryMethod;
  int parity = 0;
  BabyGender? babyGender;
  bool hasPreeclampsia = false;
  bool hasPostpartumHemorrhage = false;
  bool hasPretermBirth = false;
  bool hasGestationalDiabetes = false;

  // Step 3 – Family Support
  HouseholdType? householdType;
  String? incomeRange;
  SupportSource? primarySupport;

  // Step 4 – Consent
  bool consentTier1 = true; // Required; always true
  bool consentTier2 = true; // Default opt-in (recommended)
  bool consentTier3 = false; // Default opt-out (optional)

  /// Serializes to a flat JSON map for:
  ///   - Local persistence in SharedPreferences
  ///   - Transmission to POST /api/v1/users/onboarding
  ///   - ML model feature ingestion
  Map<String, dynamic> toJson() {
    return {
      // Personal
      'full_name': fullName,
      'age': age,
      'education_level': educationLevel,
      'city': city,
      'months_since_birth': monthsSinceBirth,

      // Obstetric (ML features)
      'delivery_method': deliveryMethod?.name,
      'parity': parity,
      'baby_gender': babyGender?.name,
      'has_preeclampsia': hasPreeclampsia,
      'has_postpartum_hemorrhage': hasPostpartumHemorrhage,
      'has_preterm_birth': hasPretermBirth,
      'has_gestational_diabetes': hasGestationalDiabetes,

      // Family
      'household_type': householdType?.name,
      'income_range': incomeRange,
      'primary_support': primarySupport?.name,

      // Consent
      'consent_tier1': consentTier1,
      'consent_tier2': consentTier2,
      'consent_tier3': consentTier3,
    };
  }

  /// Reconstructs from a stored JSON map.
  factory OnboardingData.fromJson(Map<String, dynamic> json) {
    final data = OnboardingData();
    data.fullName = json['full_name'] as String?;
    data.age = json['age'] as int?;
    data.educationLevel = json['education_level'] as String?;
    data.city = json['city'] as String?;
    data.monthsSinceBirth = json['months_since_birth'] as int?;

    final dm = json['delivery_method'] as String?;
    data.deliveryMethod = dm != null
        ? DeliveryMethod.values.firstWhere((e) => e.name == dm)
        : null;

    data.parity = (json['parity'] as int?) ?? 0;

    final bg = json['baby_gender'] as String?;
    data.babyGender = bg != null
        ? BabyGender.values.firstWhere((e) => e.name == bg)
        : null;

    data.hasPreeclampsia = (json['has_preeclampsia'] as bool?) ?? false;
    data.hasPostpartumHemorrhage =
        (json['has_postpartum_hemorrhage'] as bool?) ?? false;
    data.hasPretermBirth = (json['has_preterm_birth'] as bool?) ?? false;
    data.hasGestationalDiabetes =
        (json['has_gestational_diabetes'] as bool?) ?? false;

    final ht = json['household_type'] as String?;
    data.householdType = ht != null
        ? HouseholdType.values.firstWhere((e) => e.name == ht)
        : null;

    data.incomeRange = json['income_range'] as String?;

    final ps = json['primary_support'] as String?;
    data.primarySupport = ps != null
        ? SupportSource.values.firstWhere((e) => e.name == ps)
        : null;

    data.consentTier1 = (json['consent_tier1'] as bool?) ?? true;
    data.consentTier2 = (json['consent_tier2'] as bool?) ?? true;
    data.consentTier3 = (json['consent_tier3'] as bool?) ?? false;

    return data;
  }
}
