// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockChainlinkOracle.sol";
import {IMockAaveOracle} from "../test/mocks/interfaces/IMockAaveOracle.sol";
import {ILiquidationAdapter} from "../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol";
import {LiiBorrowV1Adapter} from "../src/liidiaProtocol/LiiBorrowV1Adapter.sol";
import {MockUniswapV4PoolManager} from "../test/mocks/MockUniswapV4PoolManager.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title DropAssetPrices
/// @notice Drops asset prices to trigger liquidation conditions for testing
/// @dev Updates Chainlink oracle, Aave oracle, and Uniswap V4 pool price to make user liquidatable
contract DropAssetPrices is Script {
    using PoolIdLibrary for PoolKey;

    MockV3Aggregator priceFeed;
    HelperConfig helperConfig;
    IMockAaveOracle aaveOracle;
    IDebtManager debtManager;
    MockUniswapV4PoolManager uniswapV4Pool;
    LiiBorrowV1Adapter liiAdapter;
    FlashLoanRouter flashRouter;

    /// @notice New WETH price ($1600)
    int256 constant NEW_PRICE = 1600e8;
    /// @notice User private key from environment
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    /// @notice Main function to drop asset prices
    /// @dev Updates oracles and pool price to trigger liquidation eligibility
    function run() public {
        // deploy helperConfig
        helperConfig = new HelperConfig();
        // fetch addresses
        (
            address mockChainlinkOracle,
            address mockAaveV3Oracle,
            address mockAaveV3Pool
        ) = helperConfig.activeMockConfig();
        (
            ,,
            address uniswapV4PoolAddress
        ) = helperConfig.activeNetworkConfig();
        (
            address debtManagerAddress,,
            address weth,
            address usdc
        ) = helperConfig.activeLiiBorrowConfig();
        (
            ,
            address flashLoanRouterAddress,
            ,,,,,
            address liiBorrowV1AdapterAddress
        ) = helperConfig.activeLiiquidateConfig();

        priceFeed = MockV3Aggregator(mockChainlinkOracle);
        aaveOracle = IMockAaveOracle(mockAaveV3Oracle);
        debtManager = IDebtManager(debtManagerAddress);
        uniswapV4Pool = MockUniswapV4PoolManager(payable(uniswapV4PoolAddress));
        liiAdapter = LiiBorrowV1Adapter(liiBorrowV1AdapterAddress);
        flashRouter = FlashLoanRouter(flashLoanRouterAddress);

        uint256 hfBefore = debtManager.getHealthFactor(vm.addr(userKey));
        bool isLiquidatableBefore = debtManager.isLiquidatable(vm.addr(userKey));
        (uint256 aaveDebtBefore, ) = debtManager.getUserDebt(vm.addr(userKey));
        console2.log("User Debt before : %s USDC", aaveDebtBefore / 1e6);
        console2.log("User Health Factor before price drop: %s", hfBefore);
        console2.log("User is liquidatable before price drop: %s", isLiquidatableBefore);
        console2.log("------------------------------------------------------------");

        vm.startBroadcast(helperConfig.deployerKey());
        
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(weth),
            currency1: Currency.wrap(usdc),
            fee: 3000,
            tickSpacing: 60, 
            hooks: IHooks(address(0)) 
        });
        uint160 newSqrtPriceX96 = 3162277660168379331998893544432; // for 1600USDC/1WETH

        uniswapV4Pool.setSqrtPrice(poolKey, newSqrtPriceX96);

        aaveOracle.setAssetPrice(weth, uint256(NEW_PRICE));
        priceFeed.updateAnswer(NEW_PRICE);
        console2.log("Successfully dropped asset price to $%d!", NEW_PRICE / 1e8);

        vm.stopBroadcast();

        uint256 hfAfter = debtManager.getHealthFactor(vm.addr(userKey));
        bool isLiquidatableAfter = debtManager.isLiquidatable(vm.addr(userKey));
        (uint256 aaveDebtAfter, ) = debtManager.getUserDebt(vm.addr(userKey));
        console2.log("------------------------------------------------------------");
        console2.log("User Debt After : %s USDC", aaveDebtAfter / 1e6);
        console2.log("User Health Factor after price drop: %s", hfAfter);
        console2.log("User is liquidatable after price drop: %s", isLiquidatableAfter);
        console2.log("------------------------------------------------------------");
        ILiquidationAdapter.RiskState memory riskState = liiAdapter.getRiskState(vm.addr(userKey));
        console2.log(">>> ADAPTER <<<");
        console2.log("isLiquidatable: %s", riskState.liquidatable);
        console2.log("HF: %s", riskState.riskMetric);
    }
}