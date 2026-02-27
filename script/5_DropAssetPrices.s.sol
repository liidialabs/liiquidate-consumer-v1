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

contract DropAssetPrices is Script {
    using PoolIdLibrary for PoolKey;

    MockV3Aggregator priceFeed;
    HelperConfig helperConfig;
    IMockAaveOracle aaveOracle;
    IDebtManager debtManager;
    MockUniswapV4PoolManager uniswapV4Pool;
    LiiBorrowV1Adapter liiAdapter;
    FlashLoanRouter flashRouter;

    int256 constant NEW_PRICE = 1600e8; // Drop to $1600
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        // Create contract instance
        priceFeed = MockV3Aggregator(helperConfig.mockChainlinkOracle());
        aaveOracle = IMockAaveOracle(helperConfig.mockAaveV3Oracle());
        debtManager = IDebtManager(helperConfig.debtManagerAddress());
        uniswapV4Pool = MockUniswapV4PoolManager(payable(helperConfig.uniswapV4PoolAddress()));
        liiAdapter = LiiBorrowV1Adapter(helperConfig.liiBorrowV1AdapterAddress());
        flashRouter = FlashLoanRouter(helperConfig.flashLoanRouterAddress());

        // Log health factor before price drop
        uint256 hfBefore = debtManager.getHealthFactor(vm.addr(userKey));
        bool isLiquidatableBefore = debtManager.isLiquidatable(vm.addr(userKey));
        (uint256 aaveDebtBefore, ) = debtManager.getUserDebt(vm.addr(userKey));
        console2.log("User Debt before : %s USDC", aaveDebtBefore / 1e6);
        console2.log("User Health Factor before price drop: %s", hfBefore);
        console2.log("User is liquidatable before price drop: %s", isLiquidatableBefore);
        console2.log("------------------------------------------------------------");

        vm.startBroadcast(helperConfig.deployerKey());
        
        // set proxy
        // flashRouter.setProxyAddress(helperConfig.liiquidateAddress());
        
        // adjust sqrtPrice
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(helperConfig.WETH()),
            currency1: Currency.wrap(helperConfig.USDC()),
            fee: 3000,
            tickSpacing: 60, 
            hooks: IHooks(address(0)) 
        });
        uint160 newSqrtPriceX96 = 3162277660168379331998893544432; // for 1600USDC/1WETH

        uniswapV4Pool.setSqrtPrice(poolKey, newSqrtPriceX96);

        // Update price to simulate price drop on chainlink oracle & Aave oracle
        aaveOracle.setAssetPrice(helperConfig.WETH(), uint256(NEW_PRICE));
        priceFeed.updateAnswer(NEW_PRICE);
        // Log
        console2.log("Successfully dropped asset price to $%d!", NEW_PRICE / 1e8);

        vm.stopBroadcast();

        // Log health factor after price drop
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