import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Streams a picked file over a WebRTC data channel in small chunks.
///
/// Works on every platform: on native it consumes [PlatformFile.readStream]
/// (memory-efficient), and on web it falls back to [PlatformFile.bytes].
class FileTransferManager {
  FileTransferManager(this.dataChannel);

  final RTCDataChannel dataChannel;

  static const int chunkSize = 16 * 1024; // 16 KB
  static const int maxBufferedBytes = 1024 * 1024; // 1 MB backpressure limit

  Future<void> sendFile(
    PlatformFile file,
    void Function(double progress) onProgress,
  ) async {
    final totalSize = file.size;
    dataChannel.send(
      RTCDataChannelMessage(
        jsonEncode({'type': 'meta', 'name': file.name, 'size': totalSize}),
      ),
    );

    var sent = 0;
    Future<void> sendChunk(List<int> bytes) async {
      // Backpressure: wait if the send buffer is getting full.
      while ((dataChannel.bufferedAmount ?? 0) > maxBufferedBytes) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      dataChannel
          .send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)));
      sent += bytes.length;
      onProgress(totalSize > 0 ? sent / totalSize : 0.0);
    }

    Future<void> sendAll(List<int> data) async {
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        await sendChunk(data.sublist(i, end));
      }
    }

    if (file.readStream != null) {
      await for (final data in file.readStream!) {
        await sendAll(data);
      }
    } else if (file.bytes != null) {
      await sendAll(file.bytes!);
    } else {
      throw Exception('No readable file data available');
    }

    dataChannel.send(RTCDataChannelMessage(jsonEncode({'type': 'eof'})));
  }
}
