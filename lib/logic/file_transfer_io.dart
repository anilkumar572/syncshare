import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'file_transfer_manager.dart';

Future<void> sendFileFromDisk(
  RTCDataChannel channel,
  String path,
  void Function(double) onProgress,
) async {
  final file = File(path);
  final manager = FileTransferManager(channel);
  final totalSize = await file.length();
  final name = file.path.split('/').last;

  await manager.sendFromStream(
    file.openRead(0, FileTransferManager.chunkSize),
    totalSize,
    name,
    onProgress,
  );
}
