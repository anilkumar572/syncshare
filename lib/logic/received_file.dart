class ReceivedFile {
  const ReceivedFile({
    required this.name,
    required this.size,
    this.savedPath,
    this.canRedownload = false,
  });

  final String name;
  final int size;
  final String? savedPath;
  final bool canRedownload;

  String get readableSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = size.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final precision = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unit]}';
  }
}
