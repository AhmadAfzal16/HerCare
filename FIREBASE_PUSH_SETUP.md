# HerCare Firebase Push Setup

Firebase Cloud Messaging is listed as no-cost in [Firebase pricing](https://firebase.google.com/pricing), checked 12 October 2026. This does not make backend hosting, phone calls, SMS authentication or clinician services free. HerCare
does not store Firebase credentials in source control and remains runnable when
push is not configured.

## 1. Create the Firebase project

1. Create a project in the Firebase console and keep it on the **Spark** plan.
2. Before registering apps, choose permanent Android and iOS identifiers. The
   current Android application ID is `com.hercare.app`; keep the Firebase
   registration and `google-services.json` package name consistent with it.
3. Register the Android app. Register the iOS app separately if iOS deployment
   is required.
4. Copy the API key, app ID, project ID, messaging sender ID, and storage bucket
   from the Firebase app configuration.

Android initializes from `android/app/google-services.json`. This file contains
Firebase app identifiers, not an Admin private key. Backend credentials remain
deployment secrets and must never be committed.

## 2. Configure the backend

Deploy the backend with Node.js 22 or newer (required by the current Firebase
Admin SDK).

Install production packages with `npm ci --omit=dev --omit=optional`; the
Firebase Storage/Firestore optional packages are not used by HerCare messaging.

Create a Firebase Admin service account in Firebase project settings. Store its
JSON as a deployment secret, preferably base64 encoded. Then configure:

```text
FIREBASE_PUSH_ENABLED=true
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT_JSON=base64-encoded-service-account-json
PUSH_TOKEN_ENCRYPTION_KEY=32-byte-random-key-as-base64
```

Keep `PUSH_TOKEN_ENCRYPTION_KEY` stable after deployment. Changing it makes
existing encrypted device tokens unreadable, requiring users to sign in again.

Run the database migration once per environment:

```text
npm run migrate
```

## 3. Build the Flutter app

Android only needs the deployed HTTPS API URL because its Firebase application
configuration is compiled from `google-services.json`:

```text
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

For iOS, also pass `FIREBASE_IOS_BUNDLE_ID` and upload an APNs authentication
key in Firebase project settings. Firebase is free, but distributing iOS push
notifications requires Apple's developer provisioning.

## 4. Verify on two physical devices

1. Install the configured build on the mother and guardian phones.
2. Sign in on both, allow notification permission, and activate the Guardian Link.
3. Ensure the mother has enabled Tier 2 guardian sharing consent.
   For urgent crisis alerts since M10, she must also explicitly confirm that the
   current linked guardian is safe to contact in Immediate Help. This defaults
   off and does not carry to a replacement link. Routine aggregate sharing alone
   never authorizes an urgent disclosure.
4. Submit a controlled test in a non-production environment that creates a
   guardian alert.
5. Confirm the guardian receives a generic lock-screen notification and that
   opening it shows the authenticated alerts page.

Notification bodies never include journal text, chat messages, transcripts, or
other raw private content. Delivery failures are retained in the database
outbox and retried; revoked links and withdrawn consent cancel delivery.
Urgent alerts also require an unresolved, owned crisis event and the original
safe link; closure/withdrawal cancels pending work. Provider acceptance is not a
delivery or emergency-response guarantee, and a previously delivered notice
cannot be recalled. See `M10_CRISIS_IMPLEMENTATION_AND_DEPLOYMENT.md` for the
current contact, privacy and staging acceptance requirements.

## 5. M10 sound rollout (12 October 2026)

Urgent crisis/severe-risk pushes now carry `urgent: "true"`, Android channel
`hercare_urgent_v1` and bundled sound `hercare_urgent`. Ordinary updates and
screening reminders keep their own channels. Open the updated Android app once
to register the new channel before checking background delivery. Existing old
builds do not contain the new sound; update guardian phones as part of rollout.

Permission, user channel settings, volume and Do Not Disturb are respected.
No critical-alert/DND bypass, guaranteed instant arrival or emergency response
is promised. Android foreground uses the same generic native urgent notification;
iOS retains default APNs background sound and its existing foreground in-app
notice, not a custom foreground siren.

Verify real foreground/background/terminated delivery, taps, logout/account
switch, disabled notifications, channel changes and revoked safe links in staging.
Device registration is account-bound via `X-Notification-Account-Id` and serialized
before logout revocation. It remains separate from the opt-in local attention
chime, which sends no notification. M10's directory/location feature requires no
Maps/Places API key and never uploads the phone's approximate location.
