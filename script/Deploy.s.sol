// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Liiquidate} from "../src/Liiquidate.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {UniversalSwapRouter} from "../src/UniversalSwapRouter.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";

contract DeployScript is Script {
    function run() public {
        // load deployer key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AdapterRegistry adapterRegistry = new AdapterRegistry();
        FlashLoanRouter flashRouter = new FlashLoanRouter();
        UniversalSwapRouter swapRouter = new UniversalSwapRouter();

        // Deploy main Liiquidate contract with mocks/routers addresses
        Liiquidate liiquidate = new Liiquidate(
            address(0), // debt manager (set later)
            address(0), // lending protocol (set later)
            address(flashRouter)
        );

        // Print addresses to stdout
        console.log("AdapterRegistry:", address(adapterRegistry));
        console.log("FlashLoanRouter:", address(flashRouter));
        console.log("UniversalSwapRouter:", address(swapRouter));
        console.log("Liiquidate:", address(liiquidate));

        vm.stopBroadcast();
    }
}
