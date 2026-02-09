# Scripts

This folder contains helper scripts for deploying and testing the `Liiquidate` project.

Files:

- `deploy_foundry.sh` - Simple wrapper to run the Foundry `Deploy.s.sol` script. Use `DEPLOYER_PRIVATE_KEY` and `RPC_URL` or `FORK_URL` env vars.
- `Deploy.s.sol` - Foundry script that deploys `AdapterRegistry`, `FlashLoanRouter`, `UniversalSwapRouter`, and `Liiquidate`.
- `deploy_hardhat.js` - Hardhat/Node deployment script (requires `npm install` and Hardhat installed locally).
- `verify_etherscan.sh` - Helper to verify contracts on Etherscan via `forge verify-contract`.
- `run_local.sh` - Starts `anvil` locally and runs tests against it.

Environment variables used:

- `DEPLOYER_PRIVATE_KEY` - Private key for broadcast deployments.
- `RPC_URL` - RPC URL for the network.
- `FORK_URL` - URL for forking state (optional).
- `ETHERSCAN_API_KEY` - API key for etherscan verification.
- `ETH_NETWORK` - Network name used in verification commands.

Examples:

Run a local dry-run deploy (no broadcast):

```bash
chmod +x script/deploy_foundry.sh
./script/deploy_foundry.sh anvil false
```

Broadcast to Goerli:

```bash
export DEPLOYER_PRIVATE_KEY=0x...
export RPC_URL="https://goerli.infura.io/v3/<KEY>"
./script/deploy_foundry.sh goerli true
```

Hardhat deploy:

```bash
node script/deploy_hardhat.js
```

Verify contract with forge:

```bash
./script/verify_etherscan.sh "src/Liiquidate.sol:Liiquidate" 0xYourContractAddress
```
