// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Liiquidate} from "../src/Liiquidate.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";

/// @title DeployLiiquidate
/// @notice Deploys the Liiquidate consumer contract
/// @dev Deploys Liiquidate with existing FlashLoanRouter and AdapterRegistry
contract DeployLiiquidate is Script {
    HelperConfig helperConfig;
    FlashLoanRouter flashRouter;
    Liiquidate liiquidate;
    AdapterRegistry adapterRegistry;

    /// @notice Main deployment function
    /// @dev Deploys Liiquidate and registers it with existing infrastructure
    function run() public {
        helperConfig = new HelperConfig();

        flashRouter = FlashLoanRouter(helperConfig.flashLoanRouterAddress());
        adapterRegistry = AdapterRegistry(helperConfig.adapterRegistryAddress());

        vm.startBroadcast(helperConfig.deployerKey());
        
        liiquidate = new Liiquidate(
            helperConfig.USDC(),
            address(adapterRegistry), 
            address(flashRouter), 
            helperConfig.forwarderAddress()
        );
        console2.log("Successfully Deployed Liiquidate Consumer Contract!");

        vm.stopBroadcast();

        console2.log("Contract Deployed At: ", address(liiquidate));
    }
}