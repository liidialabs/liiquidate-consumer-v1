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

    address[] memory sepoliaAdapters = new address[](1);
    sepoliaAdapters[0] = address(0);

    Adapter memory forSepolia = Adapter({
        adapterRegistryAddress: address(1),
        adapters: sepoliaAdapters
    });

    // BASE SEPOLIA

    address[] memory baseSepoliaAdapters = new address[](1);
    baseSepoliaAdapters[0] = address(0);

    Adapter memory forBaseSepolia = Adapter({
        adapterRegistryAddress: address(1),
        adapters: baseSepoliaAdapters
    });

    // ANVIL

    address[] memory anvilAdapters = new address[](1);
    anvilAdapters[0] = address(0);

    Adapter memory forAnvil = Adapter({
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
        uint8 adaptersLength = adapterToUse.adapters.length;
        for(uint8 i = 0; i < adaptersLength; i++) {
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