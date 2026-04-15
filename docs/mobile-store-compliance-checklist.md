# Mobile Store Compliance Checklist (Apple + Google)

Last updated: April 15, 2026

## Implemented in code

- In-app account deletion path (mobile sidebar):
  - `Tools & account` -> `Session` -> `Delete account & data`
- Outside-app account deletion path:
  - `/legal/account-deletion`
  - `/web/account` -> `Delete account and data`
- Backend account deletion endpoint:
  - `POST /me/account/delete`
- Privacy policy URL:
  - `/legal/privacy`
- Terms URL:
  - `/legal/terms`
- Android manifest hardening:
  - `android.permission.INTERNET` in release manifest
  - `android.permission.POST_NOTIFICATIONS` declared
- iOS network policy hardening:
  - removed broad `NSAllowsArbitraryLoads`
  - kept `NSAllowsLocalNetworking` for local development
- iOS privacy manifest:
  - `ios/Runner/PrivacyInfo.xcprivacy` added with `UserDefaults` required-reason declaration

## Still required in App Store Connect / Play Console

- Apple App Store Connect
  - Set the public Privacy Policy URL to `/legal/privacy` on your production domain.
  - Complete App Privacy Nutrition Labels accurately.
  - Confirm app metadata and review notes include test credentials when needed.

- Google Play Console
  - Complete Data safety (including Data deletion section) with accurate declarations.
  - Set Privacy Policy URL to `/legal/privacy` on your production domain.
  - Set Account deletion web URL to `/legal/account-deletion`.
  - Ensure target API level meets current Play requirement before release.

## Release validation pass before submission

- Verify account deletion from:
  - iOS app UI
  - Android app UI
  - Web account page (`/web/account`)
  - Subscription cancellation guidance is visible before deletion
- Verify legal pages load publicly without auth:
  - `/legal/privacy`
  - `/legal/terms`
  - `/legal/account-deletion`
- Verify mobile app API base URL in production uses HTTPS.
