import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileTransferManager {
  final RTCDataChannel dataChannel;

  /// 16 KiB chunks stay within common WebRTC SCTP message limits across browsers.
  static const int chunkSize = 16 * 1024;
  static const int maxBuffered = 512 * 1024;
  static const int bufferLowThreshold = 256 * 1024;
  static const Duration bufferWaitTimeout = Duration(seconds: 60);

  FileTransferManager(this.dataChannel);

  Future<void> sendFromBytes(
    Uint8List bytes,
    String name,
    void Function(double) onProgress,
  ) {
    return sendFromStream(
      _chunkBytes(bytes),
      bytes.length,
      name,
      onProgress,
    );
  }

  Future<void> sendFromStream(
    Stream<List<int>> stream,
    int totalSize,
    String name,
    void Function(double) onProgress,
  ) async {
    dataChannel.bufferedAmountLowThreshold = bufferLowThreshold;

    dataChannel.send(
      RTCDataChannelMessage(
        jsonEncode({"type": "meta", "name": name, "size": totalSize}),
      ),
    );

    // Give the peer a moment to handle meta before binary frames arrive.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    var sent = 0;
    var lastReportedProgress = -1.0;
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

    await for (final chunk in normalizeChunkStream(stream, chunkSize)) {
      await _waitForSendCapacity();

      dataChannel.send(RTCDataChannelMessage.fromBinary(chunk));
      sent += chunk.length;

      final progress = totalSize > 0 ? sent / totalSize : 1.0;
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

  Stream<Uint8List> _chunkBytes(Uint8List bytes) async* {
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize > bytes.length)
          ? bytes.length
          : offset + chunkSize;
      yield bytes.sublist(offset, end);
    }
  }

  Future<void> _waitForSendCapacity() async {
    while ((dataChannel.bufferedAmount ?? 0) > maxBuffered) {
      final completer = Completer<void>();
      Timer? pollTimer;

      void release() {
        pollTimer?.cancel();
        dataChannel.onBufferedAmountLow = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      dataChannel.onBufferedAmountLow = (_) => release();
      pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if ((dataChannel.bufferedAmount ?? 0) <= maxBuffered) {
          release();
        }
      });

      if ((dataChannel.bufferedAmount ?? 0) <= maxBuffered) {
        release();
      }

      await completer.future.timeout(bufferWaitTimeout, onTimeout: release);
    }
  }
}

/// Re-chunks arbitrary stream piece sizes into fixed frames for the data channel.
Stream<Uint8List> normalizeChunkStream(
  Stream<List<int>> input,
  int frameSize,
) async* {
  var carry = BytesBuilder(copy: false);

  await for (final piece in input) {
    carry.add(piece);
    while (carry.length >= frameSize) {
      final all = carry.takeBytes();
      yield Uint8List.fromList(all.sublist(0, frameSize));
      if (all.length > frameSize) {
        carry.add(all.sublist(frameSize));
      }
    }
  }

  if (carry.length > 0) {
    yield Uint8List.fromList(carry.takeBytes());
  }
}
