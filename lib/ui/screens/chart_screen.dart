import 'package:flutter/material.dart';

import '../../analysis/estimator.dart';
import '../../analysis/indicators.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/candle_chart.dart';
import '../widgets/common.dart';

/// Candlestick chart + live signal detail for one symbol.
class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key, required this.state, required this.symbol});

  final AppState state;
  final String symbol;

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  BarInterval _interval = BarInterval.fiveMin;
  List<Candle> _bars = <Candle>[];
  SignalScore? _signal;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bars = await widget.state.dataSource.getBars(
        symbol: widget.symbol,
        interval: _interval,
        limit: 180,
      );
      final sig = await widget.state.scanner.evaluateSymbol(
        widget.symbol,
        interval: _interval,
        bars: 220,
      );
      if (!mounted) return;
      setState(() {
        _bars = bars;
        _signal = sig;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  ChartFrame _buildFrame() {
    final closes = _bars.map((b) => b.close).toList();
    final snapshot = _bars.length >= 30
        ? const TrendEstimator().estimate(_bars)
        : null;
    return ChartFrame(
      candles: _bars,
      emaFast: ema(closes, 9),
      emaSlow: ema(closes, 21),
      vwap: sessionVwap(_bars),
      support: snapshot?.support,
      resistance: snapshot?.resistance,
      markers: <(int, String, Color)>[
        if (_signal != null && _signal!.stance != Stance.flat)
          (
            _bars.length - 1,
            _signal!.stance == Stance.long ? 'LONG' : 'SHORT',
            _signal!.stance == Stance.long ? TrTheme.up : TrTheme.down,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sig = _signal;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<BarInterval>(
              value: _interval,
              dropdownColor: TrTheme.surface2,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: BarInterval.oneMin, child: Text('1m')),
                DropdownMenuItem(value: BarInterval.fiveMin, child: Text('5m')),
                DropdownMenuItem(value: BarInterval.fifteenMin, child: Text('15m')),
                DropdownMenuItem(value: BarInterval.oneHour, child: Text('1h')),
                DropdownMenuItem(value: BarInterval.oneDay, child: Text('1d')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _interval = v);
                _load();
              },
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Could not load chart:\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: TrTheme.textMuted),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (sig != null) _SignalDetailCard(signal: sig),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: TrTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TrTheme.outline),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              _Legend(color: TrTheme.accent, label: 'EMA 9'),
                              SizedBox(width: 12),
                              _Legend(color: TrTheme.warn, label: 'EMA 21'),
                              SizedBox(width: 12),
                              _Legend(color: Color(0xFFB388FF), label: 'VWAP'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          CandleChart(frame: _buildFrame(), height: 340),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _bars.isEmpty
                          ? ''
                          : 'last close \$${_bars.last.close.toStringAsFixed(2)} · '
                              '${_bars.length} bars · ${_interval.code}',
                      style: const TextStyle(color: TrTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, color: TrTheme.textMuted)),
      ],
    );
  }
}

class _SignalDetailCard extends StatelessWidget {
  const _SignalDetailCard({required this.signal});

  final SignalScore signal;

  @override
  Widget build(BuildContext context) {
    final s = signal;
    final stanceColor = s.stance == Stance.long
        ? TrTheme.up
        : s.stance == Stance.short
            ? TrTheme.down
            : TrTheme.textMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TrTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stanceColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TagChip(label: s.stance.name.toUpperCase(), color: stanceColor),
              const SizedBox(width: 8),
              Text(
                'score ${s.scorePct} · conf ${(s.confidence * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const Spacer(),
              if (s.mlProbability != null)
                Text(
                  'ML P(up) ${s.mlProbability!.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFFB388FF), fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ScoreBar(score: s.score),
          const SizedBox(height: 10),
          for (final r in s.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $r',
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 12),
              ),
            ),
          if (s.breakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'SIGNAL BREAKDOWN',
              style: TextStyle(
                color: TrTheme.textMuted,
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in s.breakdown.entries)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: TrTheme.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${e.key} ${e.value >= 0 ? '+' : ''}${e.value}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: TrTheme.pnlColor(e.value),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
