# Liiquidate

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

### Deploy

Deploy to Sepolia testnet:
```shell
forge script script/1a_DeployScript.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### Run Liquidation Flow

1. Configure mock contracts:
```shell
forge script script/1b_ConfigureMocks.s.sol:ConfigureMocks --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

2. Supply collateral:
```shell
forge script script/3_SupplyToLiidia.s.sol:SupplyToLiidia --rpc-url $SEPOLIA_RPC_URL --private-key $USER_PRIVATE_KEY --broadcast
```

3. Borrow against collateral:
```shell
forge script script/4_BorrowFromLiidia.s.sol:BorrowFromLiidia --rpc-url $SEPOLIA_RPC_URL --private-key $USER_PRIVATE_KEY --broadcast
```

4. Drop asset prices to trigger liquidation:
```shell
forge script script/5_DropAssetPrices.s.sol:DropAssetPrices --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

5. Execute liquidation:
```shell
forge script script/ManualLiiquidate.s.sol:ManualLiiquidate --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Security

- All critical functions are protected by `onlyOwner` modifiers
- Circuit breakers prevent repeated failures from blocking execution
- Slippage protection on all swap operations
- Input validation on all external inputs

## License

MIT
