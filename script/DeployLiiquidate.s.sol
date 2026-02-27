// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Liiquidate} from "../src/Liiquidate.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";

contract DeployLiiquidate is Script {
    HelperConfig helperConfig;
    FlashLoanRouter flashRouter;
    Liiquidate liiquidate;
    AdapterRegistry adapterRegistry;


    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        // Create contract instance
        flashRouter = FlashLoanRouter(helperConfig.flashLoanRouterAddress());
        adapterRegistry = AdapterRegistry(helperConfig.adapterRegistryAddress());

        vm.startBroadcast(helperConfig.deployerKey());
        
        // deploy Liiquidate
        liiquidate = new Liiquidate(
            address(adapterRegistry), 
            address(flashRouter), 
            helperConfig.forwarderAddress()
        );
        // Log
        console2.log("Successfully Deployed Liiquidate Consumer Contract!");

        vm.stopBroadcast();

        // Log health factor after price drop
        console2.log("Contract Deployed At: ", address(liiquidate));

    }
}