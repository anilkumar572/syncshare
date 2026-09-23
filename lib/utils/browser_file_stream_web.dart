import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class BrowserFileSelection {
  BrowserFileSelection({
    required this.name,
    required this.size,
    required this.stream,
  });

  final String name;
  final int size;
  final Stream<List<int>> stream;
}

bool get isMobileWebBrowser {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod') ||
      ua.contains('android') ||
      ua.contains('mobile');
}

Future<BrowserFileSelection?> pickBrowserFileForStream() {
  final completer = Completer<BrowserFileSelection?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..multiple = false;

  var settled = false;

  void complete(BrowserFileSelection? value) {
    if (settled) {
      return;
    }
    settled = true;
    input.remove();
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void onWindowFocus(web.Event _) {
    web.window.removeEventListener('focus', onWindowFocus.toJS);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (settled) {
        return;
      }
      final files = input.files;
      if (files == null || files.length == 0) {
        complete(null);
      }
    });
  }

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      complete(null);
      return;
    }

    final file = files.item(0);
    if (file == null) {
      complete(null);
      return;
    }

    final chunkSize = isMobileWebBrowser ? 8 * 1024 : 16 * 1024;
    complete(
      BrowserFileSelection(
        name: file.name,
        size: file.size.round(),
        stream: _streamBrowserFile(file, chunkSize),
      ),
    );
  }.toJS;

  web.document.body?.append(input);
  web.window.addEventListener('focus', onWindowFocus.toJS);
  input.click();

  return completer.future;
}

Stream<List<int>> _streamBrowserFile(web.File file, int chunkSize) async* {
  final total = file.size.round();
  var offset = 0;

  while (offset < total) {
    final end = min(offset + chunkSize, total);
    final slice = file.slice(offset.toJS, end.toJS);
    yield await _readBlob(slice);
    offset = end;
  }
}

Future<Uint8List> _readBlob(web.Blob blob) {
  final reader = web.FileReader();
  final completer = Completer<Uint8List>();

  reader.onload = (web.Event _) {
    final buffer = reader.result;
    if (buffer == null) {
      completer.completeError(StateError('Could not read file chunk'));
      return;
    }
    completer.complete((buffer as JSArrayBuffer).toDart.asUint8List());
  }.toJS;

  reader.onerror = (web.Event _) {
    completer.completeError(StateError('Browser file read failed'));
  }.toJS;

  reader.readAsArrayBuffer(blob);
  return completer.future;
}
