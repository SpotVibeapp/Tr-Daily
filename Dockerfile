# ==============================================================================
# Tr-Daily 24/7 Autonomous Trading Server Dockerfile
# Ultra-lightweight multi-stage build: compiles to native AOT Linux binary (~30MB)
# ==============================================================================

FROM dart:stable AS build
WORKDIR /app

# Cache dependencies
COPY pubspec.yaml ./
RUN dart pub get

# Copy source and compile native executable
COPY . .
RUN dart compile exe bin/tr_daily_server.dart -o bin/tr_daily_server

# ------------------------------------------------------------------------------
# Minimal runtime container
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim
WORKDIR /app

# Install CA certificates for TLS connections to Alpaca and Yahoo Finance
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /app/bin/tr_daily_server /app/tr_daily_server

EXPOSE 8080
ENV PORT=8080
ENV TR_BROKER_MODE=paper

ENTRYPOINT ["/app/tr_daily_server"]
