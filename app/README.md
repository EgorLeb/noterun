# App

Flutter app for Android. Requires Flutter 3.x ([install guide](https://docs.flutter.dev/get-started/install)), Android SDK ([install guide](https://developer.android.com/studio)), and Java 17 ([download](https://adoptium.net/temurin/releases/?version=17), used by Gradle to build the APK — not installed automatically).

## Setup

```bash
flutter pub get
```

## Build

Debug build (for development and testing):

```bash
flutter build apk --debug
```

Release build (for users):

```bash
flutter build apk --release
```

The APK ends up at `build/app/outputs/flutter-apk/app-release.apk`.

## Build parameters

Pass with `--dart-define=KEY=value`, can combine multiple.

### API_HOST

Address of the backend server. Default: `http://89.169.171.219:8000`.

```bash
flutter build apk --release --dart-define=API_HOST=http://YOUR_SERVER_IP:8000
```

Without this the app uses the default address. Account features (leaderboard, progress sync, AI analysis) won't work if the server is unreachable, but the rest of the app works offline.

## Permissions

The app requires these Android permissions (already set in `AndroidManifest.xml`):

- `RECORD_AUDIO` — microphone for note detection
- `VIBRATE` — vibration on miss
- `INTERNET` — server communication