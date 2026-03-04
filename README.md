# Liiquidate Consumer Contract

A proxy consumer smart contract built for the Chainlink CRE Automation Workflow to execute liquidation of undercollateralized positions for the LiiBorrow, a lending protocol built on top of Aave V3.

## Overview

When a users positions drops below the liquidation threshold, the CRE automated workflow picks them up and forwards them to Liiquidate that executes the liquidation using flash loans to cover the debt without requiring upfront capital.

## How It Works

The liquidation flow operates as follows:

1. **Trigger**: Chainlink Automation detects undercollateralized positions and sends a liquidation report to the Liiquidate contract
2. **Flash Loan**: A flash loan is taken from either Aave V3 or Uniswap V4 to cover the debt amount
3. **Liquidation**: The borrowed funds are used to liquidate the position, receiving collateral assets as compensation
4. **Swap**: The received collateral is swapped back to the debt asset via Uniswap V4
5. **Repay**: The flash loan (plus fees) is repaid from the swap proceeds
6. **Profit**: Any remaining tokens are transferred as profit to the caller

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Chainlink Automation                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │ Liquidation Report
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Liiquidate                                 │
│  • Processes automation reports                                 │
│  • Decodes liquidation jobs                                     │
│  • Routes to FlashLoanRouter                                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   FlashLoanRouter                               │
│  • Manages flash loan providers                                 │
│  • Tries providers in priority order                            │
│  • Returns success/failure                                      │
└──────────┬──────────────────────────────────────────────────────┘
           │
     ┌─────┴─────┐
     ▼           ▼
┌─────────┐ ┌──────────┐
│AaveV3   │ │UniswapV4 │
└────┬────┘ └────┬─────┘
     │           │
     └─────┬─────┘
           │ Debt Asset (Flash Loan)
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                  LiiBorrow Protocol                             │
│  • Liquidates undercollateralized positions                     │
│  • Returns collateral asset                                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │ Collateral Asset
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                UniversalSwapRouter                              │
│  • Routes swaps through DEX adapters                            │
│  • Fallback to secondary DEX on failure                         │
│  • Circuit breaker for unhealthy protocols                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │ Debt Asset (Swapped)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Flash Loan Repayment                         │
└─────────────────────────────────────────────────────────────────┘
```

## Contracts

| Contract | Description |
|----------|-------------|
| `Liiquidate` | Main consumer contract, receives reports from Chainlink Automation |
| `FlashLoanRouter` | Routes flash loans across multiple providers with fallback |
| `AdapterRegistry` | Maps protocol names to liquidation adapter addresses |
| `UniversalSwapRouter` | Multi-DEX swap router with circuit breaker |
| `AaveV3` | Aave V3 flash loan provider |
| `UniswapV4` | Uniswap V4 flash loan provider |
| `UniswapV4Adapter` | Uniswap V4 swap adapter |
| `LiiBorrowV1Adapter` | LiiBorrow V1 liquidation adapter |

## Integrations

- **Chainlink Automation**: Receives liquidation reports for undercollateralized positions
- **Uniswap V4**: Primary flash loan provider and swap DEX
- **Aave V3**: Secondary flash loan provider
- **LiiBorrow**: Target lending protocol for liquidations

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- Node.js (for environment variables)

### Setup

1. Install dependencies:
```shell
forge install
```

2. Set up environment variables:
```shell
cp .env.example .env
# Edit .env with your private keys and RPC URLs
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

## Tenderly Virtual TestNet

The project supports deployment to Tenderly Virtual TestNet, a simulated test environment that allows testing without real blockchain costs.

### Key Features

- **Simulated Environment**: No real transaction costs
- **Virtual Accounts**: Test with unlimited ETH
- **Built-in Verification**: Automatic contract verification
- **Time Manipulation**: Control block timestamps for testing time-dependent features

### Time Control

To handle cooldown periods and time-based logic:
```shell
make forward-time
```

This advances the virtual time by 1 hour, allowing you to test time-dependent features without waiting.

### Verification

Contracts deployed to Tenderly Virtual TestNet are automatically verified using the custom verifier. 

### Testing Flow

You can simulate to estimate gas and fix bugs before broadcasting to the TestNet:

1. Deploy contracts: `make sim-deploy-script`
2. Configure mocks: `make sim-deploy-configs`
3. Deploy and register adapter: `make sim-deploy-adapters`
4. Supply collateral: `make sim-supply`
5. Advance time if needed: `make forward-time`
6. Borrow funds: `make sim-borrow`
7. Drop prices: `make sim-drop-price`
8. Execute liquidation: `make sim-man-liiquidate`

The typical testing flow on Tenderly Virtual TestNet:

1. Deploy contracts: `make deploy-script ARGS="--network tenderly"`
2. Configure mocks: `make deploy-configs ARGS="--network tenderly"`
3. Deploy and register adapter: `make deploy-adapters ARGS="--network tenderly"`
4. Supply collateral: `make supply`
5. Advance time if needed: `make forward-time`
6. Borrow funds: `make borrow`
7. Drop prices: `make drop-price`
   > **Note**: The mock Uniswap V4 pool is configured with an initial price of 2000e8 (sqrtPriceX96). To trigger liquidation, the price must be dropped to exactly 1600e8 to avoid reverts during liquidation simulation.

8. Execute liquidation: `make man-liiquidate`

### Environment Variables

The following environment variables are required for Tenderly Virtual TestNet:

- `TENDERLY_VIRTUAL_TESTNET_ADMIN`: Admin RPC URL for time manipulation
- `TENDERLY_VIRTUAL_TESTNET_RPC_URL`: Public RPC URL for deployment
- `TENDERLY_VERIFIER_URL`: Contract verification URL
- `TENDERLY_ACCESS_KEY`: Tenderly access key for authentication

### Advantages

- **Cost-effective**: No real ETH required
- **Fast**: Transactions execute instantly
- **Reliable**: No network congestion
- **Safe**: No risk of losing funds
- **Reproducible**: Consistent testing environment

### Limitations

- Simulated environment may behave differently than mainnet
- No real economic incentives
- Limited to Tenderly's virtual network

## Mainnet And Sepolia (... and other EVMS)

To deploy to either Mainnet or Sepolia, you need to update the Makefile to comment out the Tenderly variables and uncomment the network you want to deploy to.

In the Makefile:

1. **For Sepolia deployment:**
   - Comment out the Tenderly NETWORK_ARGS and RPC_URL (lines 44-48)
   - Uncomment the Sepolia NETWORK_ARGS and RPC_URL (lines 40-42)

2. **For Mainnet deployment:**
   - Comment out the Tenderly NETWORK_ARGS and RPC_URL (lines 44-48)
   - Add your Mainnet RPC URL to the .env file as `MAINNET_RPC_URL`
   - Uncomment the Mainnet NETWORK_ARGS (lines 73-79) or add a similar configuration

Then run:
```shell
make deploy-script ARGS="--network sepolia"
# or
make deploy-script ARGS="--network mainnet"
# rest of the commands as for Tenderly
```

**Note:** Ensure you have the required environment variables set in `.env` for the respective network (RPC URL, private key, Etherscan API key for verification).

## License

MIT
