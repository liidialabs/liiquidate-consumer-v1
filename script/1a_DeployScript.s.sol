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

/// @title DeployScript
/// @notice Deploys all core contracts for the Liiquidate system
/// @dev Deploys AdapterRegistry, FlashLoanRouter, UniversalSwapRouter, Liiquidate,
///      UniswapV4Adapter, and flash loan providers (UniswapV4, AaveV3)
contract DeployScript is Script {
    /// @notice Helper configuration contract
    HelperConfig helperConfig;
    /// @notice Registry for liquidation adapters
    AdapterRegistry adapterRegistry;
    /// @notice Router for flash loan execution
    FlashLoanRouter flashRouter;
    /// @notice Router for token swaps
    UniversalSwapRouter swapRouter;
    /// @notice Main liquidation consumer contract
    Liiquidate liiquidate;
    /// @notice Uniswap V4 swap adapter
    UniswapV4Adapter uniswapAdapter;
    /// @notice Uniswap V4 flash loan provider
    UniswapV4 uniswapFlashloan;
    /// @notice Aave V3 flash loan provider
    AaveV3 aaveV3Flashloan;

    /// @notice Main deployment function
    /// @dev Deploys all contracts and configures them with proper addresses and priorities
    function run() public {
        helperConfig = new HelperConfig();

        (
            address forwarderAddress,
            address aaveV3PoolAddress,
            address uniswapV4PoolAddress
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(helperConfig.deployerKey());

        ////// DEPLOY CORE CONTRACTS //////

        adapterRegistry = new AdapterRegistry();
        flashRouter = new FlashLoanRouter();
        swapRouter = new UniversalSwapRouter();

        ////// DEPLOY & REGISTER SWAP ADAPTER //////

        uniswapAdapter = new UniswapV4Adapter(uniswapV4PoolAddress);
        swapRouter.registerAdapter(address(uniswapAdapter));
        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = uniswapAdapter.protocolId();
        swapRouter.setProtocolPriority(protocols);

        ///// DEPLOY AND REGISTER FLASH LOAN ADAPTERS /////

        uniswapFlashloan = new UniswapV4(
            uniswapV4PoolAddress,
            address(swapRouter)
        );
        aaveV3Flashloan = new AaveV3(
            aaveV3PoolAddress,
            address(swapRouter)
        );
        flashRouter.addProvider(address(uniswapFlashloan));
        flashRouter.addProvider(address(aaveV3Flashloan));
        bytes32[] memory _protocols = new bytes32[](2);
        _protocols[0] = uniswapFlashloan.id();
        _protocols[1] = aaveV3Flashloan.id();
        flashRouter.setProviderPriority(_protocols);

        ///// DEPLOY LIIQUIDATE AND SET AS PROXY /////

        liiquidate = new Liiquidate(
            helperConfig.USDC(),
            address(adapterRegistry), 
            address(flashRouter), 
            forwarderAddress
        );

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
