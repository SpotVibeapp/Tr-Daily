import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/equity_curve.dart';
import 'home_shell.dart';

/// Run backtests and inspect metrics (simulated past performance — never a
/// guarantee of future results).
class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key, required this.state});

  final AppState state;

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  String? _symbol;
  int _bars = 400;

  @override
  void initState() {
    super.initState();
    _symbol = widget.state.settings.watchlist.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return ScreenScaffold(
      title: 'Backtest',
      child: AnimatedBuilder(
        animation: st,
        builder: (context, _) {
          final result = st.lastBacktest;
          final m = result?.metrics;
          return ListView(
            children: [
              // ---- controls ----
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _symbol,
                      dropdownColor: TrTheme.surface2,
                      decoration: const InputDecoration(labelText: 'Symbol'),
                      items: [
                        for (final s in st.settings.watchlist)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setState(() => _symbol = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _bars,
                      dropdownColor: TrTheme.surface2,
                      decoration: const InputDecoration(labelText: 'Bars'),
                      items: const [
                        DropdownMenuItem(value: 200, child: Text('200')),
                        DropdownMenuItem(value: 400, child: Text('400')),
                        DropdownMenuItem(value: 700, child: Text('700')),
                      ],
                      onChanged: (v) => setState(() => _bars = v ?? 400),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: (st.backtestRunning || _symbol == null)
                    ? null
                    : () => st.runBacktest(_symbol!, bars: _bars),
                icon: st.backtestRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  st.backtestRunning
                      ? 'Running ${st.backtestSymbol ?? ''}…'
                      : 'Run backtest',
                ),
              ),
              const SizedBox(height: 14),

              if (result == null && m == null)
                const _BacktestPlaceholder()
              else if (result != null && m != null) ...[
                // ---- headline ----
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TrTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: TrTheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${m.returnPct >= 0 ? '+' : ''}'
                            '${m.returnPct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: TrTheme.pnlColor(m.returnPct),
                            ),
                          ),
                          const SizedBox(width: 10),
                          TagChip(
                            label:
                                'vs B&H ${m.buyHoldPct.toStringAsFixed(2)}%',
                            color: m.returnPct >= m.buyHoldPct
                                ? TrTheme.up
                                : TrTheme.warn,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'strategy PnL ${TrTheme.money(m.totalPnl, signed: true)} '
                        'on \$25k start · ${m.tradeCount} trades',
                        style: const TextStyle(
                          color: TrTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      EquityCurve(values: result!.equityCurve),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ---- metrics grid ----
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.5,
                  children: [
                    StatTile(
                      label: 'Win rate',
                      value: '${m.winRate.toStringAsFixed(0)}%',
                      valueColor: m.winRate >= 50 ? TrTheme.up : TrTheme.warn,
                    ),
                    StatTile(
                      label: 'Profit factor',
                      value: m.profitFactor >= 999
                          ? '∞'
                          : m.profitFactor.toStringAsFixed(2),
                      valueColor:
                          m.profitFactor >= 1 ? TrTheme.up : TrTheme.down,
                    ),
                    StatTile(
                      label: 'Max DD',
                      value: '${m.maxDrawdownPct.toStringAsFixed(1)}%',
                      valueColor: TrTheme.down,
                    ),
                    StatTile(
                      label: 'Sharpe',
                      value: m.sharpe.toStringAsFixed(2),
                    ),
                    StatTile(
                      label: 'Expectancy',
                      value: TrTheme.money(m.expectancy, signed: true),
                      valueColor: TrTheme.pnlColor(m.expectancy),
                    ),
                    StatTile(
                      label: 'Exposure',
                      value: '${m.exposurePct.toStringAsFixed(0)}%',
                    ),
                    StatTile(
                      label: 'Avg win',
                      value: TrTheme.money(m.avgWin, signed: true),
                      valueColor: TrTheme.up,
                    ),
                    StatTile(
                      label: 'Avg loss',
                      value: TrTheme.money(m.avgLoss, signed: true),
                      valueColor: TrTheme.down,
                    ),
                    StatTile(
                      label: 'Final equity',
                      value: TrTheme.money(result!.equityFinal),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ---- trade list ----
                const Text(
                  'RECENT TRADES',
                  style: TextStyle(
                    color: TrTheme.textMuted,
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final t in result.trades.take(12))
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: TrTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: TrTheme.outline),
                    ),
                    child: Row(
                      children: [
                        TagChip(
                          label: t.side == Stance.long ? 'LONG' : 'SHORT',
                          color: t.side == Stance.long
                              ? TrTheme.up
                              : TrTheme.down,
                        ),
                        const SizedBox(width: 8),
                        Text(t.symbol,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const Spacer(),
                        Text(
                          t.exitReason,
                          style: const TextStyle(
                              color: TrTheme.textMuted, fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          TrTheme.money(t.grossPnl, signed: true),
                          style: TextStyle(
                            color: TrTheme.pnlColor(t.grossPnl),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TrTheme.warn.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: TrTheme.warn.withOpacity(0.4)),
                  ),
                  child: const Text(
                    '⚠ Simulated past performance. Markets are unpredictable — '
                    'these results do NOT guarantee future profits. Backtests '
                    'use conservative fills (slippage applied) but real fills, '
                    'fees and latency will differ.',
                    style: TextStyle(color: TrTheme.warn, fontSize: 11.5),
                  ),
                ),
                for (final w in result.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(w,
                        style: const TextStyle(
                            color: TrTheme.textMuted, fontSize: 11)),
                  ),
              ],
              if (st.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('⚠ ${st.lastError}',
                      style:
                          const TextStyle(color: TrTheme.down, fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BacktestPlaceholder extends StatelessWidget {
  const _BacktestPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: TrTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrTheme.outline),
      ),
      child: const Column(
        children: [
          Icon(Icons.biotech, size: 40, color: TrTheme.textMuted),
          SizedBox(height: 10),
          Text(
            'Run the ensemble over historical bars.\n'
            'Strict no-lookahead execution: signals on close, fills at next open.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TrTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
