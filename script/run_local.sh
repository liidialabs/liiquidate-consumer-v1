#!/usr/bin/env bash
set -euo pipefail

# Simple local run helper: starts anvil and runs tests
ANVIL_PORT=8545
ANVIL_PID=0

function start_anvil() {
  if command -v anvil >/dev/null 2>&1; then
    echo "Starting anvil on port $ANVIL_PORT..."
    anvil -p $ANVIL_PORT > /tmp/anvil.log 2>&1 &
    ANVIL_PID=$!
    sleep 1
    echo "Anvil pid: $ANVIL_PID"
  else
    echo "anvil not found. Please install Foundry (foundryup)"
    exit 1
  fi
}

function stop_anvil() {
  if [ "$ANVIL_PID" -ne 0 ]; then
    echo "Stopping anvil..."
    kill $ANVIL_PID || true
  fi
}

trap stop_anvil EXIT

start_anvil

# Run unit tests against local anvil
export RPC_URL=http://127.0.0.1:$ANVIL_PORT
forge test --rpc-url $RPC_URL -v
