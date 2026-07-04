import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'received_file_saver_api.dart';

class _IoReceivedFileSaver implements ReceivedFileSaver {
  _IoReceivedFileSaver(this._sink, this._path);

  final IOSink _sink;
  final String _path;

  @override
  void addChunk(Uint8List chunk) => _sink.add(chunk);

  @override
  Future<String> finish() async {
    await _sink.flush();
    await _sink.close();
    return _path;
  }
}

Future<ReceivedFileSaver> openReceivedFileSaver(String fileName) async {
  Directory directory;
  if (Platform.isAndroid) {
    final downloads = Directory('/storage/emulated/0/Download');
    directory = await downloads.exists()
        ? downloads
        : (await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory());
  } else {
    directory = await getApplicationDocumentsDirectory();
  }
  final path = '${directory.path}/$fileName';
  final sink = File(path).openWrite();
  return _IoReceivedFileSaver(sink, path);
}
