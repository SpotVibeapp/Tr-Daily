import 'package:flutter/material.dart';

import '../theme.dart';

/// Center-zero score bar in [-1, 1].
class ScoreBar extends StatelessWidget {
  const ScoreBar({super.key, required this.score, this.height = 8});

  final double score;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = score.clamp(-1.0, 1.0);
    final color = s >= 0 ? TrTheme.up : TrTheme.down;
    final frac = s.abs();
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: TrTheme.surface2,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = constraints.maxWidth / 2;
          return Stack(
            children: [
              // Center tick.
              Positioned(
                left: half - 0.5,
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: TrTheme.outline),
              ),
              Positioned(
                left: s >= 0 ? half : half - frac * half,
                top: 0,
                bottom: 0,
                child: Container(
                  width: frac * half,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Small labeled metric tile.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.expanded = false,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: TrTheme.textMuted,
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? TrTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: const TextStyle(color: TrTheme.textMuted, fontSize: 11),
          ),
      ],
    );
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TrTheme.outline),
      ),
      child: expanded
          ? SizedBox(width: double.infinity, child: content)
          : content,
    );
    return card;
  }
}

/// Chip showing stance / mode / status.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    required this.color,
    this.filled = true,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(filled ? 0.5 : 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
