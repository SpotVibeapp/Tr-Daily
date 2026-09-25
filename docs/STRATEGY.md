# Strategy Reference

How Tr-Daily turns charts into decisions — transparently, with no holy grail
claims.

## 1. Inputs

The auto-trader checks the watchlist every pass and also walks listed US stocks and ETFs, a slice at a time. A name does not have to be on the watchlist to be traded. OTC names are not included. It does not chart the entire market in one minute.

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
- **News**: company headlines and a world-news feed, reviewed on every scan.
  A severe recent company story can block or close that name. A feed failure
  skips new trades in names that could not be checked. Developing stories are
  listed, not treated as a forecast. Headlines can be late or wrong. This does
  not remove the risk of a loss.

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
| Risk per trade | 0.5% of equity | Sized against the stop distance. Installs still on the old 0.75% default move to 0.5%; a value you picked is kept. |
| Stop loss | 1.5 × ATR | Where the thesis is wrong |
| Take profit | 2.5 × ATR | ~1.67:1 reward-to-risk floor |
| Max open positions | 1 | Concentration cap. One at a time while starting out. Old default of 3 moves to 1; a value you picked is kept. |
| Min share price | $1.00 | No new trades under $1, where a 1¢ tick is a large percentage |
| Min dollar volume | $1M a session | No new trades in thinly traded names. On Alpaca's free IEX feed the floor is scaled to IEX's ~2% share of volume. Held positions are still managed. |
| Max exposure | 60% of equity | Gross cap |
| Max position | 25% of equity | Single-name cap |
| **Max daily loss** | **2%** | **Engine halts until next session** |
| Min confidence | 35% | No low-conviction entries |
| Fit to cash | on | Skip a name when 1 share exceeds 25% of equity or buying power. If the watchlist does not fit, scan listed names, preferring ≤ $5. Not OTC, not fractional shares of the big names. |
| Day-trade edge | on, 1% target | Skip a setup whose target is under 1% of the share price, or whose forced 1-share size risks more than 2.5× the risk-per-trade setting. Flatten in the last 15 minutes so a day trade is not held overnight. Not a profit guarantee. |
| Scale with balance | on | Size from the session's starting equity, not the intraday mark. Under $2,000: small-account range, no shorts. From $2,000 to $25,000: step up, and still scan lower-priced names. At $25,000: top sizing band. A strong target may use up to 2× the risk setting. Not a profit guarantee. Options are not traded. |

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

## 5b. Day-trade count (removed)

FINRA retired the pattern-day-trader rule on June 4, 2026. Brokers no longer
count day trades or require $25,000 to day trade; intraday margin rules apply
instead (Alpaca: margin from $2,000). Tr-Daily no longer caps entries by day
trade count, in paper or live. The broker still decides whether to accept an
order.

## 5c. Go-live checks

Portfolio → Performance and the live-mode confirmation show whether the paper
record meets four minimums: at least 50 completed paper trades, a positive
average trade after costs, profit factor at least 1.2, and worst drawdown
within 15%. They count the in-app paper account only. Passing them is not a
forecast of live results.

## 6. Execution realism

- **Backtest:** decisions at close of bar `t`, fills at **open of `t+1`**,
  intrabar stops checked against high/low, same-bar stop+target → stop first,
  gap-through-stop fills at the worse open, slippage on every fill.
- **Costs:** a simulated market buy pays the ask and a sell gets the bid when
  a quote is known. The cost floor is the larger of the slippage setting and
  half a tick (½¢ on a stock over $1), so cheap stocks are not given
  near-free fills. The backtester uses the same floor.
- **Paper broker:** instant fills at those prices, no margin. Each fill logs
  the price the signal saw and what the fill cost.
- **Stops overnight:** a live entry's broker-side stop and target are sent
  good-till-cancelled. If the app is closed before the end-of-day flatten, the
  stop is still at the broker. Closing a position cancels that name's working
  orders first.
- **Live:** market orders to Alpaca during the regular session (raw fills, real
  spreads/latency — usually *worse* than simulation). A new trade is skipped
  when the bid-ask spread is 25% or more of the profit-point distance, or when
  the quote cannot be read. Outside the regular session the app does not send
  a market order. An extended-hours order is a limit at the bid or ask, or it
  is not sent. Demo prices and a bar older than three intervals do not open a
  trade. A name with an order already working does not get a second order.

## 7. What this is NOT

- Not a guarantee of profit; expect losing streaks and drawdowns.
- Not HFT: latency-sensitive strategies are out of scope.
- Not a substitute for your own judgment: watch the log, especially early.
