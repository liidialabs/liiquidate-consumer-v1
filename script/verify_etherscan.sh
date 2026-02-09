#!/usr/bin/env bash
set -euo pipefail

# Simple Etherscan verification helper for Foundry deployments
# Requires: ETHERSCAN_API_KEY environment variable and deployed contract addresses

if [ -z "${ETHERSCAN_API_KEY:-}" ]; then
  echo "ETHERSCAN_API_KEY not set"
  exit 1
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: verify_etherscan.sh <contract-fqdn> <contract-address> [constructor-args-file]"
  echo "Example: ./verify_etherscan.sh \"src/Liiquidate.sol:Liiquidate\" 0x123... ./args.txt"
  exit 1
fi

CONTRACT_FQDN=$1
CONTRACT_ADDRESS=$2
CONSTRUCTOR_ARGS_FILE=${3:-}

if [ -n "$CONSTRUCTOR_ARGS_FILE" ]; then
  forge verify-contract --chain ${ETH_NETWORK:-} --num-of-optimizations 200 $CONTRACT_ADDRESS $CONTRACT_FQDN $ETHERSCAN_API_KEY --constructor-args $(cat $CONSTRUCTOR_ARGS_FILE)
else
  forge verify-contract --chain ${ETH_NETWORK:-} --num-of-optimizations 200 $CONTRACT_ADDRESS $CONTRACT_FQDN $ETHERSCAN_API_KEY
fi
