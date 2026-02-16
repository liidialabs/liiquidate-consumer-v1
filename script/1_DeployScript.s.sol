// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
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
            address forwarder,
            address aaveV3Pool,
            address uniswapV4Pool,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        // deploy

        vm.startBroadcast(deployerKey);

        ////// DEPLOY CORE CONTRACTS //////

        adapterRegistry = new AdapterRegistry();
        flashRouter = new FlashLoanRouter();
        swapRouter = new UniversalSwapRouter();

        ////// REGISTER ADAPTER //////

        // deploy
        uniswapAdapter = new UniswapV4Adapter(uniswapV4Pool);
        // register
        swapRouter.registerAdapter(address(uniswapAdapter));
        // add to priority queu
        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = uniswapAdapter.protocolId();
        swapRouter.setProtocolPriority(protocols);

        ///// FLASH LOAN /////

        // deploy uniswapV4
        uniswapFlashloan = new UniswapV4(
            uniswapV4Pool,
            address(swapRouter)
        );
        // deploy aaveV3
        aaveV3Flashloan = new AaveV3(
            aaveV3Pool,
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

        ///// DEPLOT LIIQUIDATE /////

        liiquidate = new Liiquidate(
            address(adapterRegistry), 
            address(flashRouter), 
            address(forwarder)
        );

        // set proxyAdress
        flashRouter.setProxyAddress(address(liiquidate));

        // Print addresses to stdout
        console.log("AdapterRegistry:", address(adapterRegistry));
        console.log("FlashLoanRouter:", address(flashRouter));
        console.log("UniversalSwapRouter:", address(swapRouter));
        console.log("Liiquidate:", address(liiquidate));
        console.log("-------------------------------");
        console.log("UniswapV4Adapter:", address(uniswapAdapter));
        console.log("UniswapV4FlashloanAdapter:", address(uniswapFlashloan));
        console.log("AaveV3FlashloanAdapter:", address(aaveV3Flashloan));


        vm.stopBroadcast();
    }
}
