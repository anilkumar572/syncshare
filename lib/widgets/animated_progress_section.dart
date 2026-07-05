import 'package:flutter/material.dart';
import 'package:sharesyncapp/theme/app_theme.dart';

class AnimatedProgressSection extends StatelessWidget {
  const AnimatedProgressSection({
    super.key,
    required this.progress,
    required this.isActive,
  });

  final double progress;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isActive ? 1 : 0,
        child: isActive
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 12,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.secondary,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}% complete',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Icon(
                        Icons.bolt_rounded,
                        color: AppTheme.secondary.withValues(alpha: 0.9),
                        size: 20,
                      ),
                    ],
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
