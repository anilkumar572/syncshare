import 'package:flutter/material.dart';
import 'package:sharesyncapp/theme/app_theme.dart';

class RoomCodeDisplay extends StatelessWidget {
  const RoomCodeDisplay({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final digits = code.split('');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < digits.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Duration(milliseconds: 250 + i * 80),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.6 + value * 0.4,
                  child: Opacity(opacity: value.clamp(0, 1), child: child),
                );
              },
              child: _DigitBox(digit: digits[i]),
            ),
          ),
      ],
    );
  }
}

class _DigitBox extends StatelessWidget {
  const _DigitBox({required this.digit});

  final String digit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.22),
            AppTheme.secondary.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
