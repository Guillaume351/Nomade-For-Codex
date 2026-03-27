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
flutter pub get
flutter run
```

Use Android emulator host alias (`10.0.2.2`) if needed instead of `localhost`.

You can override API URL:
```bash
flutter run --dart-define NOMADE_API_URL=http://localhost:8080
```
