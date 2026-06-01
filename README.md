# NoteRun

Piano learning app with real-time note detection using ML.

```
noterun/
├── app/      # Flutter app (Android)
└── server/   # FastAPI backend
```

---

## App

Requires Flutter 3.x and Android SDK.

```bash
cd app
flutter pub get
```

Build with your server address:

```bash
flutter build apk --release --dart-define=API_HOST=http://YOUR_SERVER_IP:8000
```

Skip `--dart-define` for local development — the app will use the default host. Account-dependent features (leaderboard, AI analysis, progress sync) won't work but everything else does.

---

## Server

See [server/README.md](server/README.md).
