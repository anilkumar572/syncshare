import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<void> sendFileFromDisk(
  RTCDataChannel channel,
  String path,
  void Function(double) onProgress,
) {
  throw UnsupportedError('sendFileFromDisk is only supported on IO platforms');
}
