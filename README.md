# Tr-Daily 📈

**An automated day-trading assistant built entirely in Flutter/Dart.**  
It scans your watchlist with proven chart-trend analysis, scores setups with an
explainable ensemble + online-ML model, applies strict risk management, and can
execute trades through a pluggable broker — **paper-trading (simulation) by
default**, with live trading as an explicit, confirmed opt-in.

> ⚠️ **Honest disclaimer — read this first**  
> No app, strategy, indicator, or AI can guarantee trading profits. Day trading
> involves substantial risk of loss, especially with leverage and automation.
> Tr-Daily ships in **paper mode** so you can prove the system on simulated
> money before ever connecting real funds. Historical/backtest performance
> never guarantees future results. Nothing here is financial advice.

---

## What it does

| Layer | What's inside |
|---|---|
| **Market data** | Yahoo Finance → bundled sample CSVs → deterministic synthetic data (auto-fallback chain), or Alpaca's free IEX feed |
| **Chart analysis** | EMA 9/21, RSI, MACD, Bollinger %B, ATR, ADX/DI±, session VWAP, Stochastic, Donchian breakouts, linear-regression trend, swing pivots, support/resistance clustering, candlestick patterns |
| **Estimator** | Fuses everything into one trend score (−1…+1), confidence, nearest S/R, and a feature vector |
| **Signal ensemble** | Weighted fusion of 7 rule signals + trend read + structure + optional online-ML probability — every decision comes with human-readable reasons |
| **AI (free, on-device)** | Online logistic regression learns next-bar direction from live data (walk-forward, no lookahead). Fully inspectable — no API fees |
| **Risk manager** | ATR stop/target, % risking per trade, position/exposure caps, min-confidence gate, **daily-loss circuit breaker** that halts trading |
| **Broker abstraction** | `PaperBroker` (instant local simulation w/ slippage) and `AlpacaBroker` (free commission-free US stocks, paper + live) |
| **Backtester** | Strict no-lookahead: signals on bar close, fills at next open, intrabar stops, gap-aware. Metrics: return, win rate, profit factor, max DD, Sharpe, expectancy, buy & hold comparison |
| **Engine** | Periodic scan → score → risk-check → execute → manage exits, during market hours (9:30–16:00 ET, holidays & early closes handled) |
| **UI** | Dark trading theme: dashboard (equity, positions, engine switch), live signals, candlestick chart with overlays, backtests, trade log, settings |

## Quick start (VS Code + Flutter)

```bash
# 1. Get dependencies
flutter pub get

# 2. Generate platform folders (android/ios/…) — repo ships lib-only on purpose
flutter create --project-name tr_daily .

# 3. Run on a device/emulator
flutter run
```

Then in the app:

1. **Dashboard → engine switch** starts paper auto-trading immediately (no keys needed).
2. **Signals** tab runs manual scans with explainable scores.
3. **Backtest** tab replays history through the same strategy with real execution rules.
4. **Settings** lets you change the watchlist, intervals, risk, and data provider.

`flutter analyze` and `flutter test` must be green — CI enforces this on every push.

### Repository layout

```
lib/
├── core/        # settings, secrets, US market-hours/DST/holiday logic
├── data/        # OHLCV models, CSV parser, Yahoo/Alpaca/synthetic sources
├── analysis/    # indicators, chart structure (pivots/S-R/patterns), estimator, ML
├── strategy/    # rule signals + weighted ensemble
├── risk/        # sizing, caps, daily-loss breaker
├── broker/      # Broker interface, PaperBroker, AlpacaBroker (paper/live)
├── engine/      # scanner, backtester, autonomous trader loop
├── state/        # AppState (ChangeNotifier hub + persistence)
└── ui/          # Material 3 screens & custom-painted charts
test/            # unit + widget tests (indicators, risk, broker, backtest, …)
assets/sample_data/  # labeled SYNTHETIC demo CSVs (offline mode)
scripts/         # regenerates demo data
docs/            # roadmap, broker/bank connection guide, strategy reference
```

The entire engine (`analysis` → `engine`) is **pure Dart with zero Flutter
imports**, so it can later be reused by a CLI or a server deployment unchanged.

## Connecting a real account (when you're ready)

**The app never asks for bank credentials.** Bank linking always happens on the
broker's website; Tr-Daily only stores an API key pair on your device.

1. Create a free account at [alpaca.markets](https://alpaca.markets) and link
   your bank in **their** dashboard (they use Plaid — same infra as Venmo).
2. Generate **paper** keys first → paste into *Settings → Broker* → Connect.
3. Run paper mode for weeks. Review the trade log honestly.
4. When (and only when) you're satisfied, generate **live** keys, switch to LIVE
   (requires typing `TRADE REAL MONEY`), and start small.

See [docs/CONNECT_BROKER.md](docs/CONNECT_BROKER.md) for the step-by-step.

## Is it really free?

Yes — every runtime piece is free:

- **Broker:** Alpaca commissions = $0 for US stocks/ETFs.
- **Data:** Yahoo Finance free endpoints / Alpaca IEX free tier / bundled samples.
- **AI:** the ML model trains on-device with plain math — no API bills, ever.
- **Infra:** runs entirely on your phone or computer (no server required).

Optional paid upgrades you don't need now: Alpaca's paid SIP data feed, a VPS
for 24/7 hosting, or a paid ML service.

## Roadmap

Phased plan in [docs/ROADMAP.md](docs/ROADMAP.md):

1. ✅ Engine + paper trading + backtests + dashboard (this repo)
2. 🔄 Alpaca live mode hardening, bracket orders, day-trade counter warnings
3. ⬜ Notifications (fill alerts, halts), long/short portfolio view
4. ⬜ Cloud deployment of the same Dart engine (run while device is off)
5. ⬜ Strategy lab (parameter sweeps), walk-forward optimizer

## Development

```bash
flutter analyze   # lint gate (CI)
flutter test      # unit + widget tests (CI)
flutter build web --no-tree-shake-icons   # full compile check (CI)
```

Contributions and your own modifications are welcome — that's the point of
shipping it as your repo.
