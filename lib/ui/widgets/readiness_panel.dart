import 'package:flutter/material.dart';

import '../../analysis/live_readiness.dart';
import '../theme.dart';

/// The go-live checks with a pass/fail mark each.
class ReadinessPanel extends StatelessWidget {
  const ReadinessPanel({super.key, required this.readiness});

  final LiveReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final color = readiness.ready ? TrTheme.up : TrTheme.warn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          readiness.summary,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final c in readiness.checks)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  c.passed ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: c.passed ? TrTheme.up : TrTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.label,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  c.detail,
                  style: const TextStyle(
                    color: TrTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'Counts trades in the in-app paper account only.',
          style: TextStyle(color: TrTheme.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}
