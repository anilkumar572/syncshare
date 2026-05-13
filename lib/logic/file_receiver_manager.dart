import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileReceiverManager {
  IOSink? _fileSink;
  File? _receivedFile;
  int _receivedSize = 0;
  int _totalSize = 0;
  String? _fileName;

  // Callback to update UI
  final Function(double progress, String status, String? filePath) onStatusUpdate;

  FileReceiverManager({required this.onStatusUpdate});

  void handleIncomingMessage(RTCDataChannelMessage message) async {
    if (message.isBinary) {
      // 1. RECEIVE BINARY CHUNK
      if (_fileSink != null) {
        _fileSink!.add(message.binary);
        _receivedSize += message.binary.length;
        
        double progress = _totalSize > 0 ? (_receivedSize / _totalSize) : 0;
        onStatusUpdate(progress, "Receiving...", null);
      }
    } else {
      // 2. RECEIVE TEXT COMMAND (JSON)
      Map<String, dynamic> data = jsonDecode(message.text);

      if (data['type'] == 'meta') {
        // Prepare for new file
        _fileName = data['name'];
        _totalSize = data['size'];
        _receivedSize = 0;

        // Get directory to save (Downloads or Documents)
        Directory? directory;
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) directory = await getExternalStorageDirectory();
        } else {
          directory = await getApplicationDocumentsDirectory();
        }

        _receivedFile = File('${directory!.path}/$_fileName');
        _fileSink = _receivedFile!.openWrite();
        
        onStatusUpdate(0.0, "Starting download: $_fileName", null);
        print("Saving to: ${_receivedFile!.path}");

      } else if (data['type'] == 'eof') {
        // 3. FINISH FILE
        await _fileSink?.flush();
        await _fileSink?.close();
        _fileSink = null;
        
        onStatusUpdate(1.0, "File Saved!", _receivedFile!.path);
      }
    }
  }

  void dispose() {
    _fileSink?.close();
  }
}