import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sharesyncapp/logic/received_file.dart';
import 'package:sharesyncapp/utils/web_download.dart';

class FileReceiverManager {
  final BytesBuilder _webBuffer = BytesBuilder(copy: false);
  int _receivedSize = 0;
  int _totalSize = 0;
  String? _fileName;
  Uint8List? _lastBytes;
  double _lastReportedProgress = -1;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  final void Function(double progress, String status, String? filePath)
      onStatusUpdate;
  final void Function(ReceivedFile file)? onFileReceived;
  final void Function(String name, int size)? onMeta;

  FileReceiverManager({
    required this.onStatusUpdate,
    this.onFileReceived,
    this.onMeta,
  });

  void handleIncomingMessage(RTCDataChannelMessage message) {
    if (message.isBinary) {
      _webBuffer.add(message.binary);
      _receivedSize += message.binary.length;
      _maybeReportProgress('Receiving...');
      return;
    }

    final data = jsonDecode(message.text) as Map<String, dynamic>;

    if (data['type'] == 'meta') {
      _fileName = data['name'] as String;
      _totalSize = data['size'] as int;
      _receivedSize = 0;
      _lastReportedProgress = -1;
      _lastBytes = null;
      _webBuffer.clear();
      onMeta?.call(_fileName!, _totalSize);
      onStatusUpdate(0.0, 'Receiving $_fileName...', null);
    } else if (data['type'] == 'eof') {
      final bytes = _webBuffer.toBytes();
      _lastBytes = bytes;

      if (_totalSize > 0 && _receivedSize != _totalSize) {
        onStatusUpdate(
          1.0,
          'Warning: size mismatch ($_receivedSize / $_totalSize bytes)',
          _fileName,
        );
        return;
      }

      final name = _fileName ?? 'download';
      triggerBrowserDownload(bytes, name);
      onStatusUpdate(1.0, 'File ready', _fileName);
      onFileReceived?.call(
        ReceivedFile(name: name, size: bytes.length, canRedownload: true),
      );
    }
  }

  void redownload() {
    final bytes = _lastBytes;
    if (bytes != null) {
      triggerBrowserDownload(bytes, _fileName ?? 'download');
    }
  }

  void _maybeReportProgress(String status) {
    final progress = _totalSize > 0 ? (_receivedSize / _totalSize) : 0.0;
    final now = DateTime.now();

    if (progress - _lastReportedProgress < 0.01 &&
        now.difference(_lastProgressUpdate).inMilliseconds < 200) {
      return;
    }

    _lastReportedProgress = progress;
    _lastProgressUpdate = now;
    onStatusUpdate(progress, status, null);
  }

  void dispose() {}
}
