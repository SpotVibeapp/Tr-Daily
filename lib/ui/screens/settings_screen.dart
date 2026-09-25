import 'package:flutter/material.dart';

import '../../broker/alpaca_broker.dart';
import '../../broker/paper_broker.dart';
import '../../core/config.dart';
import '../../engine/scale.dart';
import '../../data/models.dart';
import '../../risk/risk_manager.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'home_shell.dart';

/// Broker connection, data provider, watchlist, risk & ensemble parameters.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _keyId;
  late TextEditingController _secret;
  late TextEditingController _symbolInput;
  late TextEditingController _webhookUrl;
  late TextEditingController _telegramBotToken;
  late TextEditingController _telegramChatId;
  late TextEditingController _paperCash;
  bool _obscureSecret = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.state.settings;
    _keyId = TextEditingController(text: s.keys.keyId);
    _secret = TextEditingController(text: s.keys.secretKey);
    _symbolInput = TextEditingController();
    _webhookUrl = TextEditingController(text: s.notifications.webhookUrl);
    _telegramBotToken = TextEditingController(text: s.notifications.telegramBotToken);
    _telegramChatId = TextEditingController(text: s.notifications.telegramChatId);
    _paperCash = TextEditingController(
      text: s.paperStartingCash.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _keyId.dispose();
    _secret.dispose();
    _symbolInput.dispose();
    _webhookUrl.dispose();
    _telegramBotToken.dispose();
    _telegramChatId.dispose();
    _paperCash.dispose();
    super.dispose();
  }

  void _applyPaperCash() {
    final parsed = double.tryParse(
      _paperCash.text.replaceAll(RegExp(r'[^0-9.]'), ''),
    );
    if (parsed == null || parsed < 10) return;
    widget.state.settings.paperStartingCash = parsed;
  }

  Future<void> _save({bool silent = false}) async {
    setState(() => _saving = true);
    await widget.state.updateSettings(widget.state.settings);
    if (mounted && !silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _connectAlpaca() async {
    final mode = widget.state.settings.brokerMode;
    if (mode == BrokerMode.live) {
      final confirmed = await _confirmLive();
      if (confirmed != true) return;
    }
    await widget.state.connectAlpaca(
      keyId: _keyId.text,
      secret: _secret.text,
      mode: mode,
    );
    if (mounted) {
      final ok = widget.state.settings.keys.isConfigured;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Connected (${widget.state.broker.id})'
              : 'Connection failed — check keys'),
        ),
      );
    }
  }

  Future<bool?> _confirmLive() {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TrTheme.surface,
        title: const Text('Enable LIVE trading?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live mode routes REAL orders to your funded brokerage account. '
              'Automated trading can lose money — rapidly. Tr-Daily has no way '
              'to guarantee profits.',
              style: TextStyle(color: TrTheme.textMuted, fontSize: 13),
            ),
            SizedBox(height: 12),
            Text(
              'Type TRADE REAL MONEY to confirm:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            SizedBox(height: 8),
            _ConfirmField(controller: controller),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TrTheme.down),
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim() == 'TRADE REAL MONEY'),
            child: const Text('Confirm live'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return ScreenScaffold(
      title: 'Settings',
      child: AnimatedBuilder(
        animation: st,
        builder: (context, _) {
          final s = st.settings;
          return ListView(
            children: [
              _sectionTitle('BROKER & BANK CONNECTION'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trading mode',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Connect your bank on alpaca.markets (free account), then '
                      'paste the API keys below. Tr-Daily never sees your bank '
                      'login — only these keys.',
                      style: TextStyle(
                          color: TrTheme.textMuted, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<BrokerMode>(
                      segments: const [
                        ButtonSegment(
                          value: BrokerMode.paper,
                          label: Text('Paper (safe)'),
                          icon: Icon(Icons.shield_outlined),
                        ),
                        ButtonSegment(
                          value: BrokerMode.live,
                          label: Text('LIVE'),
                          icon: Icon(Icons.bolt),
                        ),
                      ],
                      selected: {s.brokerMode},
                      onSelectionChanged: (sel) {
                        final mode = sel.first;
                        if (mode == BrokerMode.live) {
                          _confirmLive().then((ok) {
                            if (ok == true) {
                              setState(() => s.brokerMode = mode);
                              _save(silent: true);
                            }
                          });
                        } else {
                          setState(() => s.brokerMode = mode);
                          _save(silent: true);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyId,
                      decoration: const InputDecoration(
                        labelText: 'Alpaca API Key ID',
                        hintText: 'e.g. PK...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _secret,
                      obscureText: _obscureSecret,
                      decoration: InputDecoration(
                        labelText: 'Alpaca Secret Key',
                        suffixIcon: IconButton(
                          icon: Icon(_obscureSecret
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _saving ? null : _connectAlpaca,
                          icon: const Icon(Icons.link, size: 16),
                          label: Text(s.keys.isConfigured
                              ? 'Reconnect'
                              : 'Connect'),
                        ),
                        const SizedBox(width: 8),
                        if (s.keys.isConfigured)
                          OutlinedButton(
                            onPressed: () => st.disconnectBroker(),
                            child: const Text('Disconnect'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const SelectableText(
                      'Free account & bank linking → alpaca.markets/start '
                      '(opens in your browser)',
                      style: TextStyle(color: TrTheme.accent, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Broker: ${st.broker.id}'
                      '${st.settings.liveTrading ? ' · LIVE' : ' · simulated/paper'}',
                      style: const TextStyle(
                          color: TrTheme.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),

              _sectionTitle('MARKET DATA'),
              _card(
                child: Column(
                  children: [
                    DropdownButtonFormField<DataProviderMode>(
                      value: s.dataProvider,
                      dropdownColor: TrTheme.surface2,
                      decoration: const InputDecoration(
                        labelText: 'Data provider',
                        helperText:
                            'auto = Yahoo → bundled sample → synthetic fallback',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: DataProviderMode.auto,
                          child: Text('Auto (recommended)'),
                        ),
                        DropdownMenuItem(
                          value: DataProviderMode.yahoo,
                          child: Text('Yahoo Finance'),
                        ),
                        DropdownMenuItem(
                          value: DataProviderMode.alpaca,
                          child: Text('Alpaca (IEX)'),
                        ),
                        DropdownMenuItem(
                          value: DataProviderMode.synthetic,
                          child: Text('Synthetic (offline demo)'),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => s.dataProvider = v ?? DataProviderMode.auto);
                        _save(silent: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<BarInterval>(
                      value: s.interval,
                      dropdownColor: TrTheme.surface2,
                      decoration: const InputDecoration(labelText: 'Chart interval'),
                      items: const [
                        DropdownMenuItem(value: BarInterval.oneMin, child: Text('1 minute')),
                        DropdownMenuItem(value: BarInterval.fiveMin, child: Text('5 minutes')),
                        DropdownMenuItem(value: BarInterval.fifteenMin, child: Text('15 minutes')),
                        DropdownMenuItem(value: BarInterval.oneHour, child: Text('1 hour')),
                        DropdownMenuItem(value: BarInterval.oneDay, child: Text('1 day')),
                      ],
                      onChanged: (v) {
                        setState(() => s.interval = v ?? BarInterval.fiveMin);
                        _save(silent: true);
                      },
                    ),
                  ],
                ),
              ),

              _sectionTitle('WATCHLIST'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sym in s.watchlist)
                          Chip(
                            label: Text(sym),
                            backgroundColor: TrTheme.surface2,
                            side: const BorderSide(color: TrTheme.outline),
                            deleteIconColor: TrTheme.textMuted,
                            onDeleted: s.watchlist.length > 1
                                ? () {
                                    setState(() => s.watchlist.remove(sym));
                                    _save(silent: true);
                                  }
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _symbolInput,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Add symbol (e.g. META)',
                            ),
                            onSubmitted: (v) {
                              final sym = v.trim().toUpperCase();
                              if (sym.isNotEmpty &&
                                  RegExp(r'^[A-Z.\-]{1,10}$').hasMatch(sym) &&
                                  !s.watchlist.contains(sym)) {
                                setState(() => s.watchlist.add(sym));
                                _symbolInput.clear();
                                _save(silent: true);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () {
                            final sym = _symbolInput.text.trim().toUpperCase();
                            if (sym.isNotEmpty &&
                                RegExp(r'^[A-Z.\-]{1,10}$').hasMatch(sym) &&
                                !s.watchlist.contains(sym)) {
                              setState(() => s.watchlist.add(sym));
                              _symbolInput.clear();
                              _save(silent: true);
                            }
                          },
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              _sectionTitle('FIT TO CASH'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _switchRow(
                      'Adapt to available cash',
                      'Skip a name when one share costs more than this account '
                          'can buy. If nothing on the watchlist fits, scan listed '
                          'stocks that do — preferring about \$5 and under. Not '
                          'OTC penny stocks, and not a fraction of AAPL.',
                      s.fitToBudget,
                      (v) {
                        setState(() => s.fitToBudget = v);
                        if (!v) widget.state.budget.clear();
                        _save(silent: true);
                      },
                    ),
                    if (s.fitToBudget) ...[
                      const SizedBox(height: 4),
                      Text(
                        _budgetCaption(st, s),
                        style: const TextStyle(
                          color: TrTheme.textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sliderRow(
                        'Prefer stocks at or under',
                        '\$${s.budgetShareCeiling.toStringAsFixed(0)}',
                        s.budgetShareCeiling.clamp(1, 20).toDouble(),
                        1,
                        20,
                        (v) {
                          setState(() => s.budgetShareCeiling = v.roundToDouble());
                        },
                        () => _save(silent: true),
                      ),
                      const Text(
                        'Used when the watchlist itself does not fit. If no listed '
                        'name is under that price, the engine uses the next '
                        'names one share can still buy. With scaling on, a '
                        'larger account still scans some lower-priced names '
                        'and does not drop the watchlist.',
                        style: TextStyle(
                          color: TrTheme.textMuted,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              _sectionTitle('SCALE WITH BALANCE'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scaleCaption(st, s),
                      style: const TextStyle(
                        color: TrTheme.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _switchRow(
                      'Scale with today\'s starting balance',
                      'Position size and the day-trade limit follow the equity '
                          'the session started with. A gain or a setback changes '
                          'the next session, not the middle of a trade. At '
                          '\$25,000 and above, full day trading is available. '
                          'Below that, a 4th day trade in 5 business days is '
                          'skipped. Lower-priced names stay in the scan once '
                          'the account can also afford larger ones. This does '
                          'not guarantee a profit.',
                      s.scaleWithBalance,
                      (v) {
                        setState(() => s.scaleWithBalance = v);
                        widget.state.budget.clear();
                        _save(silent: true);
                      },
                    ),
                    _switchRow(
                      'Allow a larger size on a strong setup',
                      'A target at least 2× the minimum, with higher confidence, '
                          'may risk up to 2× the risk-per-trade setting. Quiet '
                          'setups stay at the normal size. Still capped by the '
                          'one-share limit and buying power.',
                      s.allowConvictionRisk,
                      (v) {
                        setState(() => s.allowConvictionRisk = v);
                        _save(silent: true);
                      },
                    ),
                  ],
                ),
              ),

              _sectionTitle('DAY TRADE'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _switchRow(
                      'Only take trades with room to move',
                      'Skip a setup when the target is too small a percent of '
                          'the share price, or when one share would risk more '
                          'than the risk setting allows. A quiet name is not '
                          'forced just because it fits the cash cap. This does '
                          'not guarantee a profit.',
                      s.dayTradeEdge,
                      (v) {
                        setState(() => s.dayTradeEdge = v);
                        _save(silent: true);
                      },
                    ),
                    if (s.dayTradeEdge)
                      _sliderRow(
                        'Minimum target',
                        '${s.minTargetPct.toStringAsFixed(1)}% of the share price',
                        s.minTargetPct.clamp(0.4, 3.0).toDouble(),
                        0.4,
                        3.0,
                        (v) {
                          setState(() => s.minTargetPct =
                              (v * 10).roundToDouble() / 10);
                        },
                        () => _save(silent: true),
                      ),
                    _switchRow(
                      'Allow overnight holds',
                      'Off by default. Leaves a position open past the close. '
                          'This is not a long-term system, and the app does not '
                          'trade options.',
                      s.allowOvernightHolds,
                      (v) {
                        setState(() => s.allowOvernightHolds = v);
                        _save(silent: true);
                      },
                    ),
                    _switchRow(
                      'Flatten before the close',
                      'Sell open positions in the last 15 minutes of the '
                          'session so a day trade does not become an overnight '
                          'hold. The app or the cloud server has to be running '
                          'then.',
                      s.flattenBeforeClose,
                      (v) {
                        setState(() => s.flattenBeforeClose = v);
                        _save(silent: true);
                      },
                    ),
                  ],
                ),
              ),

              _sectionTitle('ENGINE'),
              _card(
                child: Column(
                  children: [
                    _switchRow(
                      'Auto-start on launch',
                      'Begin scanning when the app opens',
                      s.startEngineOnLaunch,
                      (v) {
                        setState(() => s.startEngineOnLaunch = v);
                        _save(silent: true);
                      },
                    ),
                    _switchRow(
                      'Extended-hours trading',
                      'Route orders 4am–8pm ET (Alpaca; market orders only)',
                      s.extendedHours,
                      (v) {
                        setState(() => s.extendedHours = v);
                        _save(silent: true);
                      },
                    ),
                    _switchRow(
                      'Trade while market closed',
                      'Paper only — evaluate setups outside 9:30–16:00 ET',
                      s.tradeWhileClosed,
                      (v) {
                        setState(() => s.tradeWhileClosed = v);
                        _save(silent: true);
                      },
                    ),
                    _switchRow(
                      'Allow short selling',
                      'Enables SELL signals to open short positions',
                      s.allowShort,
                      (v) {
                        setState(() => s.allowShort = v);
                        final b = st.broker;
                        if (b is PaperBroker) {
                          b.setAllowShort(v);
                        }
                        _save(silent: true);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Scan every ${s.scanIntervalSeconds}s',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Slider(
                        value: s.scanIntervalSeconds.toDouble().clamp(15, 300),
                        min: 15,
                        max: 300,
                        divisions: 19,
                        label: '${s.scanIntervalSeconds}s',
                        onChanged: (v) {
                          setState(() => s.scanIntervalSeconds = v.round());
                        },
                        onChangeEnd: (_) => _save(silent: true),
                      ),
                    ),
                  ],
                ),
              ),

              _sectionTitle('RISK MANAGEMENT'),
              _card(
                child: Column(
                  children: [
                    _sliderRow(
                      'Risk per trade',
                      '${s.risk.riskPerTradePct.toStringAsFixed(2)}% of equity',
                      s.risk.riskPerTradePct,
                      0.1,
                      3.0,
                      (v) {
                        setState(() =>
                            s.risk = s.risk.copyWith(riskPerTradePct: v));
                      },
                      () => _save(silent: true),
                    ),
                    _sliderRow(
                      'Max daily loss',
                      'Halt at -${s.risk.maxDailyLossPct.toStringAsFixed(1)}%/day',
                      s.risk.maxDailyLossPct,
                      0.5,
                      10.0,
                      (v) {
                        setState(
                            () => s.risk = s.risk.copyWith(maxDailyLossPct: v));
                      },
                      () => _save(silent: true),
                    ),
                    _sliderRow(
                      'Max open positions',
                      '${s.risk.maxOpenPositions} concurrent',
                      s.risk.maxOpenPositions.toDouble(),
                      1,
                      10,
                      (v) {
                        setState(() => s.risk =
                            s.risk.copyWith(maxOpenPositions: v.round()));
                      },
                      () => _save(silent: true),
                    ),
                    _sliderRow(
                      'Stop loss',
                      '${s.risk.stopLossAtrMult.toStringAsFixed(1)} × ATR',
                      s.risk.stopLossAtrMult,
                      0.5,
                      4.0,
                      (v) {
                        setState(
                            () => s.risk = s.risk.copyWith(stopLossAtrMult: v));
                      },
                      () => _save(silent: true),
                    ),
                    _sliderRow(
                      'Take profit',
                      '${s.risk.takeProfitAtrMult.toStringAsFixed(1)} × ATR',
                      s.risk.takeProfitAtrMult,
                      1.0,
                      6.0,
                      (v) {
                        setState(() =>
                            s.risk = s.risk.copyWith(takeProfitAtrMult: v));
                      },
                      () => _save(silent: true),
                    ),
                    _sliderRow(
                      'Trailing stop',
                      s.risk.trailingStopAtrMult <= 0
                          ? 'off'
                          : '${s.risk.trailingStopAtrMult.toStringAsFixed(1)} × ATR '
                              '(activates at +${s.risk.trailingActivateAtrMult.toStringAsFixed(1)} ATR)',
                      s.risk.trailingStopAtrMult,
                      0,
                      4,
                      (v) {
                        setState(() => s.risk =
                            s.risk.copyWith(trailingStopAtrMult: v));
                      },
                      () => _save(silent: true),
                    ),
                    _switchRow(
                      'Scale-out (partial profit)',
                      'Sell ${((s.risk.scaleOutFraction) * 100).round()}% at '
                          '+${s.risk.scaleOutAtAtrMult.toStringAsFixed(1)} ATR',
                      s.risk.scaleOutEnabled,
                      (v) {
                        setState(() => s.risk = s.risk.copyWith(scaleOutEnabled: v));
                        _save(silent: true);
                      },
                    ),
                    if (s.risk.scaleOutEnabled)
                      _sliderRow(
                        'Scale-out size',
                        '${((s.risk.scaleOutFraction) * 100).round()}% of position',
                        s.risk.scaleOutFraction,
                        0.25,
                        0.75,
                        (v) {
                          setState(
                              () => s.risk = s.risk.copyWith(scaleOutFraction: v));
                        },
                        () => _save(silent: true),
                      ),
                    _sliderRow(
                      'Entry threshold',
                      'score ≥ ${s.ensemble.enterThreshold.toStringAsFixed(2)} to trade',
                      s.ensemble.enterThreshold,
                      0.2,
                      0.8,
                      (v) {
                        setState(() => s.ensemble = s.ensemble
                            .copyWithEntry(v));
                      },
                      () => _save(silent: true),
                    ),
                  ],
                ),
              ),

              _sectionTitle('AI / ML'),
              _card(
                child: Column(
                  children: [
                    _switchRow(
                      'Online ML model',
                      'Logistic model learns next-bar direction from live data',
                      s.ensemble.useMl,
                      (v) {
                        setState(() => s.ensemble = s.ensemble.copyWithMl(v));
                        _save(silent: true);
                      },
                    ),
                    _sliderRow(
                      'ML influence',
                      'weight ${s.ensemble.mlWeight.toStringAsFixed(2)} of final score',
                      s.ensemble.mlWeight,
                      0.0,
                      0.8,
                      (v) {
                        setState(() =>
                            s.ensemble = s.ensemble.copyWithMlWeight(v));
                      },
                      () => _save(silent: true),
                    ),
                  ],
                ),
              ),

              _sectionTitle('NOTIFICATIONS & WEBHOOK ALERTS'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _switchRow(
                      'Enable notifications',
                      'Receive in-app alerts and webhook pushes',
                      s.notifications.enabled,
                      (v) {
                        setState(() => s.notifications =
                            s.notifications.copyWith(enabled: v));
                        _save(silent: true);
                      },
                    ),
                    if (s.notifications.enabled) ...[
                      _switchRow(
                        'Trade fills',
                        'Alert when buys, sells or scale-outs execute',
                        s.notifications.notifyOnFills,
                        (v) {
                          setState(() => s.notifications =
                              s.notifications.copyWith(notifyOnFills: v));
                          _save(silent: true);
                        },
                      ),
                      _switchRow(
                        'Stop loss & targets',
                        'Alert when stops ratchet or profit targets hit',
                        s.notifications.notifyOnStops,
                        (v) {
                          setState(() => s.notifications =
                              s.notifications.copyWith(notifyOnStops: v));
                          _save(silent: true);
                        },
                      ),
                      _switchRow(
                        'Circuit breaker halts',
                        'Urgent alert if daily loss limit triggers',
                        s.notifications.notifyOnHalts,
                        (v) {
                          setState(() => s.notifications =
                              s.notifications.copyWith(notifyOnHalts: v));
                          _save(silent: true);
                        },
                      ),
                      _switchRow(
                        'PDT warnings',
                        'Alert when approaching 3 day-trades limit',
                        s.notifications.notifyOnPdt,
                        (v) {
                          setState(() => s.notifications =
                              s.notifications.copyWith(notifyOnPdt: v));
                          _save(silent: true);
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Free Remote Push Alerts (Phone / Desktop)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Receive real-time phone notifications while running 24/7 in the cloud. '
                        'Create a free Discord webhook or Telegram bot — completely free with zero subscription fees.',
                        style: TextStyle(color: TrTheme.textMuted, fontSize: 11.5, height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _webhookUrl,
                        decoration: const InputDecoration(
                          labelText: 'Discord or Slack Webhook URL',
                          hintText: 'https://discord.com/api/webhooks/...',
                        ),
                        onChanged: (v) {
                          s.notifications = s.notifications.copyWith(webhookUrl: v.trim());
                          _save(silent: true);
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _telegramBotToken,
                              decoration: const InputDecoration(
                                labelText: 'Telegram Bot Token',
                                hintText: '123456:ABC-DEF...',
                              ),
                              onChanged: (v) {
                                s.notifications = s.notifications.copyWith(telegramBotToken: v.trim());
                                _save(silent: true);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _telegramChatId,
                              decoration: const InputDecoration(
                                labelText: 'Telegram Chat ID',
                                hintText: 'e.g. 987654321',
                              ),
                              onChanged: (v) {
                                s.notifications = s.notifications.copyWith(telegramChatId: v.trim());
                                _save(silent: true);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.send, size: 15),
                        label: const Text('Send Test Alert'),
                        onPressed: () async {
                          final ok = await st.notifications.sendTestNotification();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'Test alert sent! Check your notification center or webhook.'
                                    : 'Notifications are disabled in settings.'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),

              _sectionTitle('PAPER ACCOUNT'),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash: ${TrTheme.money(st.account.cash)} · '
                      'equity ${TrTheme.money(st.account.equity)}',
                      style: const TextStyle(
                          color: TrTheme.textMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _paperCash,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Paper cash',
                        helperText:
                            'Local simulator only. Alpaca funds are not changed. Live mode must be off.',
                      ),
                      onEditingComplete: _applyPaperCash,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final amount in <double>[
                          100,
                          500,
                          1000,
                          2500,
                          5000,
                          10000,
                          25000,
                          50000,
                        ])
                          ActionChip(
                            label: Text('\$${amount.toStringAsFixed(0)}'),
                            onPressed: () {
                              _paperCash.text = amount.toStringAsFixed(0);
                              _setPaperCash(amount);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () {
                        final parsed = double.tryParse(
                          _paperCash.text.replaceAll(RegExp(r'[^0-9.]'), ''),
                        );
                        if (parsed == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enter a paper cash amount first.'),
                            ),
                          );
                          return;
                        }
                        _setPaperCash(parsed);
                      },
                      icon: const Icon(Icons.account_balance_wallet, size: 16),
                      label: const Text('Set paper cash'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _confirmReset(),
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Reset paper account'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _previewSmallAccount,
                      icon: const Icon(Icons.savings_outlined, size: 16),
                      label: const Text('Preview with \$100 paper cash'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  String _scaleCaption(AppState st, AppSettings s) {
    if (!s.scaleWithBalance) {
      return 'Scaling is off. Size uses the current equity, and a large '
          'balance does not add lower-priced names.';
    }
    final plan = scalePlan(
      account: st.account,
      settings: s,
      dayTradeCount: 0,
    );
    return plan.summary;
  }

  String _budgetCaption(AppState st, AppSettings s) {
    final maxPx = maxAffordableSharePrice(
      st.account,
      s.risk,
      sizingEquity: s.scaleWithBalance ? dayStartEquityOf(st.account) : null,
    );
    final ceiling = s.budgetShareCeiling <= 0 ? 5.0 : s.budgetShareCeiling;
    if (st.account.equity <= 0 && st.account.buyingPower <= 0) {
      return 'Connect an account or start paper trading to see the share-price cap.';
    }
    return 'Right now one new share can cost up to ${TrTheme.money(maxPx)} '
        '(${s.risk.maxPositionPct.round()}% of today\'s start, or buying power '
        'if that is lower). Backup names prefer ${TrTheme.money(ceiling)} and '
        'under. Set paper cash to try \$100, \$1,000, or \$25,000. A larger '
        'balance still scans some lower-priced names when scaling is on.';
  }

  Future<void> _setPaperCash(double amount) async {
    if (amount < 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least \$10 of paper cash.')),
      );
      return;
    }
    if (widget.state.settings.liveTrading) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Live mode is on. Switch to paper before changing test cash.',
          ),
        ),
      );
      return;
    }
    final shown = amount.toStringAsFixed(0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TrTheme.surface,
        title: Text('Set paper cash to \$$shown?'),
        content: Text(
          'Replaces the local simulator with \$$shown and clears its positions. '
          'Alpaca funds are not changed. The next scan sizes from this balance. '
          'This does not guarantee a profit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Use \$$shown'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.state.settings.paperStartingCash = amount;
    widget.state.settings.useLocalPaper = true;
    _paperCash.text = shown;
    widget.state.budget.clear();
    await _save(silent: true);
    await widget.state.resetPaperAccount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Paper account is \$$shown.')),
    );
  }

  Future<void> _previewSmallAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TrTheme.surface,
        title: const Text('Preview a \$100 account?'),
        content: const Text(
          'Replaces the simulated paper account with \$100 cash so you can see '
          'which names fit. Live Alpaca funds are not touched. Any open paper '
          'positions are cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use \$100'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.state.settings.paperStartingCash = 100;
    widget.state.settings.fitToBudget = true;
    _paperCash.text = '100';
    widget.state.budget.clear();
    await _save(silent: true);
    await widget.state.resetPaperAccount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Paper account is \$100. Names over about \$25 are skipped.',
        ),
      ),
    );
  }

  Future<void> _confirmReset() async {
    _applyPaperCash();
    await _save(silent: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TrTheme.surface,
        title: const Text('Reset paper account?'),
        content: const Text(
            'Clears all simulated positions, fills and cash back to the starting balance.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TrTheme.down),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.resetPaperAccount();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Paper account reset')));
      }
    }
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            color: TrTheme.textMuted,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TrTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TrTheme.outline),
        ),
        child: child,
      );

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: TrTheme.textMuted, fontSize: 11.5)),
        value: value,
        onChanged: onChanged,
      );

  Widget _sliderRow(
    String title,
    String valueLabel,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    VoidCallback onEnd,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 14)),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                    color: TrTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: (_) => onEnd(),
          ),
        ],
      );
}

class _ConfirmField extends StatelessWidget {
  const _ConfirmField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(letterSpacing: 1.5),
      decoration: const InputDecoration(hintText: 'TRADE REAL MONEY'),
    );
  }
}
