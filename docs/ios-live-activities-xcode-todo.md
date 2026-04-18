# iOS Live Activities: Xcode TODO

This checklist is the remaining Xcode work needed for Live Activities to appear on iPhone.

## 1) Verify minimum versions

1. In Xcode, open `apps/mobile/ios/Runner.xcworkspace`.
2. Select target `Runner` -> `General`.
3. Confirm `Deployment Info` minimum iOS version is `16.1` or above for Live Activities support.
4. If you must keep lower deployment target (current project uses iOS 15.5), keep runtime checks in code and test Live Activities only on iOS 16.1+ devices.

## 2) Add Widget Extension target (required)

1. `File` -> `New` -> `Target...`.
2. Choose `Widget Extension`.
3. Product name example: `NomadeLiveActivityExtension`.
4. Ensure `Include Live Activity` is checked.
5. Finish and activate scheme if prompted.

Notes:
- This target is required. Without it, ActivityKit requests can succeed/fail silently and no UI is rendered.
- Keep generated Activity attributes/content state types shared between app and extension.

## 3) Enable capabilities on Runner target

1. Select target `Runner` -> `Signing & Capabilities`.
2. Add capability: `Push Notifications`.
3. Add capability: `Background Modes`.
4. Inside `Background Modes`, enable `Remote notifications`.
5. Ensure signing team and provisioning profile are valid for device builds.

## 4) Confirm Info.plist keys

1. In `Runner/Info.plist`, confirm `NSSupportsLiveActivities = YES` (already added in repo).
2. Optional (only if you need frequent updates): add `NSSupportsLiveActivitiesFrequentUpdates = YES`.

## 5) APNs / push provider setup for remote updates

1. Apple Developer portal:
   - Create or use an APNs auth key for your app ID.
   - Ensure app ID has Push Notifications enabled.
2. Firebase Console:
   - Upload APNs key in project settings (Cloud Messaging) if using FCM relay.
3. App token source:
   - Backend currently accepts only `provider = "fcm"`.
   - Ensure your iOS app returns an FCM registration token (not only raw APNs token) for `/me/push/register`.

## 6) Device settings validation

1. On iPhone: `Settings` -> `Face ID & Passcode` -> `Live Activities` ON.
2. On iPhone: `Settings` -> your app -> `Live Activities` ON.
3. On iPhone: `Settings` -> your app -> `Notifications` allowed.
4. Test on physical device (not simulator only).

## 7) Runtime verification sequence

1. Build app normally (no extra `dart-define` required).
2. Start a turn in app and confirm `setRunningStatus` is invoked.
3. In Xcode console, look for ActivityKit errors.
4. Confirm Live Activity appears on Lock Screen / Dynamic Island.
5. Complete turn and confirm `clearRunningStatus` ends activity.

## 8) Common failure signatures

1. No widget extension target:
   - Live Activity never appears.
2. Missing signing/capabilities:
   - Activity request errors or push registration failures.
3. Push token mismatch:
   - backend marks registration invalid (`provider_rejected_token`).
4. Unsupported iOS version:
   - bridge no-ops by design below iOS 16.1.
