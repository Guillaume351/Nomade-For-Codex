# Nomade Mobile (Flutter)

This app now includes a cross-platform conversation UI scaffold for:
- Device code login flow
- Pairing code generation
- Conversation list + turn timeline
- Streaming Markdown output
- Diff rendering per turn
- Running/completed/interrupted turn states

## Run
```bash
cd apps/mobile
fvm flutter pub get
fvm flutter run -d macos
```

Other supported targets:
```bash
fvm flutter run -d chrome
fvm flutter run -d <ios-device-id>
```

Use Android emulator host alias (`10.0.2.2`) if needed instead of `localhost`.

You can override API URL:
```bash
fvm flutter run -d macos --dart-define NOMADE_API_URL=http://localhost:8080
```
