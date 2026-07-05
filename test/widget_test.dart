import 'package:flutter_test/flutter_test.dart';
import 'package:sharesyncapp/theme/app_theme.dart';

void main() {
  test('App theme constants are defined', () {
    expect(AppTheme.primary.value, 0xFF6C63FF);
    expect(AppTheme.secondary.value, 0xFF00D4AA);
  });
}
