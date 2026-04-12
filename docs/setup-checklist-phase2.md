# Phase 2 Setup Checklist (External Services)

This checklist covers everything that still needs configuration outside the codebase.

## 1) Control API Environment

Set these in your control-api runtime environment:

- Required baseline:
  - `DATABASE_URL`
  - `JWT_SECRET`
  - `BETTER_AUTH_SECRET`
  - `INTERNAL_GATEWAY_SECRET`
- Stripe (already supported):
  - `STRIPE_SECRET_KEY`
  - `STRIPE_WEBHOOK_SECRET`
  - `STRIPE_PRO_PRICE_ID`
- RevenueCat (new):
  - `REVENUECAT_WEBHOOK_AUTH`
  - Optional product mapping:
    - `REVENUECAT_PRODUCT_PLAN_MAP` JSON (example: `{"nomade_pro_monthly":"pro","nomade_pro_yearly":"pro"}`)
- Firebase push (new, optional):
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_CLIENT_EMAIL`
  - `FIREBASE_PRIVATE_KEY` (escaped newlines as `\n`)

If RevenueCat/Firebase env vars are missing, the app still runs and those features stay disabled.

## 2) RevenueCat Console

1. Create products that match your mobile plans.
2. Configure webhook URL:
   - `POST https://<your-control-api>/billing/revenuecat/webhook`
3. Configure webhook auth header value to match `REVENUECAT_WEBHOOK_AUTH`.
4. Ensure your mobile app sets RevenueCat `app_user_id` to Nomade `user.id` (critical for entitlement mapping).
5. Optionally map product IDs to plan codes via `REVENUECAT_PRODUCT_PLAN_MAP`.

## 3) Firebase Project (Push)

1. Create/select Firebase project.
2. Enable Cloud Messaging API.
3. Create service account credentials with permission to send FCM messages.
4. Copy service account values into env:
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_CLIENT_EMAIL`
   - `FIREBASE_PRIVATE_KEY`
5. For iOS:
   - Upload APNs key/cert in Firebase project settings.
6. For Android:
   - Configure application package in Firebase and FCM.

Without this config, push delivery is skipped but app flows keep working.

## 4) Mobile Native Bridge Completion

Current bridge status:

- iOS `nomade/runtime_status` is implemented (ActivityKit start/update/end).
- iOS `nomade/native_notifications` now captures native token state, but backend registration requires FCM token format.
- Android native channels are still no-op.

To fully enable native push + live status:

1. Finish push token provider alignment:
   - iOS must return an FCM registration token for backend `provider: "fcm"` (APNs-only token is insufficient).
   - Android `nomade/native_notifications` still needs real token implementation.
2. Complete Xcode Live Activity wiring:
   - Widget extension target with Live Activity UI.
   - Runner capabilities/signing for Push Notifications + Background remote notifications.
3. Build mobile app with:
   - `--dart-define=NOMADE_ENABLE_NATIVE_NOTIFICATIONS=true`

If you do not enable this flag or native bridge logic, app behavior remains unchanged (no regressions).

Detailed Xcode steps for iOS Live Activities are in `docs/ios-live-activities-xcode-todo.md`.

## 5) CI/CD + Distribution

1. npm publish:
   - Add `NPM_TOKEN` in GitHub Actions secrets.
   - Tag release `v*` to trigger `publish-npm.yml`.
2. Docker publish (already separate):
   - Keep existing Docker workflow secrets/tokens unchanged.
3. SaaS domain:
   - Ensure DNS + TLS for `nomade.d1.guillaumeclaverie.com`.

## 6) Entitlement Policy Decisions

Free defaults are now enforced in backend:

- `maxAgents = 1`
- `features.tunnels = false`
- `features.pushNotifications = false`
- `features.deferredTurns = false`

Before release, confirm paid plan policy:

- Which plan codes exist (`pro`, `paid`, etc.)
- Final `PAID_MAX_AGENTS` value
- RevenueCat product-to-plan mapping
