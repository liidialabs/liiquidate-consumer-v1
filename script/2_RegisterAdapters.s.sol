// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import {
    ILiquidationAdapter
} from "../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract RegisterAdapters is Script {
    ILiquidationAdapter liquidationAdapter;
    AdapterRegistry adapterRegistry;
    HelperConfig helperConfig;

    // General Struct
    struct Adapter {
        address adapterRegistryAddress;
        address[] adapters; 
    }

    // SEPOLIA

    address[] private sepoliaAdapters = [address(0), address(1)];

    Adapter private forSepolia = Adapter({
        adapterRegistryAddress: address(1),
        adapters: sepoliaAdapters
    });

    // BASE SEPOLIA

    address[] private baseSepoliaAdapters = [address(0), address(1)];

    Adapter private forBaseSepolia = Adapter({
        adapterRegistryAddress: address(1),
        adapters: baseSepoliaAdapters
    });

    // ANVIL

    address[] private anvilAdapters = [address(0), address(1)];

    Adapter private forAnvil = Adapter({
        adapterRegistryAddress: address(1),
        adapters: anvilAdapters
    });


    function run() public {
        // get deployer key
        helperConfig = new HelperConfig();
        (,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        // to use
        Adapter memory adapterToUse;

        vm.startBroadcast(deployerKey);

        // Assign correct address
        if (block.chainid == 11_155_111) {
            adapterToUse = forSepolia;
        } else if (block.chainid == 84532) {
            adapterToUse = forBaseSepolia;
        } else {
            adapterToUse = forAnvil;
        }

        // create registry instance
        adapterRegistry = AdapterRegistry(adapterToUse.adapterRegistryAddress);

        // register adapter
        uint256 adaptersLength = adapterToUse.adapters.length;
        for(uint256 i = 0; i < adaptersLength; i++) {
            // create adapter instance
            liquidationAdapter = ILiquidationAdapter(adapterToUse.adapters[i]);
            // register
            adapterRegistry.registerAdapter(
                liquidationAdapter.protocol(), 
                address(liquidationAdapter)
            );
            // confirm
            console.log("Successfully Registered:", address(liquidationAdapter));
        }

        vm.stopBroadcast();
    }
}