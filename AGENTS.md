# sharesyncapp

A Flutter P2P file-transfer app ("ShareSync"). Peers exchange large files over a
WebRTC data channel; Firebase Firestore is used only for signaling (exchanging
SDP offers/answers and ICE candidates via the `rooms` collection). Entry point
is `lib/main.dart` → `TransferScreen` (`lib/screens/transfer_screen.dart`).

## Cursor Cloud specific instructions

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
- **`flutter test` currently fails**: `test/widget_test.dart` is the unmodified
  Flutter "counter" boilerplate and does not match this app (it looks for a
  counter that doesn't exist). This is a pre-existing code issue, not an
  environment problem — the test runner itself works.
- **`flutter analyze` passes** (exit 0) but reports pre-existing warnings/infos
  (e.g. runtime packages declared under `dev_dependencies` in `pubspec.yaml`,
  unused imports). These are not environment issues.
- **Firebase / signaling**: `lib/firebase_options.dart` ships real config for
  the `sharesync-56711` Firebase project, so the web app initializes Firebase on
  load. Creating a room writes to Firestore; an actual end-to-end file transfer
  needs a second peer to join the room and working STUN/TURN connectivity.
