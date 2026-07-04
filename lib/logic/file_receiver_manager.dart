import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'received_file_saver.dart';

class FileReceiverManager {
  FileReceiverManager({required this.onStatusUpdate});

  /// Callback to update the UI: (progress 0..1, status text, saved location).
  final void Function(double progress, String status, String? location)
      onStatusUpdate;

  ReceivedFileSaver? _saver;
  int _receivedSize = 0;
  int _totalSize = 0;
  String? _fileName;

  Future<void> handleIncomingMessage(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      if (_saver == null) return;
      _saver!.addChunk(message.binary);
      _receivedSize += message.binary.length;
      final progress = _totalSize > 0 ? _receivedSize / _totalSize : 0.0;
      onStatusUpdate(progress, 'Receiving "$_fileName"…', null);
      return;
    }

    final data = jsonDecode(message.text) as Map<String, dynamic>;
    switch (data['type']) {
      case 'meta':
        _fileName = data['name'] as String;
        _totalSize = (data['size'] as num).toInt();
        _receivedSize = 0;
        _saver = await openReceivedFileSaver(_fileName!);
        onStatusUpdate(0.0, 'Incoming file: "$_fileName"', null);
        break;
      case 'eof':
        final location = await _saver?.finish();
        _saver = null;
        onStatusUpdate(1.0, 'File received', location);
        break;
    }
  }

  void dispose() {
    _saver = null;
  }
}
