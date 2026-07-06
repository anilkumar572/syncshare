import 'package:flutter/material.dart';
import 'package:sharesyncapp/theme/app_theme.dart';
import 'package:sharesyncapp/utils/format.dart';

enum TransferPhase { idle, sending, receiving, done }

class TransferStatusCard extends StatelessWidget {
  const TransferStatusCard({
    super.key,
    required this.phase,
    required this.progress,
    required this.fileName,
    required this.totalBytes,
    required this.speed,
  });

  final TransferPhase phase;
  final double progress;
  final String? fileName;
  final int totalBytes;
  final double speed;

  bool get _active =>
      phase == TransferPhase.sending || phase == TransferPhase.receiving;

  Color get _accent {
    switch (phase) {
      case TransferPhase.sending:
        return AppTheme.primary;
      case TransferPhase.receiving:
        return AppTheme.secondary;
      case TransferPhase.done:
        return AppTheme.secondary;
      case TransferPhase.idle:
        return Colors.white;
    }
  }

  IconData get _icon {
    switch (phase) {
      case TransferPhase.sending:
        return Icons.arrow_upward_rounded;
      case TransferPhase.receiving:
        return Icons.arrow_downward_rounded;
      case TransferPhase.done:
        return Icons.check_rounded;
      case TransferPhase.idle:
        return Icons.bolt_rounded;
    }
  }

  String get _label {
    switch (phase) {
      case TransferPhase.sending:
        return 'Sending';
      case TransferPhase.receiving:
        return 'Receiving';
      case TransferPhase.done:
        return 'Completed';
      case TransferPhase.idle:
        return 'Ready';
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0, 1) * 100);
    final transferred = (totalBytes * progress.clamp(0, 1)).round();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent.withValues(alpha: 0.18),
            _accent.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: _accent.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.14),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PhaseIcon(icon: _icon, accent: _accent, active: _active),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _label,
                          style: TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (_active) ...[
                          const SizedBox(width: 8),
                          _LiveDot(color: _accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fileName ?? 'Waiting for file...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress.clamp(0, 1)),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: phase == TransferPhase.done ? 1 : value,
                  minHeight: 14,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(_accent),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MetaChip(
                icon: Icons.data_usage_rounded,
                label: totalBytes > 0
                    ? '${formatBytes(transferred)} / ${formatBytes(totalBytes)}'
                    : formatBytes(transferred),
              ),
              if (_active)
                _MetaChip(
                  icon: Icons.speed_rounded,
                  label: formatSpeed(speed),
                )
              else if (phase == TransferPhase.done)
                _MetaChip(
                  icon: Icons.check_circle_rounded,
                  label: 'Done',
                  color: AppTheme.secondary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhaseIcon extends StatelessWidget {
  const _PhaseIcon({
    required this.icon,
    required this.accent,
    required this.active,
  });

  final IconData icon;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: accent, size: 26),
    );

    if (!active) {
      return box;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.9, end: 1.05),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      onEnd: () {},
      child: box,
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white.withValues(alpha: 0.7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: c,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
