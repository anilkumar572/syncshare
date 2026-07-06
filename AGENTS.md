# AGENTS.md

## Cursor Cloud specific instructions

ShareSync is a single Flutter app (`sharesyncapp`) — a peer-to-peer file transfer
tool. Two devices connect via a 6-digit room code; **Cloud Firestore is used only
as the WebRTC signaling channel** (project `sharesync-56711`, live/cloud — no local
emulator is configured), and files then transfer directly peer-to-peer over a WebRTC
data channel using a public Google STUN server. Standard run/build/test commands live
in the Flutter tooling and `.github/workflows/deploy.yml`; the notes below only cover
non-obvious caveats.

### Toolchain
- The Flutter SDK is installed at `~/flutter` and added to `PATH` via `~/.bashrc`
  (Flutter 3.44.4 / Dart 3.12.2, which satisfies `pubspec.yaml`'s `sdk: ^3.10.7`).
  If `flutter` is not on `PATH` in a fresh shell, run `export PATH="$HOME/flutter/bin:$PATH"`.
- Only the **web** toolchain (Chrome) is available in this VM. `flutter doctor` reports
  the Android SDK and Linux desktop toolchain (ninja/GTK) as missing — this is expected;
  target the web platform for running/testing.

### Running / testing
- Lint: `flutter analyze` (pre-existing warnings in `lib/servises/background_handler.dart`
  and `test/widget_test.dart` are unrelated to setup; no errors).
- Tests: `flutter test`.
- Run in dev mode (web): `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080`.
  The first launch compiles for ~20s before printing `lib/main.dart is being served at ...`;
  wait for that line before opening the browser. Then open `http://localhost:8080` in Chrome.
- **End-to-end testing needs two browser tabs/instances**: one tab clicks "Create a room"
  to get a 6-digit code (this writes the WebRTC offer to live Firestore), the second tab
  enters that code and clicks "Join room". Both must reach the "Connected" / "Send a file"
  view before a file can be sent. This requires outbound network access to Firebase and
  the Google STUN server (`stun:stun.l.google.com:19302`).

### Firebase / deployment
- Running the client needs **no secrets** — the Firebase web config is committed in
  `lib/firebase_options.dart`.
- The `npm` layer (`package.json`) exists only for `firebase-tools` deploy scripts
  (`npm run deploy*`), which require a Firebase service account credential
  (e.g. `FIREBASE_SERVICE_ACCOUNT_SHARESYNC_56711`). Deployment is not needed for local dev.
