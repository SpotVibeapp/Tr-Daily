# Connecting Your Bank & Broker (safe, free, ~10 minutes)

Tr-Daily executes trades through a **broker API**, not by touching your bank
directly. Your bank credentials always stay between you and the broker's
bank-linking provider (Plaid — the same company Venmo/CashApp use).

```
┌────────────┐   API keys only   ┌─────────────────┐   funded   ┌──────────┐
│  Tr-Daily  │ ────────────────► │ Alpaca (broker) │ ◄───────── │ Your bank│
│  (on your  │   (key id +       │ links the bank  │  via Plaid │ account  │
│   phone)   │    secret)        │ on THEIR site   │  on their  │          │
└────────────┘                   └─────────────────┘  website   └──────────┘
```

## Step 1 — Create the free Alpaca account

1. Go to <https://alpaca.markets> → **Sign up** (free, no minimums).
2. Complete their signup. For **paper trading** you do not need to fund
   anything — paper accounts start with $100k of simulated cash.
3. When you later want live trading: complete their identity verification and
   link your bank **inside the Alpaca dashboard** (their "Transfer" / banking
   section, powered by Plaid).

## Step 2 — Generate API keys

1. Alpaca dashboard → **Home → View API keys** (or *Paper → API Keys* first).
2. Copy the **Key ID** and **Secret Key**.
   - Paper keys work only against paper-money endpoints.
   - Live keys work only after your account is funded & approved.

## Step 3 — Paste them into Tr-Daily

1. Open Tr-Daily → **Settings → Broker & bank connection**
2. Choose **Paper (safe)** — recommended for at least a few weeks.
3. Paste Key ID + Secret → **Connect**.
4. The status line under the button shows `alpaca-paper` when connected.

Storage: keys are kept in your device's shared preferences via the settings
store and are **never committed to git** (`.gitignore` blocks secret files).

## Step 4 — Prove it in paper mode

- Run the auto-trader on paper for **≥ 2 weeks / ≥ 30 trades**.
- Compare the in-app trade log with what you'd realistically feel losing.
- Run backtests and read the metrics honestly (win rate ≠ profitability —
  check profit factor, max drawdown, expectancy).

## Step 5 — Going live (only if you choose)

1. Settings → **Segmented button → LIVE**.
2. You'll be asked to type `TRADE REAL MONEY` — deliberate friction.
3. Paste **live keys** (generated after funding) → Connect.
4. Start with the lowest risk settings (`risk per trade ≤ 0.5%`,
   `max daily loss ≤ 1%`). The circuit breaker halts automatically.

> Remember: automation amplifies both wins and mistakes. A bug, a runaway
> loop, or a bad regime can lose money quickly in live mode. Paper first.
> Never fund an account with money you cannot afford to lose.

## Revoking access anytime

- Alpaca dashboard → API keys → **Delete/revoke** → Tr-Daily loses access
  instantly. Also disconnect from within the app's Settings screen.
