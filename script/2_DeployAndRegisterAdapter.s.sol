// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import {
    ILiquidationAdapter
} from "../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {LiiBorrowV1Adapter} from "../src/liidiaProtocol/LiiBorrowV1Adapter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployAndRegisterAdapter is Script {
    ILiquidationAdapter liquidationAdapter;
    LiiBorrowV1Adapter liiBorrowV1Adapter;
    AdapterRegistry adapterRegistry;
    HelperConfig helperConfig;

    function run() public {
        // get deployer key
        helperConfig = new HelperConfig();

        vm.startBroadcast(helperConfig.deployerKey());

        // Create contract instances
        adapterRegistry = AdapterRegistry(helperConfig.adapterRegistryAddress());

        // deploy LiiBorrowV1Adapter 
        liiBorrowV1Adapter = new LiiBorrowV1Adapter(helperConfig.debtManagerAddress());
        // register
        adapterRegistry.registerAdapter(
            address(liiBorrowV1Adapter)
        );
        
        // Log
        console.log("Successfully Registered Adapter:", address(liiBorrowV1Adapter));

        vm.stopBroadcast();
    }
}