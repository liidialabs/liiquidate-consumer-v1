#!/usr/bin/env bash
set -euo pipefail

# Simple Foundry deployment script for Liiquidate contracts
# Usage: ./deploy_foundry.sh <network> [broadcast]
# Example: ./deploy_foundry.sh goerli true

NETWORK=${1:-anvil}
BROADCAST=${2:-false}

echo "Network: $NETWORK"

# If broadcast true, pass --broadcast to forge script
BROADCAST_FLAG=""
if [ "$BROADCAST" = "true" ]; then
  BROADCAST_FLAG="--broadcast"
fi

# Default deployer private key env var: DEPLOYER_PRIVATE_KEY
if [ -z "${DEPLOYER_PRIVATE_KEY:-}" ]; then
  echo "Warning: DEPLOYER_PRIVATE_KEY not set. Local dry-run only."
fi

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url ${RPC_URL:-} \
  --private-key ${DEPLOYER_PRIVATE_KEY:-} \
  --legacy \
  $BROADCAST_FLAG \
  --etherscan-api-key ${ETHERSCAN_API_KEY:-} \
  --fork-url ${FORK_URL:-} \
  -vvvv

echo "Done. Check the output above for deployed addresses."
