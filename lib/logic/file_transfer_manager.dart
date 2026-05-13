import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileTransferManager {
  final RTCDataChannel dataChannel;
  static const int CHUNK_SIZE = 64 * 1024; // 64KB

  FileTransferManager(this.dataChannel);

  // SENDER LOGIC
  Future<void> sendLargeFile(File file, Function(double) onProgress) async {
    int totalSize = await file.length();
    String name = file.path.split('/').last;

    // Send Metadata
    dataChannel.send(RTCDataChannelMessage(jsonEncode({"type": "meta", "name": name, "size": totalSize})));

    // Stream from Disk to WebRTC
    Stream<List<int>> stream = file.openRead();
    int sent = 0;

    await for (var chunk in stream) {
      // BACKPRESSURE: Wait if WebRTC buffer is full (> 1MB)
      while (dataChannel.bufferedAmount! > 1024 * 1024) {
        await Future.delayed(Duration(milliseconds: 30));
      }
      
      dataChannel.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(chunk)));
      sent += chunk.length;
      onProgress(sent / totalSize);
    }
    dataChannel.send(RTCDataChannelMessage(jsonEncode({"type": "eof"})));
  }
}