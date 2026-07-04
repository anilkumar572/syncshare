# sharesyncapp

A Flutter P2P file-transfer app ("ShareSync"). Peers exchange large files over a
WebRTC data channel; Firebase Firestore is used only for signaling (exchanging
SDP offers/answers and ICE candidates via the `rooms` collection). Entry point
is `lib/main.dart` → `TransferScreen` (`lib/screens/transfer_screen.dart`).

## Cloud development environment notes

Standard Flutter project. Commands (`flutter pub get`, `flutter analyze`,
`flutter test`, `flutter run`) are the usual ones; see the Flutter docs if
unfamiliar.

- **SDK / platform**: This repo requires Dart `^3.10.7` (Flutter 3.44.x, bundled
  Dart 3.12.2). Flutter is installed at `~/flutter` and added to `PATH` via
  `~/.bashrc`. The update script only runs `flutter pub get`.
- **Best runnable target in the cloud VM is web** (Chrome is preinstalled;
  Android/iOS/desktop toolchains are not set up). Run with:
  `flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0`
  then open `http://localhost:8080` in Chrome. The first web build is slow
  (~compiles for a minute); subsequent hot reloads are fast.
- **`flutter test` passes**: `test/widget_test.dart` is a minimal smoke test
  (it only constructs the top-level `ShareSyncApp` widget, because the main
  screen initializes WebRTC/Firebase plugins that aren't available in the plain
  `flutter test` VM).
- **`flutter analyze` passes** (exit 0) but reports pre-existing warnings/infos
  (e.g. runtime packages declared under `dev_dependencies` in `pubspec.yaml`).
  These are not environment issues.
- **Signaling flow**: `SignalingService` (`lib/servises/singnaling_service.dart`)
  brokers the WebRTC handshake through Firestore. The caller (`createRoom`)
  publishes an offer and then listens for the callee's `answer` + ICE
  candidates; the callee (`joinRoom`) answers and listens for the caller's ICE
  candidates. Both sides must listen or the connection never completes.
- **File transfer is cross-platform**: on web it uses `PlatformFile.bytes` and
  triggers a browser download (`lib/logic/received_file_saver_web.dart`); on
  native it streams to disk via `path_provider`
  (`lib/logic/received_file_saver_io.dart`). The correct implementation is
  chosen with a conditional import in `received_file_saver.dart`.
- **Production Firestore rules block writes**: `lib/firebase_options.dart` points
  at the real `sharesync-56711` project, whose rules currently reject
  `rooms` writes (`[cloud_firestore/permission-denied]`). To exercise the full
  create-room → join → transfer flow locally, run the Firestore emulator
  (`firebase emulators:start --only firestore`, Java is installed) and
  temporarily add `FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8081);`
  after `Firebase.initializeApp(...)` in `lib/main.dart` (revert before
  committing). Two browser tabs on the same origin connect via loopback ICE
  without needing a TURN server.
