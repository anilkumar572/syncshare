import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  final List<Uint8List> _earlyBinaryBuffer = [];
  Future<void>? _sinkSetup;

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
      _onBinary(message.binary);
      return;
    }

    final data = jsonDecode(message.text) as Map<String, dynamic>;

    if (data['type'] == 'meta') {
      _onMeta(data);
    } else if (data['type'] == 'eof') {
      _onEof();
    }
  }

  void _onBinary(Uint8List data) {
    if (_fileSink != null) {
      _writeBinary(data);
      return;
    }

    if (_fileName != null && _totalSize > 0) {
      _earlyBinaryBuffer.add(data);
    }
  }

  void _onMeta(Map<String, dynamic> data) {
    _fileName = data['name'] as String;
    _totalSize = data['size'] as int;
    _receivedSize = 0;
    _lastReportedProgress = -1;
    _earlyBinaryBuffer.clear();

    _sinkSetup = _prepareSink().then((_) {
      for (final chunk in _earlyBinaryBuffer) {
        _writeBinary(chunk);
      }
      _earlyBinaryBuffer.clear();
    }).catchError((Object error) {
      onStatusUpdate(0, 'Could not save file: $error', null);
    });

    onMeta?.call(_fileName!, _totalSize);
    onStatusUpdate(0.0, 'Receiving $_fileName...', null);
  }

  Future<void> _prepareSink() async {
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;

    final directory = await _resolveSaveDirectory();
    final safeName = _fileName!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    _receivedFile = File('${directory.path}/$safeName');
    if (await _receivedFile!.exists()) {
      await _receivedFile!.delete();
    }
    _fileSink = _receivedFile!.openWrite();
  }

  Future<Directory> _resolveSaveDirectory() async {
    if (Platform.isAndroid) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }

      final external = await getExternalStorageDirectory();
      if (external != null) {
        return external;
      }
    }

    return getApplicationDocumentsDirectory();
  }

  void _writeBinary(Uint8List data) {
    final sink = _fileSink;
    if (sink == null) {
      return;
    }
    sink.add(data);
    _receivedSize += data.length;
    _maybeReportProgress('Receiving...');
  }

  Future<void> _onEof() async {
    final setup = _sinkSetup;
    if (setup != null) {
      await setup;
    }

    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;
    _sinkSetup = null;

    if (_totalSize > 0 && _receivedSize != _totalSize) {
      onStatusUpdate(
        1.0,
        'Warning: size mismatch ($_receivedSize / $_totalSize bytes)',
        _receivedFile?.path,
      );
      return;
    }

    if (_receivedFile == null) {
      onStatusUpdate(1.0, 'Receive failed: file was not saved', null);
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
