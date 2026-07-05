import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void triggerBrowserDownload(Uint8List bytes, String fileName) {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
