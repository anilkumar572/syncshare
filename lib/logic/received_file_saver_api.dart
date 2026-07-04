import 'dart:typed_data';

/// Platform-agnostic incremental writer for a received file.
///
/// Native implementations stream chunks straight to disk; the web
/// implementation buffers them and triggers a browser download on [finish].
abstract class ReceivedFileSaver {
  void addChunk(Uint8List chunk);

  /// Finalizes the file and returns a human-readable location/description.
  Future<String> finish();
}
