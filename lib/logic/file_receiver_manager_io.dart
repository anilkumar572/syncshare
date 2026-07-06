import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sharesyncapp/logic/received_file.dart';

class FileReceiverManager {
  IOSink? _fileSink;
  File? _receivedFile;
  int _receivedSize = 0;
  int _totalSize = 0;
  String? _fileName;
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

  void handleIncomingMessage(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      if (_fileSink != null) {
        _fileSink!.add(message.binary);
        _receivedSize += message.binary.length;
        _maybeReportProgress('Receiving...');
      }
      return;
    }

    final data = jsonDecode(message.text) as Map<String, dynamic>;

    if (data['type'] == 'meta') {
      _fileName = data['name'] as String;
      _totalSize = data['size'] as int;
      _receivedSize = 0;
      _lastReportedProgress = -1;

      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      _receivedFile = File('${directory!.path}/$_fileName');
      _fileSink = _receivedFile!.openWrite();

      onMeta?.call(_fileName!, _totalSize);
      onStatusUpdate(0.0, 'Receiving $_fileName...', null);
    } else if (data['type'] == 'eof') {
      await _fileSink?.flush();
      await _fileSink?.close();
      _fileSink = null;

      if (_totalSize > 0 && _receivedSize != _totalSize) {
        onStatusUpdate(
          1.0,
          'Warning: size mismatch ($_receivedSize / $_totalSize bytes)',
          _receivedFile?.path,
        );
        return;
      }

      onStatusUpdate(1.0, 'File saved', _receivedFile!.path);
      onFileReceived?.call(
        ReceivedFile(
          name: _fileName ?? 'download',
          size: _receivedSize,
          savedPath: _receivedFile!.path,
        ),
      );
    }
  }

  void redownload() {}

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

  void dispose() {
    _fileSink?.close();
  }
}
