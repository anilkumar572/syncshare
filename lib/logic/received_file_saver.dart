import 'received_file_saver_api.dart';
import 'received_file_saver_io.dart'
    if (dart.library.js_interop) 'received_file_saver_web.dart' as impl;

export 'received_file_saver_api.dart';

/// Opens a platform-appropriate [ReceivedFileSaver] for [fileName].
Future<ReceivedFileSaver> openReceivedFileSaver(String fileName) =>
    impl.openReceivedFileSaver(fileName);
