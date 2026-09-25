import 'package:flutter/material.dart';

import '../../broker/alpaca_broker.dart';
import '../../core/pdt.dart';
import '../../core/time.dart';
import '../../data/models.dart';
import '../../engine/budget.dart';
import '../../engine/scale.dart';
import '../../risk/risk_manager.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'portfolio_screen.dart';

/// Account overview, engine controls, open positions.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Tr-Daily',
      actions: [
        _SessionBadge(state: state),
        const SizedBox(width: 8),
        _ModeChip(state: state),
        const SizedBox(width: 4),
        _NotificationBell(state: state),
      ],
      trailing: _EngineBanner(state: state),
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final a = state.account;
          final dayPnl = a.dayPnl;
          final dayPct = a.dayPnlPct;
          return RefreshIndicator(
            color: TrTheme.accent,
            onRefresh: () async {
              await state.refreshAccount();
              await state.scanNow();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // ---- account card ----
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EQUITY',
                        style: TextStyle(
                          color: TrTheme.textMuted,
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            TrTheme.money(a.equity),
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
                              '${dayPnl >= 0 ? '+' : ''}${dayPnl.toStringAsFixed(2)} '
                              '(${dayPct.toStringAsFixed(2)}%) today',
                              style: TextStyle(
                                color: TrTheme.pnlColor(dayPnl),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (state.settings.scaleWithBalance) ...[
                        const SizedBox(height: 8),
                        Text(
                          _scaleLine(state),
                          style: const TextStyle(
                            color: TrTheme.textMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              label: 'Buying power',
                              value: TrTheme.money(a.buyingPower),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatTile(
                              label: 'Cash',
                              value: TrTheme.money(a.cash),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatTile(
                              label: 'Open',
                              value: '${state.positions.length}'
                                  '/${state.settings.risk.maxOpenPositions}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ---- PDT warning (only near/over the limit) ----
                if (_pdt().isNearLimit || _pdt().isRestricted)
                  _PdtBanner(snapshot: _pdt()),

                // ---- engine row ----
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: _cardDecoration(),
                  child: Row(
                    children: [
                      Icon(
                        state.engineRunning ? Icons.play_circle : Icons.pause_circle,
                        color: state.engineRunning ? TrTheme.up : TrTheme.textMuted,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.engineRunning
                                  ? 'Auto-trader running'
                                  : 'Auto-trader idle',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              state.engineRunning
                                  ? (state.backgroundRunning
                                      ? 'Keeps scanning if you close the app. Notification stays up.'
                                      : 'Scanning ${state.settings.watchlist.length} watchlist'
                                          '${state.budget.last.sleeve.isEmpty ? '' : ' + ${state.budget.last.sleeve.length} budget'}'
                                          ' names every ${state.settings.scanIntervalSeconds}s')
                                  : 'Start it to scan & trade automatically',
                              style: const TextStyle(
                                color: TrTheme.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: state.engineRunning,
                        onChanged: (_) {
                          state.engineRunning
                              ? state.stopEngine()
                              : state.startEngine();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                _BudgetBanner(state: state),

                if (state.risk.isHalted)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TrTheme.down.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TrTheme.down.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: TrTheme.down),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Trading halted: ${state.risk.haltReason ?? 'daily loss limit'}',
                            style: const TextStyle(
                              color: TrTheme.down,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            state.risk.resetHalt();
                            state.notifyManually();
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'OPEN POSITIONS',
                      style: TextStyle(
                        color: TrTheme.textMuted,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: state.scanning
                          ? null
                          : () => state.scanNow(),
                      icon: state.scanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: TrTheme.accent),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(state.scanning ? 'Scanning…' : 'Scan now'),
                    ),
                  ],
                ),
                if (state.positions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: _cardDecoration(),
                    child: const Column(
                      children: [
                        Icon(Icons.hourglass_empty, color: TrTheme.textMuted, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'No open positions.\nRun a scan or start the auto-trader.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: TrTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                for (final p in state.positions) _PositionCard(position: p),
                const SizedBox(height: 12),
                if (state.lastError != null)
                  Text(
                    '⚠ ${state.lastError}',
                    style: const TextStyle(color: TrTheme.warn, fontSize: 12),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Pattern-day-trader awareness: broker-reported (live) or estimated from
  /// the paper fill log.
  String _scaleLine(AppState state) {
    final plan = scalePlan(
      account: state.account,
      settings: state.settings,
      dayTradeCount: 0,
    );
    final band = switch (plan.band) {
      AccountBand.fullDayTrade => 'Full day trading is available.',
      AccountBand.building =>
        'Building — full day trading starts at \$25,000.',
      AccountBand.micro => 'Small-account range until the next session is higher.',
    };
    return 'Sized from today\'s start ${TrTheme.money(plan.dayStartEquity)}. $band';
  }

  PdtSnapshot _pdt() {
    final equity = state.settings.scaleWithBalance
        ? dayStartEquityOf(state.account)
        : state.account.equity;
    final brokerIsLive = state.broker.mode == BrokerMode.live;
    if (brokerIsLive) {
      return reportedPdt(
        dayTradeCount: state.account.dayTradeCount,
        equity: equity,
      );
    }
    return estimatePaperPdt(
      fills: [
        for (final f in state.tradeLog)
          (symbol: f.symbol, time: f.time, isBuy: f.side == OrderSide.buy),
      ],
      equity: equity,
      now: DateTime.now(),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: TrTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrTheme.outline),
      );
}

class _PdtBanner extends StatelessWidget {
  const _PdtBanner({required this.snapshot});

  final PdtSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = snapshot.isRestricted ? TrTheme.down : TrTheme.warn;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.gavel, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              snapshot.note,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final pnl = p.unrealizedPnl;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TrTheme.outline),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: TrTheme.textPrimary,
                ),
              ),
              Text(
                '${p.short ? 'SHORT' : 'LONG'} ${p.qty.toStringAsFixed(0)} @ '
                '\$${p.avgEntryPrice.toStringAsFixed(2)}',
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 11.5),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${p.currentPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)} '
                '(${p.unrealizedPnlPct.toStringAsFixed(2)}%)',
                style: TextStyle(
                  color: TrTheme.pnlColor(pnl),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionBadge extends StatelessWidget {
  const _SessionBadge({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final open = isMarketOpen(now);
    return TagChip(
      label: sessionLabel(now),
      color: open ? TrTheme.up : TrTheme.warn,
    );
  }
}

class _BudgetBanner extends StatelessWidget {
  const _BudgetBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.settings.fitToBudget) return const SizedBox.shrink();
    final maxPx = maxAffordableSharePrice(
      state.account,
      state.settings.risk,
      sizingEquity: state.settings.scaleWithBalance
          ? dayStartEquityOf(state.account)
          : null,
    );
    final snap = state.budget.last;
    final small = maxPx > 0 && maxPx < 80;
    if (!small && !snap.active) return const SizedBox.shrink();
    final ceiling = state.settings.budgetShareCeiling <= 0
        ? BudgetSession.defaultPreferredCeiling
        : state.settings.budgetShareCeiling;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TrTheme.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TrTheme.accent.withOpacity(0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FITTING TRADES TO CASH',
              style: TextStyle(
                color: TrTheme.accent,
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'One new share can cost up to ${TrTheme.money(maxPx)} '
              '(${state.settings.risk.maxPositionPct.round()}% of equity). '
              'More expensive watchlist names are skipped. If none fit, listed '
              'stocks at or under ${TrTheme.money(ceiling)} are scanned instead. '
              '${state.settings.scaleWithBalance ? 'A larger balance still scans some lower-priced names. ' : ''}'
              'Not OTC penny stocks. This does not guarantee a profit.',
              style: const TextStyle(
                color: TrTheme.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            if (snap.sleeve.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Budget names: ${snap.sleeve.join(', ')}',
                style: const TextStyle(
                  color: TrTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ] else if (snap.summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                snap.summary,
                style: const TextStyle(color: TrTheme.textMuted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final live = state.broker.mode == BrokerMode.live;
    return TagChip(
      label: live ? 'LIVE' : 'PAPER',
      color: live ? TrTheme.live : TrTheme.accent,
    );
  }
}

class _EngineBanner extends StatelessWidget {
  const _EngineBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final last = state.engine?.lastScanAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: TrTheme.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        last == null
            ? 'no scan yet'
            : 'last scan ${formatEasternTime(last)}',
        style: const TextStyle(color: TrTheme.textMuted, fontSize: 11),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final unread = state.notifications.unreadCount;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined, color: TrTheme.textMuted, size: 20),
          onPressed: () => showAppNotifications(context, state),
        ),
        if (unread > 0)
          PositionedDirectional(
            top: 6,
            end: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: TrTheme.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
