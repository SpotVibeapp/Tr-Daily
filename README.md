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
| **Notifications** | In-app notification center + 100% free remote phone push via Discord webhooks and Telegram bots on fills, stops, and halts |
| **Portfolio** | Asset allocation breakdown, visual capital progress bar, live P&L, stop/target tracking, and round-trip trade performance history |
| **24/7 Cloud** | Headless server runtime (`bin/tr_daily_server.dart`), Docker container (~30MB), systemd service, and HTTP healthcheck (:8080) |
| **UI** | Dark trading theme: dashboard, portfolio, live signals, candlestick chart with overlays, backtest lab, history, settings |

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
5. **Small account:** Fit-to-cash is on by default. If one share of the watchlist costs more than 25% of equity, those names are skipped and the engine scans listed stocks that fit, preferring about $5 and under.
6. **Test any paper balance:** Settings → Paper account. Pick $100, $1,000, $25,000, or type an amount, then Set paper cash. That replaces the local simulator only. Alpaca funds are not changed. Turn live mode off first.
7. **Scale with the day's start:** Size follows the equity the session started with, so a gain or a setback changes the next session instead of freezing the app in a small-account habit. At $25,000 and above, full day trading is available. Below that, a 4th day trade in 5 business days is skipped. Lower-priced names stay in the scan when the balance is high. A strong setup may use up to 2× the risk setting. Overnight holds are optional and off by default. This does not guarantee a profit, and options are not traded.
8. **Day trades, not holds:** Settings → Day trade skips quiet names whose target is under 1% of the share price, and skips a share that would risk more than the risk setting allows. Open positions are sold in the last 15 minutes unless overnight holds are on. This does not guarantee a profit.
9. **Leave or close the app:** On Android, start the engine and leave “Keep running when closed” on. This is the same for paper and live. A notification stays up and the scan continues if you leave the app, lock the screen, or swipe it away. Live orders can still be sent until you turn the engine off or tap Stop on the notification. Force Stop in Android settings stops it. The phone being off stops it. A closed market does not stop the scan. New live trades wait for the regular session, or 4:00 a.m.–8:00 p.m. ET if extended hours are on. This does not guarantee a profit.
10. **News on every scan:** Company headlines and world news are read before a new trade and again while a position is open. A severe, recent company story can block a new trade or close that name. If headlines for a name cannot be read, a new trade in that name waits. Stories that are building before the chart confirms are listed as developing. They are not automatic buys. Headlines can be late, missing, or wrong. This does not remove the risk of a loss, and it does not guarantee a profit.
11. **Daily goal and loss stop:** Settings → Risk. The profit goal defaults to 30% of the day. Reaching it does not stop scanning, does not refuse more profit, and does not increase size to chase it. The loss stop defaults to 2% and is a slider. Hitting it closes positions and blocks new trades until the next session. Per trade, the stop and profit point are ATR multiples, not fixed percents. The profit point sells the trade unless “let winners run” is on, which locks a stop there instead. This does not guarantee a 30% day, or any profit.
12. **Cost gate:** A new trade is skipped when the bid-ask spread is 25% or more of the distance to the profit point, or when the spread cannot be read. Outside 9:30–4:00 p.m. ET the app does not send a market order. In the extended window it can send a limit at the bid or ask. If that quote is missing, the order is not sent. This does not remove the risk of a loss.
13. **Faster, cleaner scans:** Names are read a few at a time so a scan is more likely to finish before the next one. If Alpaca keys are saved, that feed is tried before Yahoo. A price from demo data does not open a trade. A bar that is too old does not open a trade during the session. A name with an order already working does not get a second order. This does not guarantee a profit.

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

## Running 24/7 in the Cloud (Free)

To run automated trades while your phone is asleep or turned off:

```bash
# Run headless server locally or in a VPS
dart run bin/tr_daily_server.dart

# Or run with Docker
docker compose up -d
```

See [docs/CLOUD_DEPLOYMENT.md](docs/CLOUD_DEPLOYMENT.md) for complete step-by-step instructions on setting up 100% free hosting with Oracle Cloud Always-Free or Render/Fly.io, plus setting up free Discord or Telegram phone push alerts.

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

## Phone install

Sideload `artifacts/apk/Tr-Daily-v*-arm64-v8a.apk` (about 19 MB). Use the raw file, not the GitHub preview page. If tapping Install leaves the old app in place, uninstall Tr-Daily once and install again. Builds before v0.1.9 were each signed with a different key, so Android will not update them. Uninstalling removes on-phone settings and the paper log. It does not close positions at the broker.

## Development

```bash
flutter analyze   # lint gate (CI)
flutter test      # unit + widget tests (CI)
flutter build web --no-tree-shake-icons   # full compile check (CI)
```

Contributions and your own modifications are welcome — that's the point of
shipping it as your repo.
