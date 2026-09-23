import 'dart:typed_data';

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

Future<BrowserFileSelection?> pickBrowserFileForStream() {
  throw UnsupportedError('Browser file streaming is only available on web');
}

bool get isMobileWebBrowser => false;
