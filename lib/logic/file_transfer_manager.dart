import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileTransferManager {
  final RTCDataChannel dataChannel;

  static const int chunkSize = 64 * 1024;
  static const int maxBuffered = 4 * 1024 * 1024;
  static const int bufferLowThreshold = 2 * 1024 * 1024;

  FileTransferManager(this.dataChannel);

  Future<void> sendLargeFile(File file, Function(double) onProgress) async {
    final totalSize = await file.length();
    final name = file.path.split('/').last;

    dataChannel.bufferedAmountLowThreshold = bufferLowThreshold;

    dataChannel.send(
      RTCDataChannelMessage(
        jsonEncode({"type": "meta", "name": name, "size": totalSize}),
      ),
    );

    var sent = 0;
    var lastReportedProgress = -1.0;
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

    await for (final chunk in file.openRead(0, chunkSize)) {
      await _waitForSendCapacity();

      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      dataChannel.send(RTCDataChannelMessage.fromBinary(bytes));
      sent += bytes.length;

      final progress = sent / totalSize;
      final now = DateTime.now();
      if (progress >= 1.0 ||
          progress - lastReportedProgress >= 0.01 ||
          now.difference(lastProgressUpdate).inMilliseconds >= 200) {
        lastReportedProgress = progress;
        lastProgressUpdate = now;
        onProgress(progress);
      }
    }

    onProgress(1.0);
    dataChannel.send(RTCDataChannelMessage(jsonEncode({"type": "eof"})));
  }

  Future<void> _waitForSendCapacity() async {
    while ((dataChannel.bufferedAmount ?? 0) > maxBuffered) {
      final completer = Completer<void>();

      void onLow(int currentAmount) {
        dataChannel.onBufferedAmountLow = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      dataChannel.onBufferedAmountLow = onLow;

      if ((dataChannel.bufferedAmount ?? 0) <= maxBuffered) {
        dataChannel.onBufferedAmountLow = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      await completer.future;
    }
  }
}
