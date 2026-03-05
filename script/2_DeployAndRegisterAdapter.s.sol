// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import {
    ILiquidationAdapter
} from "../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {LiiBorrowV1Adapter} from "../src/liidiaProtocol/LiiBorrowV1Adapter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployAndRegisterAdapter
/// @notice Deploys and registers the LiiBorrow V1 liquidation adapter
/// @dev Deploys LiiBorrowV1Adapter and registers it with the AdapterRegistry
contract DeployAndRegisterAdapter is Script {
    ILiquidationAdapter liquidationAdapter;
    LiiBorrowV1Adapter liiBorrowV1Adapter;
    AdapterRegistry adapterRegistry;
    HelperConfig helperConfig;

    /// @notice Main deployment function
    /// @dev Deploys the LiiBorrowV1Adapter and registers it with the protocol registry
    function run() public {
        // deploy helperConfig
        helperConfig = new HelperConfig();
        // fetch addresses
        (
            address adapterRegistryAddress,
            ,,,,,,
        ) = helperConfig.activeLiiquidateConfig();
        (
            address debtManagerAddress,
            ,,
        ) = helperConfig.activeLiiBorrowConfig();

        vm.startBroadcast(helperConfig.deployerKey());

        adapterRegistry = AdapterRegistry(adapterRegistryAddress);

        liiBorrowV1Adapter = new LiiBorrowV1Adapter(debtManagerAddress);
        adapterRegistry.registerAdapter(
            address(liiBorrowV1Adapter)
        );
        
        console.log("Successfully Registered Adapter:", address(liiBorrowV1Adapter));

        vm.stopBroadcast();
    }
}