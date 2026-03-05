// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import { ILiquidationAdapter } from "../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @title ManualLiiquidate
/// @notice Manually executes a liquidation for testing
/// @dev Retrieves adapter from registry, builds execution payload, and triggers flash loan liquidation
contract ManualLiiquidate is Script {
    HelperConfig helperConfig;
    FlashLoanRouter flashRouter;
    AdapterRegistry registry;
    MockERC20 USDC;

    /// @notice Main liquidation function
    /// @dev Executes a manual liquidation of a specific user position
    function run() public {
        // deploy helperConfig
        helperConfig = new HelperConfig();
        // fetch addresses
        (
            address adapterRegistryAddress,
            address flashLoanRouterAddress,
            ,,,,,
        ) = helperConfig.activeLiiquidateConfig();
        (
            ,,,
            address usdc
        ) = helperConfig.activeLiiBorrowConfig();

        registry = AdapterRegistry(adapterRegistryAddress);
        flashRouter = FlashLoanRouter(flashLoanRouterAddress);
        USDC = MockERC20(usdc);

        vm.startBroadcast(helperConfig.deployerKey());
        
        // liquidatable position data
        string memory protocolName = '';
        address user = address(0);
        uint256 debtToCover = 0;
        address debtAsset = address(0);
        address collateralAsset = address(0);

        address adapterAddr = registry.getAdapter(protocolName);

        ILiquidationAdapter adapter = ILiquidationAdapter(adapterAddr);
        ILiquidationAdapter.ExecutionPayload memory payload = adapter
            .buildExecutionPayload(
                user,
                debtToCover,
                debtAsset,
                collateralAsset
            );
        
        uint256 balance = USDC.balanceOf(flashLoanRouterAddress);
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
        balance = USDC.balanceOf(flashLoanRouterAddress);
        console2.log("FlashRouter Balance: %s", balance / 1e6);

        vm.stopBroadcast();

        console2.log("Liquidation Success Status: ", resp);
    }
}