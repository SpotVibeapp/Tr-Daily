import 'package:flutter/material.dart';

import '../../broker/paper_broker.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

/// Trade log + engine event feed.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return ScreenScaffold(
      title: 'History',
      trailing: TabBar(
        controller: _tabs,
        labelColor: TrTheme.accent,
        unselectedLabelColor: TrTheme.textMuted,
        indicatorColor: TrTheme.accent,
        tabs: const [
          Tab(text: 'FILLS'),
          Tab(text: 'ENGINE LOG'),
        ],
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([st, _tabs]),
        builder: (context, _) => TabBarView(
          controller: _tabs,
          children: [
            _FillsTab(state: st),
            _LogTab(state: st),
          ],
        ),
      ),
    );
  }
}

class _FillsTab extends StatelessWidget {
  const _FillsTab({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final fills = state.tradeLog;
    if (fills.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 44, color: TrTheme.textMuted),
            SizedBox(height: 8),
            Text(
              'No fills yet.\nTrades appear here after the engine executes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TrTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    final totalPnl = fills.fold<double>(0, (a, f) => a + f.realizedPnl);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              Text(
                '${fills.length} fills',
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'realized ${TrTheme.money(totalPnl, signed: true)}',
                style: TextStyle(
                  color: TrTheme.pnlColor(totalPnl),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        for (final f in fills) _FillRow(fill: f),
      ],
    );
  }
}

class _FillRow extends StatelessWidget {
  const _FillRow({required this.fill});

  final PaperFill fill;

  @override
  Widget build(BuildContext context) {
    final buy = fill.side == OrderSide.buy;
    final t = fill.time;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: TrTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TrTheme.outline),
      ),
      child: Row(
        children: [
          TagChip(
            label: buy ? 'BUY' : 'SELL',
            color: buy ? TrTheme.up : TrTheme.down,
          ),
          const SizedBox(width: 8),
          Text(fill.symbol,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(width: 8),
          Text(
            '${fill.qty.toStringAsFixed(0)} @ \$${fill.price.toStringAsFixed(2)}',
            style: const TextStyle(color: TrTheme.textMuted, fontSize: 12),
          ),
          const Spacer(),
          if (fill.realizedPnl != 0)
            Text(
              TrTheme.money(fill.realizedPnl, signed: true),
              style: TextStyle(
                color: TrTheme.pnlColor(fill.realizedPnl),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: TrTheme.textMuted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _LogTab extends StatelessWidget {
  const _LogTab({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final entries = state.log.reversed.toList();
    if (entries.isEmpty) {
      return const Center(
        child: Text('Engine has not run yet.',
            style: TextStyle(color: TrTheme.textMuted)),
      );
    }
    return ListView.builder(
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => state.clearLog(),
              child: const Text('Clear'),
            ),
          );
        }
        final e = entries[i - 1];
        final color = switch (e.type) {
          'error' => TrTheme.down,
          'halt' => TrTheme.live,
          'trade' => TrTheme.up,
          'exit' => TrTheme.warn,
          'scan' => TrTheme.accent,
          _ => TrTheme.textMuted,
        };
        final t = e.time;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${t.hour.toString().padLeft(2, '0')}:'
                '${t.minute.toString().padLeft(2, '0')}:'
                '${t.second.toString().padLeft(2, '0')}',
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 10.5),
              ),
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.message,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
