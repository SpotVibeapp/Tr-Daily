# Tr-Daily Roadmap

Built in verifiable steps. Each phase ships working, tested code before the
next begins.

## Phase 1 — Foundation (✅ shipped)

- [x] Pure-Dart engine (indicators, structure, estimator) with causality tests
- [x] Explainable signal ensemble + online-ML overlay (free, on-device)
- [x] Risk manager: ATR stops, sizing, caps, daily-loss circuit breaker
- [x] `PaperBroker` with slippage, shorts, persistence, roundtrip tests
- [x] `AlpacaBroker` REST client (paper + live endpoints, bracket orders)
- [x] Backtester with no-lookahead execution + full metrics
- [x] Autonomous `TraderEngine` loop (scan → score → risk → execute → exits)
- [x] Material 3 UI: dashboard, signals, chart, backtest, history, settings
- [x] Market-hours logic incl. DST, holidays, early closes
- [x] CI: `flutter analyze` + `flutter test` + web compile check

## Phase 2 — Live-trading hardening (✅ shipped)

- [x] Alpaca wire-contract tests (fake HTTP client: payloads, brackets,
      extended-hours, error mapping, fill reconciliation endpoints)
- [x] ~~Day-trade counter & PDT-rule warnings~~ (removed: FINRA retired the
      PDT rule on June 4, 2026)
- [x] Trailing stops (ATR-based, profit-activated, ratchet-only) +
      partial take-profits (scale-out at ATR milestone)
- [x] Entry-anchored stops (stops no longer re-derive from live price each
      scan) + order fill reconciliation loop (poll → filled/rejected events)
- [x] Extended-hours trading flag (Alpaca 4am–8pm ET)

## Phase 3 — Portfolio & Awareness (✅ shipped)

- [x] Dedicated **Portfolio Screen**:
      - Live P&L tracking (unrealized & realized), equity, buying power
      - Capital allocation breakdown with visual multi-segment asset bar
      - Detailed open positions view with entry-anchored stop loss, target, and trailing peak
      - One-tap manual position close with confirmation dialog
      - Round-trip trade history with win rate, profit factor, average win/loss, hold duration
- [x] **In-App & Remote Push Notifications**:
      - Real-time alerts on trade fills, stop hits, profit targets, and circuit breaker halts
      - In-app notification center drawer with unread badges
      - 100% free remote push alerts via Discord webhooks and Telegram bots to user's phone
      - Configurable notification toggles and connectivity test in settings

## Phase 4 — 24/7 Cloud Deployment (✅ shipped)

- [x] Headless pure-Dart engine runner (`bin/tr_daily_server.dart`)
- [x] Ultra-lightweight multi-stage `Dockerfile` (~30 MB container) and `docker-compose.yml`
- [x] Linux systemd service configuration (`deploy/tr-daily.service`)
- [x] HTTP healthcheck and live status API (`/health` and `/status` on port 8080)
- [x] Complete free-tier setup guide (`docs/CLOUD_DEPLOYMENT.md` covering Oracle Cloud Always-Free, Render, Fly.io, and local Raspberry Pi)

### Next up

## Phase 5 — Strategy lab

- [ ] Parameter sweeps (weights, thresholds, ATR multiples) with walk-forward
      validation to reduce overfitting
- [ ] Regime filter (only trade trending markets — ADX gate tuning)
- [ ] Paper-competition between strategy presets

## Non-goals (by design)

- ❌ Guarantees of profit — impossible; anyone promising it is selling fiction
- ❌ Storing bank credentials — bank links live at the broker, always
- ❌ Hidden fees/paid tiers — runtime stays 100% free
