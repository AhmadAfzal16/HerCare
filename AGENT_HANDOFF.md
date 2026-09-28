# HerCare - AI Agent Handoff Document

**Date:** 2026-09-23
**Project:** HerCare (Postpartum Depression Screening & Support App)
**Stack:** Flutter (Frontend), Node.js/Express (Backend), PostgreSQL (Database)

This document is intended for the next AI Agent taking over development. It contains the exact current state of the project, including what has been completed, what is remaining based on the scope document, and git instructions.

---

## 1. What Has Been Accomplished

### **Module 1: User Registration, Onboarding & Consent**
- **Status:** **COMPLETED**
- **Backend:** `users`, `refresh_tokens`, and `onboarding_data` tables exist (`001_initial_schema.sql`).
- **Frontend:** Language selection (Urdu/English), Splash Screen, Auth screens, Onboarding Wizard collecting demographic and obstetric data matching the PERI_DEP ML dataset.
- **Account flow:** Language -> registration details -> account type (mother or guardian) -> server account creation. Mothers then complete onboarding; guardians enter their separate support workspace immediately.
- **Server-authoritative onboarding:** `PUT /api/v1/onboarding` validates and stores the mother's complete profile and consent choices transactionally, then marks onboarding complete. Splash and login use the server's role and onboarding state instead of trusting a device-only flag.
- Guardian accounts are created with onboarding complete because the clinical mother onboarding form does not apply to them. Mother accounts start incomplete and no guardian-sharing consent is pre-granted.

### **Module 2: Guardian/Spouse Link & Reports System**
- **Status:** **PRODUCTION-HARDENED FOUNDATION** (real clinical aggregation depends on Modules 3, 5, and 8)
- **Backend:** 
  - Schema: `guardian_links`, `guardian_alerts`, `health_reports` (`002_guardian_reports.sql`).
  - Implemented `guardian.service.js` and `guardian.controller.js`.
  - **Invite security:** Implemented cryptographically secure 12-character codes, strict 24-hour server-side expiry, endpoint rate limiting, transactional single-use acceptance, and database uniqueness constraints for active/pending links.
  - Guardian access now requires Tier 2 consent. Revocation takes effect immediately, and guardians can access only aggregate report fields.
  - Report periods are normalized server-side (daily, Monday-Sunday weekly, calendar monthly) and upserted idempotently to prevent duplicates.
  - The migration runner records checksums in `schema_migrations` so deployment migrations are ordered and repeatable.
  - Reports intentionally return `insufficient_data` with null clinical metrics until EPDS, mood, and sleep modules provide real measurements. Never replace this with demo clinical scores in production.
- **Frontend:** 
  - Created `GuardianProvider` and `GuardianService` for API communication.
  - Fixed a critical "Null check operator" bug by ensuring `GuardianService` fetches the JWT token securely via `LocalStorageService` (key: `access_token`) rather than raw `SharedPreferences`.
  - Created role-aware `GuardianLinkScreen` (mothers share; guardians enter codes).
  - Created `GuardianDashboardScreen` (shows mother's EPDS score, mood trends, and tips).
  - Created `ReportScreen` (Daily, Weekly, Monthly report snapshots with per-period caching and honest empty-data states).
  - Guardian networking now uses the shared Dio client, including token refresh, timeouts, deployment URL configuration, and HTTPS enforcement in release builds.
  - Wired navigation from `HomeScreen` ("Your Support" card) and `SettingsScreen` ("Guardian & Family" menu item).
  - Addressed syntax errors (missing `GestureDetector` closing parenthesis) and implemented error-handling UI in the Share Code tab to display backend errors if they occur.
  - Added a dedicated `GuardianHomeScreen`, distinct from the mother's home, with secure connection status, aggregate health snapshot, reports, real-time alert state, recommendations, and an explicit privacy boundary for journals and conversations.
  - Registration, login, splash/session restoration, and role-aware home routing now consistently send guardians to the guardian workspace and mothers to onboarding/home as appropriate.

### **Global UI/UX & Localization**
- **Urdu/RTL Support:** Full RTL layout handling for Urdu text. Fixed 1.3 pixel overflow issues in `MoodHeroCard` and `WellbeingGrid` caused by the `Nastaliq` font by adjusting `Wrap` and `childAspectRatio` properties.
- **Dark Mode:** System-wide dynamic dark mode implemented successfully. 

---

## 2. What Is Remaining (According to Scope)

The following modules from the `hercare_scope_extracted.txt` document have NOT been started and must be implemented next:

- **Module 3: EPDS Screening & Assessment Engine**
  - Interactive 10-question assessment (Urdu/English).
  - Auto-scoring (0-30) and categorization.
- **Module 4: ML-Powered Risk Prediction & Notification Monitoring**
  - Connect to the PERI_DEP trained prediction model.
  - Implement Android-specific telemetry (`NotificationListenerService`, `UsageStatsManager`).
- **Module 5: Multi-Modal Mood Detection & Journaling**
  - Daily mood emoji scale, text/voice journals.
- **Module 6: AI Emotional Support Chatbot (Hum-Raaz — 24/7)**
  - Gemini API integration with CBT prompt engineering and self-harm detection.
- **Module 7: Secure In-App Chat with Sentiment Analysis**
- **Module 8: Sleep Tracker & Digital Wellbeing Monitor**
- **Module 9: Guided Breathing, Meditation, CBT Exercises & Therapeutic Games**
- **Module 10: Emergency & Crisis Intervention System**
- **Module 11: Islamic & Cultural Content Recommendation & Psychoeducation Engine**
- **Module 12: Anonymous Peer Support Community**

---

## 3. Git Version Control Instructions

To push all the recent changes to a new branch in your GitHub repository, the user (or the next AI agent) should execute the following commands in the terminal from the root `HerCare` directory:

```bash
# 1. Navigate to the root directory (if not already there)
cd C:\Users\WSPL\Downloads\HerCare

# 2. Check the current git status
git status

# 3. Create and switch to a new branch for the Guardian module
git checkout -b feature/module2-guardian-link

# 4. Stage all the modified and new files (both flutter and backend)
git add .

# 5. Commit the changes with a descriptive message
git commit -m "feat: implement Module 2 Guardian Link & Reports system, fix Urdu RTL layouts, and secure code generator"

# 6. Push the new branch to GitHub
git push -u origin feature/module2-guardian-link
```

---

## 4. Environment & Testing Notes for the Next Agent
- **JWT Secrets / Backend:** The backend MUST be started with the `.env` file (e.g., `node --env-file=.env src/app.js`), otherwise `jwt.js` will throw an error and the backend will crash, causing silent frontend failures if errors aren't caught.
- **API Base URL:** In debug builds the frontend falls back to `http://localhost:5000/api/v1`. On a physical Android device, run `adb reverse tcp:5000 tcp:5000`; on an Android emulator use `http://10.0.2.2:5000/api/v1` via `API_BASE_URL`. A deployed app must point to the deployed HTTPS API, never localhost.
- **Production API URL:** Build with `--dart-define=API_BASE_URL=https://your-api.example.com/api/v1`. Release builds reject non-HTTPS API URLs.
- **Token Storage:** The frontend uses `flutter_secure_storage` to store JWT tokens. Always use `LocalStorageService().getSecureString(AppConstants.accessTokenKey)` when building new API services. Do not use raw `SharedPreferences` for tokens.
- **Database deployment:** Run `npm run migrate` from `hercare_backend` before starting a new release. Applied migration files must never be edited after deployment because checksum validation will stop the release.
- **Verification:** `npm test` covers invite-code entropy, risk mapping, canonical period calculation, and onboarding validation. ESLint and all 10 backend tests pass. Dart analysis has no compile errors; existing project-wide warning/informational deprecation/style findings remain.
- **Local runtime status:** PostgreSQL was temporarily unavailable during early debugging, which caused the app's generic connection message. At the final 2026-09-23 verification both `/health` and `/health/ready` succeeded, and the updated API was running on port 5000. Authentication and Guardian requests still require PostgreSQL to remain running.
