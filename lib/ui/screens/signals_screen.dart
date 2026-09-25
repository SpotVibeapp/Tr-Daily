import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../engine/day_trade.dart';
import '../../risk/risk_manager.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chart_screen.dart';
import 'home_shell.dart';

/// Live ensemble signals for the watchlist.
class SignalsScreen extends StatelessWidget {
  const SignalsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Signals',
      actions: [
        IconButton(
          tooltip: 'Scan now',
          onPressed: state.scanning ? null : () => state.scanNow(),
          icon: state.scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
        ),
      ],
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          if (state.signals.isEmpty && !state.scanning) {
            return _EmptyState(state: state);
          }
          return RefreshIndicator(
            color: TrTheme.accent,
            onRefresh: () => state.scanNow(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Text(
                    'Composite score = chart-trend ensemble'
                        '${state.settings.ensemble.useMl ? ' + online ML' : ''}'
                        ' · source ${state.scanner.source.id}',
                    style: const TextStyle(color: TrTheme.textMuted, fontSize: 11.5),
                  ),
                ),
                if (state.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '⚠ ${state.lastError}',
                      style: const TextStyle(color: TrTheme.warn, fontSize: 12),
                    ),
                  ),
                for (final sig in state.signals)
                  _SignalCard(
                    signal: sig,
                    overBudget: _overBudget(state, sig),
                    tooQuiet: _tooQuiet(state, sig),
                    minTargetPct: state.settings.minTargetPct,
                    budgetPick: state.budget.last.sleeve.contains(sig.symbol),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChartScreen(state: state, symbol: sig.symbol),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (state.engine?.lastError != null)
                  Text(
                    'engine: ${state.engine!.lastError}',
                    style: const TextStyle(color: TrTheme.warn, fontSize: 11),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

bool _overBudget(AppState state, SignalScore sig) {
  if (!state.settings.fitToBudget) return false;
  final maxPx = maxAffordableSharePrice(state.account, state.settings.risk);
  return maxPx > 0 && sig.price > maxPx + 1e-6;
}

bool _tooQuiet(AppState state, SignalScore sig) {
  if (!state.settings.dayTradeEdge || sig.stance == Stance.flat) return false;
  final pct = targetPctOfPrice(sig);
  if (pct == null) return false;
  return pct + 1e-9 < state.settings.minTargetPct;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.radar, size: 48, color: TrTheme.textMuted),
          const SizedBox(height: 12),
          const Text(
            'No signals yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap sync to scan ${state.settings.watchlist.join(', ')}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: TrTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => state.scanNow(),
            icon: const Icon(Icons.travel_explore, size: 18),
            label: const Text('Run first scan'),
          ),
        ],
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.signal,
    required this.onTap,
    this.overBudget = false,
    this.tooQuiet = false,
    this.minTargetPct = 1,
    this.budgetPick = false,
  });

  final SignalScore signal;
  final VoidCallback onTap;
  final bool overBudget;
  final bool tooQuiet;
  final double minTargetPct;
  final bool budgetPick;

  @override
  Widget build(BuildContext context) {
    final s = signal;
    final stanceColor = s.stance == Stance.long
        ? TrTheme.up
        : s.stance == Stance.short
            ? TrTheme.down
            : TrTheme.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TrTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: s.stance == Stance.flat ? TrTheme.outline : stanceColor.withOpacity(0.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  s.symbol,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: TrTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                TagChip(
                  label: s.stance.name.toUpperCase(),
                  color: stanceColor,
                ),
                const Spacer(),
                Text(
                  '\$${s.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
            if (overBudget) ...[
              const SizedBox(height: 4),
              const Text(
                'Over budget — one share does not fit, so this name is skipped',
                style: TextStyle(color: TrTheme.warn, fontSize: 11),
              ),
            ] else if (tooQuiet) ...[
              const SizedBox(height: 4),
              Text(
                'Too quiet for a day trade — target '
                '${(targetPctOfPrice(signal) ?? 0).toStringAsFixed(2)}% of price, '
                'need ${minTargetPct.toStringAsFixed(1)}%',
                style: const TextStyle(color: TrTheme.warn, fontSize: 11),
              ),
            ] else if (budgetPick) ...[
              const SizedBox(height: 4),
              const Text(
                'Fits this account — added because the watchlist was too expensive',
                style: TextStyle(color: TrTheme.accent, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ScoreBar(score: s.score),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${s.scorePct}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: TrTheme.pnlColor(s.score),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'confidence ${(s.confidence * 100).round()}%',
                  style: const TextStyle(color: TrTheme.textMuted, fontSize: 11.5),
                ),
                if (s.mlProbability != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    'P(up) ${s.mlProbability!.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFFB388FF), fontSize: 11.5),
                  ),
                ],
                const Spacer(),
                if (s.suggestedStop != null)
                  Text(
                    'SL \$${s.suggestedStop!.toStringAsFixed(2)}',
                    style: const TextStyle(color: TrTheme.down, fontSize: 11),
                  ),
                if (s.suggestedTarget != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'TP \$${s.suggestedTarget!.toStringAsFixed(2)}',
                    style: const TextStyle(color: TrTheme.up, fontSize: 11),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in s.reasons.take(4))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: TrTheme.surface2,
                    side: const BorderSide(color: TrTheme.outline),
                    label: Text(
                      r,
                      style: const TextStyle(fontSize: 10.5, color: TrTheme.textMuted),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
