// Smoke test for the ShareSync app.
//
// The main screen initializes WebRTC/Firebase plugins that are not available
// in the plain `flutter test` VM, so this test verifies the top-level app
// widget can be constructed rather than pumping the full widget tree.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sharesyncapp/main.dart';

void main() {
  test('ShareSyncApp can be constructed', () {
    expect(const ShareSyncApp(), isA<Widget>());
  });
}
