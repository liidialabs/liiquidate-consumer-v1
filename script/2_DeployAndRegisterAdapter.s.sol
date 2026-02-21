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

    address private LiidiaBorrowAddress = address(1); // Replace with actual LiidiaBorrow address
    address private AdapterRegistryAddress = address(1); // Replace with actual AdapterRegistry address

    function run() public {
        // get deployer key
        helperConfig = new HelperConfig();
        (,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // Create contract instances
        adapterRegistry = AdapterRegistry(AdapterRegistryAddress);

        // deploy LiiBorrowV1Adapter 
        liiBorrowV1Adapter = new LiiBorrowV1Adapter(LiidiaBorrowAddress);
        // register
        adapterRegistry.registerAdapter(
            liiBorrowV1Adapter.protocol(), 
            address(liiBorrowV1Adapter)
        );
        
        // Log
        console.log("Successfully Registered Adapter:", address(liiBorrowV1Adapter));

        vm.stopBroadcast();
    }
}