#!/usr/bin/env python3
"""Generate deterministic *synthetic* OHLCV demo CSVs for assets/sample_data.

These are NOT real market data — they are regime-switching random walks with
approximate starting price levels, used so the app (and reviewers) can explore
charts/backtests offline. Regenerate with:

    python3 scripts/gen_sample_data.py
"""
import math
import os
import random

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sample_data")

# symbol -> (start price, annual drift, annual vol, seed)
UNIVERSE = {
    "AAPL": (190.0, 0.10, 0.28, 101),
    "NVDA": (120.0, 0.25, 0.55, 202),
    "MSFT": (420.0, 0.12, 0.24, 303),
    "TSLA": (250.0, 0.05, 0.60, 404),
    "AMZN": (185.0, 0.14, 0.30, 505),
}

TRADING_DAYS = 420


def gen(symbol: str, start: float, drift: float, vol: float, seed: int) -> str:
    rnd = random.Random(seed)
    dt = 1 / 252
    price = start
    # Regime switching drift.
    regime_drift = drift
    lines = [
        f"# {symbol} DEMO DATA — synthetic random walk, NOT real market data",
        "date,open,high,low,close,volume",
    ]
    # Start 420 trading days back (weekdays only) ending "today"-ish fixed date.
    y, m, d = 2024, 7, 1
    import datetime as dtmod

    day = dtmod.date(y, m, d)
    for _ in range(TRADING_DAYS):
        while day.weekday() >= 5:
            day += dtmod.timedelta(days=1)
        if rnd.random() < 0.03:
            regime_drift = drift * rnd.uniform(-1.5, 2.5)
        intraday_vol = vol * math.sqrt(dt)
        shock = rnd.gauss(0, 1)
        o = price
        c = price * math.exp((regime_drift - 0.5 * vol * vol) * dt + intraday_vol * shock)
        hi = max(o, c) * (1 + abs(rnd.gauss(0, 1)) * intraday_vol * 0.5)
        lo = min(o, c) * (1 - abs(rnd.gauss(0, 1)) * intraday_vol * 0.5)
        vol_shares = int(abs(rnd.gauss(5e7, 2e7)) + 1e7)
        lines.append(
            f"{day.isoformat()},{o:.2f},{hi:.2f},{lo:.2f},{c:.2f},{vol_shares}"
        )
        price = c
        day += dtmod.timedelta(days=1)
    return "\n".join(lines) + "\n"


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for sym, (p, d, v, s) in UNIVERSE.items():
        path = os.path.join(OUT_DIR, f"{sym}_demo.csv")
        with open(path, "w", encoding="utf-8") as f:
            f.write(gen(sym, p, d, v, s))
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
