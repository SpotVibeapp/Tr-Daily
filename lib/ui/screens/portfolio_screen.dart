import 'package:flutter/material.dart';

import '../../analysis/portfolio_analytics.dart';
import '../../core/notifications.dart';
import '../../data/models.dart';
import '../../engine/trader_engine.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/readiness_panel.dart';
import 'chart_screen.dart';
import 'home_shell.dart';

/// Portfolio screen displaying asset allocation breakdown, active positions with
/// live P&L and risk levels, and round-trip trade performance history.
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key, required this.state});

  final AppState state;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return AnimatedBuilder(
      animation: Listenable.merge([st, _tabs]),
      builder: (context, _) {
        final posCount = st.positions.length;
        final unreadNotifs = st.notifications.unreadCount;

        return ScreenScaffold(
          title: 'Portfolio',
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'Alerts & Notifications',
                  icon: const Icon(Icons.notifications_outlined, color: TrTheme.textMuted),
                  onPressed: () => _showNotificationSheet(context, st),
                ),
                if (unreadNotifs > 0)
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: TrTheme.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadNotifs > 99 ? '99+' : '$unreadNotifs',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, color: TrTheme.textMuted),
              onPressed: () async {
                await st.refreshAccount();
                await st.scanNow();
              },
            ),
          ],
          trailing: TabBar(
            controller: _tabs,
            labelColor: TrTheme.accent,
            unselectedLabelColor: TrTheme.textMuted,
            indicatorColor: TrTheme.accent,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'ALLOCATION'),
              Tab(text: 'POSITIONS ($posCount)'),
              const Tab(text: 'PERFORMANCE'),
            ],
          ),
          child: TabBarView(
            controller: _tabs,
            children: [
              _AllocationTab(state: st),
              _PositionsTab(state: st),
              _PerformanceTab(state: st),
            ],
          ),
        );
      },
    );
  }

  void _showNotificationSheet(BuildContext context, AppState state) {
    showAppNotifications(context, state);
  }
}

/// Opens the notification bottom sheet and marks unread notifications as read.
void showAppNotifications(BuildContext context, AppState state) {
  state.notifications.markAllRead();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: TrTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _NotificationDrawer(state: state),
  );
}

// ============================================================================
// TAB 1: ALLOCATION & OVERVIEW
// ============================================================================

class _AllocationTab extends StatelessWidget {
  const _AllocationTab({required this.state});

  final AppState state;

  static const List<Color> _palette = <Color>[
    Color(0xFF00E676),
    Color(0xFF2979FF),
    Color(0xFFFF9100),
    Color(0xFFAB47BC),
    Color(0xFF00E5FF),
    Color(0xFFFF5252),
    Color(0xFFFFEA00),
  ];

  @override
  Widget build(BuildContext context) {
    final breakdown = PortfolioBreakdown.compute(
      account: state.account,
      positions: state.positions,
    );

    var totalUnrealized = 0.0;
    for (final p in state.positions) {
      totalUnrealized += p.unrealizedPnl;
    }

    final totalRealized = state.tradeLog.fold<double>(0.0, (acc, f) => acc + f.realizedPnl);

    return ListView(
      children: [
        // ---- Top Overview Card ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TOTAL PORTFOLIO VALUE',
                style: TextStyle(
                  color: TrTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    TrTheme.money(breakdown.totalEquity),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: TrTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${state.account.dayPnl >= 0 ? '+' : ''}${state.account.dayPnl.toStringAsFixed(2)} '
                      '(${state.account.dayPnlPct.toStringAsFixed(2)}%) today',
                      style: TextStyle(
                        color: TrTheme.pnlColor(state.account.dayPnl),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Unrealized P&L',
                      value: TrTheme.money(totalUnrealized, signed: true),
                      valueColor: TrTheme.pnlColor(totalUnrealized),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Realized P&L',
                      value: TrTheme.money(totalRealized, signed: true),
                      valueColor: TrTheme.pnlColor(totalRealized),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Buying Power',
                      value: TrTheme.money(state.account.buyingPower),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---- Allocation Progress Bar Card ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CAPITAL ALLOCATION',
                    style: TextStyle(
                      color: TrTheme.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Cash: ${breakdown.cashPct.toStringAsFixed(1)}% · Invested: ${breakdown.investedPct.toStringAsFixed(1)}%',
                    style: const TextStyle(color: TrTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Segmented visual bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      // Cash segment
                      if (breakdown.cashPct > 0)
                        Flexible(
                          flex: (breakdown.cashPct * 10).round().clamp(1, 1000),
                          child: Container(
                            color: TrTheme.surface2,
                          ),
                        ),
                      // Position segments
                      for (var i = 0; i < breakdown.allocations.length; i++)
                        Flexible(
                          flex: (breakdown.allocations[i].portfolioPct * 10).round().clamp(1, 1000),
                          child: Container(
                            color: _palette[i % _palette.length],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Allocation Legend
              Row(
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: TrTheme.surface2, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('Cash', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  Text(TrTheme.money(breakdown.cash), style: const TextStyle(fontSize: 13, color: TrTheme.textPrimary)),
                  const SizedBox(width: 8),
                  Text('${breakdown.cashPct.toStringAsFixed(1)}%', style: const TextStyle(color: TrTheme.textMuted, fontSize: 12)),
                ],
              ),
              const Divider(color: TrTheme.outline, height: 16),

              if (breakdown.allocations.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '100% of capital is in cash. No open positions held.',
                    style: TextStyle(color: TrTheme.textMuted, fontSize: 12),
                  ),
                )
              else
                for (var i = 0; i < breakdown.allocations.length; i++) ...[
                  _AllocationRow(
                    allocation: breakdown.allocations[i],
                    color: _palette[i % _palette.length],
                  ),
                  if (i < breakdown.allocations.length - 1)
                    const Divider(color: TrTheme.outline, height: 14),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---- Exposure Metrics Card ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EXPOSURE & LEVERAGE',
                style: TextStyle(
                  color: TrTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Long Exposure',
                      value: TrTheme.money(breakdown.longExposure),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Short Exposure',
                      value: TrTheme.money(breakdown.shortExposure),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Net Exposure',
                      value: TrTheme.money(breakdown.netExposure, signed: true),
                      valueColor: TrTheme.pnlColor(breakdown.netExposure),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Gross Exposure',
                      value: TrTheme.money(breakdown.grossExposure),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Leverage',
                      value: '${breakdown.leverage.toStringAsFixed(2)}x',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Active Holdings',
                      value: '${breakdown.allocations.length}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.allocation, required this.color});

  final AssetAllocation allocation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final a = allocation;
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(a.symbol, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: (a.isShort ? TrTheme.down : TrTheme.up).withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            a.isShort ? 'SHORT' : 'LONG',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: a.isShort ? TrTheme.down : TrTheme.up,
            ),
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              TrTheme.money(a.marketValue),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            Text(
              '${a.unrealizedPnl >= 0 ? '+' : ''}${TrTheme.money(a.unrealizedPnl)} (${a.unrealizedPnlPct.toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: TrTheme.pnlColor(a.unrealizedPnl),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          child: Text(
            '${a.portfolioPct.toStringAsFixed(1)}%',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: TrTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// TAB 2: ACTIVE POSITIONS
// ============================================================================

class _PositionsTab extends StatelessWidget {
  const _PositionsTab({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final positions = state.positions;

    if (positions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pie_chart_outline, size: 52, color: TrTheme.textMuted),
              const SizedBox(height: 12),
              const Text(
                'No Open Positions',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: TrTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'When the engine triggers a trade setup, active positions will appear here with live P&L, stop-loss and profit targets.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TrTheme.textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.bolt, size: 16),
                label: const Text('Run Market Scan'),
                onPressed: () => state.scanNow(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: positions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final p = positions[index];
        final meta = state.getPositionMeta(p.symbol);
        return _PositionCard(
          position: p,
          meta: meta,
          state: state,
        );
      },
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.position,
    required this.meta,
    required this.state,
  });

  final Position position;
  final PositionMeta? meta;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final sideColor = p.short ? TrTheme.down : TrTheme.up;
    final uPnl = p.unrealizedPnl;
    final uPct = p.unrealizedPnlPct;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Symbol, Side, Shares, P&L
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        p.symbol,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: TrTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TagChip(
                        label: p.short ? 'SHORT' : 'LONG',
                        color: sideColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${p.qty.toStringAsFixed(p.qty.truncateToDouble() == p.qty ? 0 : 2)} shares @ \$${p.avgEntryPrice.toStringAsFixed(2)}',
                    style: const TextStyle(color: TrTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${uPnl >= 0 ? '+' : ''}${TrTheme.money(uPnl)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: TrTheme.pnlColor(uPnl),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${uPct >= 0 ? '+' : ''}${uPct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: TrTheme.pnlColor(uPnl),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Price & Market Value Row
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Current Price',
                  value: '\$${p.currentPrice.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'Market Value',
                  value: TrTheme.money(p.marketValue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'Cost Basis',
                  value: TrTheme.money(p.costBasis),
                ),
              ),
            ],
          ),

          // Risk Levels / Management State
          if (meta != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: TrTheme.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'STOP LOSS',
                          style: TextStyle(color: TrTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${meta!.initialStop.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TrTheme.down),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TARGET',
                          style: TextStyle(color: TrTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${meta!.target.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TrTheme.up),
                        ),
                      ],
                    ),
                  ),
                  if (meta!.peak > 0)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PEAK SEEN',
                            style: TextStyle(color: TrTheme.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${meta!.peak.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TrTheme.accent),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Action Buttons
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.show_chart, size: 15),
                label: const Text('Chart'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChartScreen(state: state, symbol: p.symbol),
                    ),
                  );
                },
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Close Position'),
                style: FilledButton.styleFrom(
                  backgroundColor: TrTheme.down.withOpacity(0.85),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                onPressed: () => _confirmClose(context, p.symbol),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, String symbol) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TrTheme.surface,
        title: Text('Close $symbol position?'),
        content: Text(
          'This will submit a market order to completely close out your position in $symbol at the best available price.',
          style: const TextStyle(color: TrTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TrTheme.down),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close Now'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await state.closePosition(symbol);
    }
  }
}

// ============================================================================
// TAB 3: PERFORMANCE & COMPLETED TRADES
// ============================================================================

class _PerformanceTab extends StatefulWidget {
  const _PerformanceTab({required this.state});

  final AppState state;

  @override
  State<_PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<_PerformanceTab> {
  String _filter = 'all'; // all | wins | losses

  @override
  Widget build(BuildContext context) {
    final fills = widget.state.tradeLog;
    final perf = PortfolioPerformance.fromFills(fills);

    final filteredTrades = perf.trades.where((t) {
      if (_filter == 'wins') return t.isWin;
      if (_filter == 'losses') return t.isLoss;
      return true;
    }).toList();

    return ListView(
      children: [
        // ---- Go-live checks ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'READY FOR LIVE?',
                style: TextStyle(
                  color: TrTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              ReadinessPanel(readiness: widget.state.liveReadiness),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ---- Analytics Overview Card ----
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardBox(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PERFORMANCE SUMMARY',
                style: TextStyle(
                  color: TrTheme.textMuted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Win Rate',
                      value: '${perf.winRatePct.toStringAsFixed(1)}%',
                      valueColor: perf.winRatePct >= 50 ? TrTheme.up : TrTheme.down,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Profit Factor',
                      value: perf.profitFactor.isInfinite
                          ? '∞'
                          : perf.profitFactor.toStringAsFixed(2),
                      valueColor: perf.profitFactor >= 1.5 ? TrTheme.up : TrTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Total Realized',
                      value: TrTheme.money(perf.totalRealizedPnl, signed: true),
                      valueColor: TrTheme.pnlColor(perf.totalRealizedPnl),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Trades',
                      value: '${perf.winningTrades}W / ${perf.losingTrades}L (${perf.totalClosedTrades})',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Avg Win',
                      value: TrTheme.money(perf.avgWin),
                      valueColor: TrTheme.up,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Avg Loss',
                      value: TrTheme.money(-perf.avgLoss),
                      valueColor: TrTheme.down,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---- Filter Chips ----
        Row(
          children: [
            const Text(
              'Closed Trades',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const Spacer(),
            ChoiceChip(
              label: const Text('All'),
              selected: _filter == 'all',
              onSelected: (_) => setState(() => _filter = 'all'),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('Wins'),
              selected: _filter == 'wins',
              onSelected: (_) => setState(() => _filter = 'wins'),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('Losses'),
              selected: _filter == 'losses',
              onSelected: (_) => setState(() => _filter = 'losses'),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (filteredTrades.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: _cardBox(),
            child: Column(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 40, color: TrTheme.textMuted),
                const SizedBox(height: 8),
                Text(
                  perf.trades.isEmpty
                      ? 'No completed trades yet.\nCompleted round trips will appear here.'
                      : 'No trades matching this filter.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TrTheme.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          )
        else
          for (final trade in filteredTrades) ...[
            _ClosedTradeCard(trade: trade),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ClosedTradeCard extends StatelessWidget {
  const _ClosedTradeCard({required this.trade});

  final ClosedTradeRecord trade;

  @override
  Widget build(BuildContext context) {
    final t = trade;
    final isWin = t.isWin;
    final pnlColor = TrTheme.pnlColor(t.realizedPnl);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                t.symbol,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(width: 6),
              TagChip(
                label: t.side == OrderSide.buy ? 'LONG' : 'SHORT',
                color: t.side == OrderSide.buy ? TrTheme.up : TrTheme.down,
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isWin ? TrTheme.up.withOpacity(0.15) : TrTheme.down.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isWin ? 'WIN' : (t.isLoss ? 'LOSS' : 'EVEN'),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isWin ? TrTheme.up : (t.isLoss ? TrTheme.down : TrTheme.textMuted),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${t.realizedPnl >= 0 ? '+' : ''}${TrTheme.money(t.realizedPnl)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: pnlColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${t.qty.toStringAsFixed(0)} shs · In \$${t.entryPrice.toStringAsFixed(2)} → Out \$${t.exitPrice.toStringAsFixed(2)}',
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '${t.pnlPct >= 0 ? '+' : ''}${t.pnlPct.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: pnlColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _formatTime(t.exitTime),
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 11),
              ),
              if (t.holdDuration.inMinutes > 0) ...[
                const Text(' · held ', style: TextStyle(color: TrTheme.textMuted, fontSize: 11)),
                Text(
                  '${t.holdDuration.inMinutes}m',
                  style: const TextStyle(color: TrTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${pad(d.month)}-${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
  }
}

// ============================================================================
// NOTIFICATION CENTER DRAWER
// ============================================================================

class _NotificationDrawer extends StatelessWidget {
  const _NotificationDrawer({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final notifs = state.notifications.history;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: TrTheme.accent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Alerts & Notifications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: TrTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                if (notifs.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      state.notifications.clearHistory();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear all', style: TextStyle(color: TrTheme.textMuted, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (notifs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none, size: 44, color: TrTheme.textMuted),
                    SizedBox(height: 8),
                    Text(
                      'No notifications yet.',
                      style: TextStyle(color: TrTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = notifs[index];
                    final color = switch (n.severity) {
                      NotificationSeverity.critical => TrTheme.down,
                      NotificationSeverity.warning => TrTheme.warn,
                      NotificationSeverity.success => TrTheme.up,
                      NotificationSeverity.info => TrTheme.accent,
                    };
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TrTheme.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                n.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: color,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _timeAgo(n.timestamp),
                                style: const TextStyle(color: TrTheme.textMuted, fontSize: 10.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.body,
                            style: const TextStyle(color: TrTheme.textPrimary, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

BoxDecoration _cardBox() => BoxDecoration(
      color: TrTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: TrTheme.outline),
    );
