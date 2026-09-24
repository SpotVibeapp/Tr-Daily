# Strategy Reference

How Tr-Daily turns charts into decisions — transparently, with no holy grail
claims.

## 1. Inputs

Per symbol, on the configured interval (default 5-minute bars):

- **EMA 9/21** trend posture and spread
- **MACD(12,26,9)** histogram sign + acceleration
- **RSI(14)** extremes (≤30 oversold / ≥70 overbought) + mid-zone momentum
- **Bollinger(20,2)** %B — band-walk vs mean-reversion lean
- **Donchian(20)** breakout: fresh 20-bar high/low
- **Session VWAP** distance (institutional benchmark for day trades)
- **Stochastic(14,3)** cross out of extremes
- **ADX/DI±(14)** trend *strength* (gates how much directional signals count)
- **ATR(14)** for stops/position sizing
- **Structure**: swing pivots (k=3, confirmation-delayed — no lookahead),
  clustered support/resistance, least-squares trendlines (R²-qualified)
- **Candlestick patterns**: engulfing, hammer/star, pins, inside bars, strong
  directional bars

## 2. Scoring

```
rules      = Σ(weight_i × signal_i) / Σ(weight_i)        ∈ [-1, 1]
trend      = structure-aware estimator read               ∈ [-1, 1]
base       = 0.55 × rules + 0.45 × trend + structure lean
score      = (1 - mlW) × base + mlW × (2·P(next bar up) - 1)
confidence = 0.45·trendQuality + 0.30·|signal avg| + 0.15·ADX gate + ML certainty
```

- **Entry** requires `|score| ≥ enterThreshold` (default 0.45) **and**
  `confidence ≥ minConfidence` (default 0.35).
- Every SignalScore lists its reasons and per-rule breakdown in the UI — if you
  can't explain a trade, don't take it.

## 3. AI layer (free, on-device)

- Features (14) from the estimator → **online logistic regression** trained
  with SGD, L2-regularized, running standardization.
- Labels: next bar closes up = 1. Training at time T only ever uses examples
  whose label bar has already closed (strict walk-forward, no lookahead).
- The model's probability is blended with weight `mlWeight` (default 0.6, set
  to 0 to disable).
- Honest limits: it's a *small* linear model — it adapts fast, overfits little,
  but won't capture black-swan dynamics. Sample count is displayed next to
  every prediction (`n=…`), and predictions are muted until n ≥ 60.

## 4. Risk rules (defaults)

| Control | Default | Meaning |
|---|---|---|
| Risk per trade | 0.75% of equity | Sized against the stop distance |
| Stop loss | 1.5 × ATR | Where the thesis is wrong |
| Take profit | 2.5 × ATR | ~1.67:1 reward-to-risk floor |
| Max open positions | 3 | Concentration cap |
| Max exposure | 60% of equity | Gross cap |
| Max position | 25% of equity | Single-name cap |
| **Max daily loss** | **2%** | **Engine halts until next session** |
| Min confidence | 35% | No low-conviction entries |

## 5. Exit logic

Stops and targets are **anchored at entry** (the current scan's suggestions
never overwrite them — a stop sits where the thesis was invalidated, not
"1.5 ATR behind wherever price drifted to").

1. Hard stop / target (checked against live price; brackets on Alpaca live).
2. **Trailing stop** (default 2 × ATR behind the best price since entry,
   activated once the position is +1 × ATR in profit; ratchets in favor only).
3. **Scale-out** (default): sell 50% at +1.5 × ATR — locks partial profit,
   moves the trade to "free money" psychology-wise.
4. Score collapses to `|score| ≤ 0.10` → signal no longer supports the trade.
5. Stance flips → close + attempt opposite entry (still risk-checked).
6. Daily-loss breaker → flatten everything, halt, re-arm next day.

## 5b. PDT awareness (Phase 2)

US pattern-day-trader rule: 4+ round trips in 5 business days without $25k
equity. The dashboard shows a warning at 3 and a restriction banner at 4
(broker-reported for live accounts, estimated from the paper fill log).
Tr-Daily warns — the broker enforces.

## 6. Execution realism

- **Backtest:** decisions at close of bar `t`, fills at **open of `t+1`**,
  intrabar stops checked against high/low, same-bar stop+target → stop first,
  gap-through-stop fills at the worse open, slippage on every fill.
- **Paper broker:** instant fills at last price ± slippage, no margin.
- **Live:** market orders to Alpaca (raw fills, real spreads/latency — usually
  *worse* than simulation).

## 7. What this is NOT

- Not a guarantee of profit; expect losing streaks and drawdowns.
- Not HFT: latency-sensitive strategies are out of scope.
- Not a substitute for your own judgment: watch the log, especially early.
