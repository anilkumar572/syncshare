import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'received_file_saver_api.dart';

class _WebReceivedFileSaver implements ReceivedFileSaver {
  _WebReceivedFileSaver(this._fileName);

  final String _fileName;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  void addChunk(Uint8List chunk) => _builder.add(chunk);

  @override
  Future<String> finish() async {
    final bytes = _builder.takeBytes();
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = _fileName;
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return 'Downloads/$_fileName';
  }
}

Future<ReceivedFileSaver> openReceivedFileSaver(String fileName) async =>
    _WebReceivedFileSaver(fileName);
