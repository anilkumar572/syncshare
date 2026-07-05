import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sharesyncapp/utils/web_download.dart';

class FileReceiverManager {
  final BytesBuilder _webBuffer = BytesBuilder(copy: false);
  int _receivedSize = 0;
  int _totalSize = 0;
  String? _fileName;
  double _lastReportedProgress = -1;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  final void Function(double progress, String status, String? filePath)
      onStatusUpdate;

  FileReceiverManager({required this.onStatusUpdate});

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
      _webBuffer.clear();
      onStatusUpdate(0.0, 'Starting download: $_fileName', null);
    } else if (data['type'] == 'eof') {
      final bytes = _webBuffer.toBytes();

      if (_totalSize > 0 && _receivedSize != _totalSize) {
        onStatusUpdate(
          1.0,
          'Warning: size mismatch ($_receivedSize / $_totalSize bytes)',
          _fileName,
        );
        return;
      }

      triggerBrowserDownload(bytes, _fileName ?? 'download');
      onStatusUpdate(1.0, 'File downloaded!', _fileName);
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
