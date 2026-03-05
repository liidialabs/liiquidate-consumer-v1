// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {UniswapV4Adapter} from "../src/swappers/UniswapV4Adapter.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {MockAaveV3Pool} from "../test/mocks/MockAaveV3Pool.sol";
import {MockUniswapV4PoolManager} from "../test/mocks/MockUniswapV4PoolManager.sol";
import {MockV3Aggregator} from "../test/mocks/MockChainlinkOracle.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {ISwapAdapter} from "../src/interfaces/swapAdapter/ISwapAdapter.sol";

/// @title ConfigureMocks
/// @notice Configures mock contracts for local testing environment
/// @dev Sets up MockAaveV3Pool and MockUniswapV4PoolManager with initial liquidity and configurations
contract ConfigureMocks is Script {
    using PoolIdLibrary for PoolKey;

    HelperConfig helperConfig;
    MockAaveV3Pool aaveV3Pool;
    MockUniswapV4PoolManager uniswapV4Pool;
    MockV3Aggregator priceFeed;
    UniswapV4Adapter uniswapAdapter;

    MockERC20 USDC;
    MockERC20 WETH;

    /// @notice Initial USDC balance for mock pools (1 million USDC)
    uint256 constant INITIAL_USDC_BALANCE = 1_000_000e6;
    /// @notice Initial WETH balance for mock pools (1 million WETH)
    uint256 constant INITIAL_WETH_BALANCE = 1_000_000e18;
    /// @notice Uniswap V4 pool fee tier (0.3%)
    uint24 constant POOL_FEE = 3000;

    /// @notice Main configuration function
    /// @dev Deploys mock price feed, configures Aave V3 and Uniswap V4 pools
    function run() public {
        // deploy helperConfig
        helperConfig = new HelperConfig();
        // fetch addresses
        (
            ,
            address aaveV3PoolAddress,
            address uniswapV4PoolAddress
        ) = helperConfig.activeNetworkConfig();
        (
            ,,
            address weth,
            address usdc
        ) = helperConfig.activeLiiBorrowConfig();
        (
            ,,,,,,
            address uniswapV4AdapterAddress,
        ) = helperConfig.activeLiiquidateConfig();

        vm.startBroadcast(helperConfig.deployerKey());

        priceFeed = new MockV3Aggregator(8, 2000e8, "WETH/USD");

        USDC = MockERC20(usdc);
        WETH = MockERC20(weth);

        aaveV3Pool = MockAaveV3Pool(payable(aaveV3PoolAddress));
        uniswapV4Pool = MockUniswapV4PoolManager(payable(uniswapV4PoolAddress));
        uniswapAdapter = UniswapV4Adapter(payable(uniswapV4AdapterAddress));

        _configureAaveV3Pool(aaveV3Pool);
        _configureUniswapV4Pool(uniswapV4Pool);

        console2.log("Completed configuration of mock contracts:");
        console2.log("Mock WETH/USD price feed address:", address(priceFeed));

        vm.stopBroadcast();
    }

    /// @notice Configures Aave V3 mock pool with supported assets
    /// @dev Sets USDC and WETH as supported assets with initial balances
    /// @param _aaveV3Pool The Aave V3 pool to configure
    function _configureAaveV3Pool(
        MockAaveV3Pool _aaveV3Pool
    ) internal {
        _aaveV3Pool.setAssetSupported(address(USDC), true);
        _aaveV3Pool.setAssetReservement(address(USDC), INITIAL_USDC_BALANCE);
        USDC.mint(address(aaveV3Pool), INITIAL_USDC_BALANCE);
        _aaveV3Pool.setAssetSupported(address(WETH), true);
        _aaveV3Pool.setAssetReservement(address(WETH), INITIAL_WETH_BALANCE);
        WETH.mint(address(aaveV3Pool), INITIAL_WETH_BALANCE);

        console2.log("Configured MockAaveV3Pool with USDC and WETH support");
    }

    /// @notice Configures Uniswap V4 mock pool with WETH/USDC pool
    /// @dev Initializes pool with liquidity and registers swap path in adapter
    /// @param _uniswapV4Pool The Uniswap V4 pool manager to configure
    function _configureUniswapV4Pool(
        MockUniswapV4PoolManager _uniswapV4Pool
    ) internal {
        USDC.mint(address(uniswapV4Pool), INITIAL_USDC_BALANCE);
        WETH.mint(address(uniswapV4Pool), INITIAL_WETH_BALANCE);

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(address(USDC)),
            fee: uint24(POOL_FEE),
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(poolKey);

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        uint160 sqrtPriceX96 = 3543191142285914205922034323214; // for 2000USDC/1WETH
        _uniswapV4Pool.initialize(
            poolKey,
            sqrtPriceX96,
            1000e18
        );

        uniswapAdapter.registerSwapPath(
            address(WETH),
            address(USDC),
            path,
            poolData,
            fees
        );

        console2.log("Configured MockUniswapV4Pool with WETH/USDC pool and registered swap path in adapter");
    }
}