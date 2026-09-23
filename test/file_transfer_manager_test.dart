import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharesyncapp/logic/file_transfer_manager.dart';

void main() {
  test('normalizeChunkStream emits fixed frame sizes', () async {
    final input = Stream<List<int>>.from([
      Uint8List.fromList(List.filled(10 * 1024, 1)),
      Uint8List.fromList(List.filled(10 * 1024, 2)),
      Uint8List.fromList(List.filled(5 * 1024, 3)),
    ]);

    final frames = await normalizeChunkStream(input, 16 * 1024).toList();

    expect(frames.length, 2);
    expect(frames[0].length, 16 * 1024);
    expect(frames[1].length, 9 * 1024);
    expect(frames.fold<int>(0, (sum, f) => sum + f.length), 25 * 1024);
  });
}
