// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Liiquidate} from "../src/Liiquidate.sol";
import {FlashLoanRouter} from "../src/FlashLoanRouter.sol";
import {UniversalSwapRouter} from "../src/UniversalSwapRouter.sol";
import {AdapterRegistry} from "../src/AdapterRegistry.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {UniswapV4Adapter} from "../src/swappers/UniswapV4Adapter.sol";
import {UniswapV4} from "../src/flashloans/UniswapV4.sol";
import {AaveV3} from "../src/flashloans/AaveV3.sol";

contract DeployScript is Script {
    // Helper
    HelperConfig helperConfig;
    // Main Contracts
    AdapterRegistry adapterRegistry;
    FlashLoanRouter flashRouter;
    UniversalSwapRouter swapRouter;
    Liiquidate liiquidate;
    // Swap Adapter
    UniswapV4Adapter uniswapAdapter;
    // Flashloan
    UniswapV4 uniswapFlashloan;
    AaveV3 aaveV3Flashloan;

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        (
            address forwarderAddress,
            address aaveV3PoolAddress,
            address uniswapV4PoolAddress
        ) = helperConfig.activeNetworkConfig();

        // deploy

        vm.startBroadcast(helperConfig.deployerKey());

        ////// DEPLOY CORE CONTRACTS //////

        adapterRegistry = new AdapterRegistry();
        flashRouter = new FlashLoanRouter();
        swapRouter = new UniversalSwapRouter();

        ////// DEPLOY & REGISTER SWAP ADAPTER //////

        // deploy
        uniswapAdapter = new UniswapV4Adapter(uniswapV4PoolAddress);
        // register
        swapRouter.registerAdapter(address(uniswapAdapter));
        // add to priority queu
        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = uniswapAdapter.protocolId();
        swapRouter.setProtocolPriority(protocols);

        ///// DEPLOY AND REGISTER FLASH LOAN ADAPTERS /////

        // deploy uniswapV4
        uniswapFlashloan = new UniswapV4(
            uniswapV4PoolAddress,
            address(swapRouter)
        );
        // deploy aaveV3
        aaveV3Flashloan = new AaveV3(
            aaveV3PoolAddress,
            address(swapRouter)
        );
        // add providers 
        flashRouter.addProvider(address(uniswapFlashloan));
        flashRouter.addProvider(address(aaveV3Flashloan));
        // set priority
        bytes32[] memory _protocols = new bytes32[](2);
        _protocols[0] = uniswapFlashloan.id();
        _protocols[1] = aaveV3Flashloan.id();
        flashRouter.setProviderPriority(_protocols);

        ///// DEPLOY LIIQUIDATE AND SET AS PROXY /////

        liiquidate = new Liiquidate(
            address(adapterRegistry), 
            address(flashRouter), 
            forwarderAddress
        );

        // Print addresses to stdout
        console2.log("AdapterRegistry:", address(adapterRegistry));
        console2.log("FlashLoanRouter:", address(flashRouter));
        console2.log("UniversalSwapRouter:", address(swapRouter));
        console2.log("Liiquidate:", address(liiquidate));
        console2.log("-------------------------------");
        console2.log("UniswapV4Adapter:", address(uniswapAdapter));
        console2.log("UniswapV4FlashloanAdapter:", address(uniswapFlashloan));
        console2.log("AaveV3FlashloanAdapter:", address(aaveV3Flashloan));


        vm.stopBroadcast();
    }
}
