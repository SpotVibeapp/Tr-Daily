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
- [x] Day-trade counter & PDT-rule warnings surfaced in UI (broker-reported
      live, estimated from paper fills; 3→warning, 4→restriction banner)
- [x] Trailing stops (ATR-based, profit-activated, ratchet-only) +
      partial take-profits (scale-out at ATR milestone)
- [x] Entry-anchored stops (stops no longer re-derive from live price each
      scan) + order fill reconciliation loop (poll → filled/rejected events)
- [x] Extended-hours trading flag (Alpaca 4am–8pm ET)

### Next up

## Phase 3 — Awareness

- [ ] Local notifications on fills, halts, and connection loss
- [ ] Portfolio screen: aggregate exposure, sector concentration
- [ ] Daily recap (PnL, win rate, rule attribution)

## Phase 4 — Cloud deployment (optional)

- [ ] Reuse the exact same engine in a Dart CLI/server (`dart run trdaily_cli`)
- [ ] Host on a free tier (Fly.io/Railway/Render) so trades run while your
      phone is off
- [ ] Remote control: the app becomes a dashboard for the hosted engine

## Phase 5 — Strategy lab

- [ ] Parameter sweeps (weights, thresholds, ATR multiples) with walk-forward
      validation to reduce overfitting
- [ ] Regime filter (only trade trending markets — ADX gate tuning)
- [ ] Paper-competition between strategy presets

## Non-goals (by design)

- ❌ Guarantees of profit — impossible; anyone promising it is selling fiction
- ❌ Storing bank credentials — bank links live at the broker, always
- ❌ Hidden fees/paid tiers — runtime stays 100% free
