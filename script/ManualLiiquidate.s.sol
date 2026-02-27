// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import { ILiquidationAdapter } from "../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract ManualLiiquidate is Script {
    HelperConfig helperConfig;
    FlashLoanRouter flashRouter;
    AdapterRegistry registry;
    MockERC20 usdc;

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        // Create contract instance
        registry = AdapterRegistry(helperConfig.adapterRegistryAddress());
        flashRouter = FlashLoanRouter(helperConfig.flashLoanRouterAddress());
        usdc = MockERC20(helperConfig.USDC());

        vm.startBroadcast(helperConfig.deployerKey());
        
        // position liquidation data
        string memory protocolName = 'LIIBORROW_v1';
        address user = 0xC099f8A2C5117C81652A506aFfE10a6E77e79808 ;
        uint256 debtToCover = 600e6;
        address debtAsset = 0xf8340a3BB21282Af32B567e0ACE1Cc5c4eF63a73;
        address collateralAsset = 0x394A1145Cc4480cD047ad065a5Ece23D4fcC2E1d;

        // Get adapter address from registry
        address adapterAddr = registry.getAdapter(protocolName);

        // Instantiate adapter
        ILiquidationAdapter adapter = ILiquidationAdapter(adapterAddr);
        // Fetch target contract and callData
        ILiquidationAdapter.ExecutionPayload memory payload = adapter
            .buildExecutionPayload(
                user,
                debtToCover,
                debtAsset,
                collateralAsset
            );
        
        uint256 balance = usdc.balanceOf(helperConfig.flashLoanRouterAddress());
        ILiquidationAdapter.RiskState memory riskState = adapter.getRiskState(user);
        console2.log("isLiquidatable: %s", riskState.liquidatable);
        console2.log("HF: %s", riskState.riskMetric);
        console2.log("Debt: %s", riskState.debtUSD);
        console2.log("Collateral: %s", riskState.collateralUSD);
        console2.log("FlashRouter Balance: %s", balance / 1e6);
        console2.log(">------------AFTER-------------<");

        bool resp = flashRouter.flashLoan(
            debtAsset, 
            collateralAsset, 
            debtToCover, 
            payload.target, 
            payload.callData 
        );

        riskState = adapter.getRiskState(user);
        console2.log("isLiquidatable: %s", riskState.liquidatable);
        console2.log("HF: %s", riskState.riskMetric);
        console2.log("Debt: %s", riskState.debtUSD);
        console2.log("Collateral: %s", riskState.collateralUSD);
        console2.log(">-------------------------<");
        balance = usdc.balanceOf(helperConfig.flashLoanRouterAddress());
        console2.log("FlashRouter Balance: %s", balance / 1e6);

        vm.stopBroadcast();

        // Log health factor after price drop
        console2.log("Liquidation Success Status: ", resp);

    }
}