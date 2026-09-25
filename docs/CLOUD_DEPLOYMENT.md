# 24/7 Cloud Deployment Guide

Run **Tr-Daily** continuously in the cloud so automated trades, stop-losses, and profit targets execute even when your phone is turned off, asleep, or disconnected from Wi-Fi.

Tr-Daily's core engine is **100% pure Dart** (no Flutter UI dependencies), allowing it to compile into a tiny native binary (~30 MB) and run headlessly on any Linux server, container, or Raspberry Pi with under 40 MB of RAM usage.

---

## Architecture Overview

```
[ Market Data APIs ]        [ Alpaca Broker (Paper/Live) ]
         │                               │
         └───────────► ┌─────────────────┴─────────────┐
                       │    Tr-Daily Headless Server   │
                       │     (bin/tr_daily_server)     │
                       │                               │
                       │  - Market Scanner (OHLCV)     │
                       │  - Technical Trend Estimator  │
                       │  - Ensemble + On-Device ML    │
                       │  - Risk Manager & Stop Trailing│
                       │  - HTTP Health Check (:8080)  │
                       └───────────────┬───────────────┘
                                       │
                      [ Real-Time Push Notifications ]
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
       Discord Webhook                                Telegram Bot
   (Pushes to your phone/watch)                  (Instant direct messages)
```

---

## Free-Tier Hosting Options

All recommended options below are **completely free** with zero hidden fees.

### Option 1: Oracle Cloud Always-Free VM (Recommended — 100% Free Forever)

Oracle Cloud Infrastructure (OCI) offers an **Always Free** tier that includes:
- Up to 4 ARM Ampere OCPU cores and 24 GB of RAM
- 200 GB of NVMe block storage
- Generous outbound bandwidth (10 TB/month)
- **Never expires** — runs 24/7/365 without paying a cent.

#### Step-by-Step Setup:
1. Sign up for an Oracle Cloud account at [cloud.oracle.com](https://cloud.oracle.com).
2. Create an **Always Free Compute Instance**:
   - Image: Ubuntu 22.04 or 24.04 (or Debian)
   - Shape: `VM.Standard.A1.Flex` (e.g. 2 OCPUs, 8 GB RAM)
   - Save your SSH key pair.
3. SSH into your instance:
   ```bash
   ssh -i your_key.pem ubuntu@<INSTANCE_PUBLIC_IP>
   ```
4. Install Docker and Docker Compose (or Dart SDK):
   ```bash
   sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 git
   sudo usermod -aG docker $USER
   newgrp docker
   ```
5. Clone your repository:
   ```bash
   git clone https://github.com/SpotVibeapp/Tr-Daily.git
   cd Tr-Daily
   ```
6. Configure environment variables in `.env`:
   ```bash
   cat << 'EOF' > .env
   TR_BROKER_MODE=paper
   ALPACA_KEY_ID=your_alpaca_key_id
   ALPACA_SECRET_KEY=your_alpaca_secret_key
   WATCHLIST=AAPL,NVDA,TSLA,MSFT,AMZN
   SCAN_INTERVAL_SECONDS=60
   RISK_PER_TRADE_PCT=0.5
   MAX_DAILY_LOSS_PCT=2.0
   MAX_OPEN_POSITIONS=1
   WEBHOOK_URL=https://discord.com/api/webhooks/your_webhook_id/token
   EOF
   ```
7. Start the container in the background:
   ```bash
   docker compose up -d
   ```
8. View real-time logs:
   ```bash
   docker compose logs -f
   ```

---

### Option 2: Render / Fly.io / Koyeb Free Container Tiers

You can deploy Tr-Daily directly from your GitHub repository using the included `Dockerfile`.

1. **Push your repository** to GitHub.
2. Log into [render.com](https://render.com) or [fly.io](https://fly.io) (free tier).
3. Create a **New Web Service** pointing to your repository.
4. Set Environment Variables in the provider's dashboard:
   - `TR_BROKER_MODE`: `paper` (or `live`)
   - `ALPACA_KEY_ID`: `PK...`
   - `ALPACA_SECRET_KEY`: `...`
   - `WATCHLIST`: `AAPL,NVDA,TSLA,MSFT,AMZN`
   - `WEBHOOK_URL`: `https://discord.com/api/webhooks/...`
5. Configure the Health Check Path: `/health` (Port: `8080`).
6. Deploy! Render or Fly.io builds the Dockerfile and starts the engine.

---

### Option 3: Local Hardware / Raspberry Pi / Home Server

If you have a Raspberry Pi, old laptop, or home server running Linux, you can run Tr-Daily as a systemd background service at zero cost.

1. Install Dart SDK (or Docker):
   ```bash
   sudo apt-get update && sudo apt-get install -y dart
   ```
2. Copy the service unit to systemd:
   ```bash
   sudo cp deploy/tr-daily.service /etc/systemd/system/
   ```
3. Create `/etc/tr-daily/tr-daily.env` with your API keys and configuration.
4. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now tr-daily
   ```
5. Check status:
   ```bash
   sudo systemctl status tr-daily
   journalctl -u tr-daily -f
   ```

---

### Option 4: GitHub Actions Scheduled Cron (Zero-Server Option)

If you don't want to manage a server or container at all, you can use GitHub Actions' free 2,000 monthly runner minutes to run market scans during trading hours:

Create `.github/workflows/market_cron.yml`:
```yaml
name: Market Hours Scanner

on:
  schedule:
    # Runs every 15 minutes during US market hours (13:30 to 20:00 UTC, Mon-Fri)
    - cron: '*/15 13-20 * * 1-5'
  workflow_dispatch:

jobs:
  run-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - name: Run Engine Scan
        env:
          TR_BROKER_MODE: ${{ secrets.TR_BROKER_MODE }}
          ALPACA_KEY_ID: ${{ secrets.ALPACA_KEY_ID }}
          ALPACA_SECRET_KEY: ${{ secrets.ALPACA_SECRET_KEY }}
          WEBHOOK_URL: ${{ secrets.WEBHOOK_URL }}
        run: |
          dart run bin/tr_daily_server.dart &
          PID=$!
          sleep 60
          kill $PID || true
```

---

## Free Real-Time Phone Push Notifications

When running headlessly 24/7, you need alerts when:
- A trade fills (`BOUGHT 50 AAPL @ $185.20`)
- A stop loss or take profit hits (`CLOSED TSLA — trailing stop`)
- The daily circuit breaker triggers (`HALTED: daily loss limit reached`)

### Discord Webhook (Recommended — Takes 60 Seconds)
1. Open Discord (desktop or mobile) and create a private server for your alerts (e.g. `My Trading Alerts`).
2. Go to **Server Settings** → **Integrations** → **Webhooks** → **New Webhook**.
3. Name it `Tr-Daily Bot`, pick a channel, and click **Copy Webhook URL**.
4. Paste the URL into `WEBHOOK_URL` in your `.env` or in the Tr-Daily Settings screen.
5. You'll receive formatted, color-coded push notifications with sound/vibration straight to your phone and smartwatch whenever the engine executes!

### Telegram Bot Setup
1. Open Telegram and search for `@BotFather`.
2. Send `/newbot` and follow the prompts to choose a bot name and username.
3. Copy the HTTP API token provided by BotFather (`TELEGRAM_BOT_TOKEN`).
4. Start a chat with your new bot and send any message (e.g. `hello`).
5. Open `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates` in your browser to find your `chat.id` (`TELEGRAM_CHAT_ID`).
6. Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in your environment.

---

## Health Check & Monitoring API

The headless server exposes lightweight HTTP endpoints on port `8080`:

| Endpoint | Method | Response | Description |
|---|---|---|---|
| `/health` | `GET` | `{"status": "healthy", "engineState": "running", ...}` | Liveness check for cloud containers (Render, Fly, Docker) |
| `/status` | `GET` | Detailed JSON with equity, P&L, positions, last signals | Check account equity and active positions via curl/browser |
| `/` | `GET` | Service banner, version, and disclaimer | Root healthcheck |

Example status check:
```bash
curl http://localhost:8080/status | jq .
```

---

## Security Best Practices

1. **Never commit API keys to Git**: Use environment variables or `.env` files (already gitignored).
2. **Start in Paper Mode**: Always run the headless engine in `paper` mode first to verify your hosting stability and webhook alerts before switching to `live`.
3. **Hard Circuit Breaker**: The `-2%` default daily-loss breaker is enforced natively by the engine loop; if hit, all positions are automatically closed at market and trading is halted for the day.
4. **Alpaca Key Restrictions**: When generating Alpaca API keys, you can restrict permissions or create separate keys for paper vs. live trading.
