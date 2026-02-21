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

contract ConfigureMocks is Script {
    using PoolIdLibrary for PoolKey;

    HelperConfig helperConfig;
    MockAaveV3Pool aaveV3Pool;
    MockUniswapV4PoolManager uniswapV4Pool;
    MockV3Aggregator priceFeed;
    UniswapV4Adapter uniswapAdapter;

    MockERC20 USDC;
    MockERC20 WETH;

    // Addresses for the deployed contracts
    address private uniswapV4AdapaterAddress = 0x000000000000000000000000000000000000dEaD; // Replace with actual

    // Initial liquidity amounts for the mock pools
    uint256 constant INITIAL_USDC_BALANCE = 1_000_000e6; // 1 million USDC with 6 decimals
    uint256 constant INITIAL_WETH_BALANCE = 1_000_000e18; // 1 million WETH with 18 decimals

    uint24 constant POOL_FEE = 3000; // 0.3% fee tier for Uniswap V4

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();
        (
            ,
            address aaveV3PoolAddress,
            address uniswapV4PoolAddress,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // deploy WETH/USD mock price feed, initial price $2000
        priceFeed = new MockV3Aggregator(8, 2000e8, "WETH/USD");

        // deploy mock ERC20 tokens
        USDC = new MockERC20("USD Coin", "USDC", 6);
        WETH = new MockERC20("Wrapped Ether", "WETH", 18);

        // Create contract instances
        aaveV3Pool = MockAaveV3Pool(payable(aaveV3PoolAddress));
        uniswapV4Pool = MockUniswapV4PoolManager(payable(uniswapV4PoolAddress));
        uniswapAdapter = UniswapV4Adapter(payable(uniswapV4AdapaterAddress));

        // Aave V3
        _configureAaveV3Pool(aaveV3Pool);
        // Uniswap V4
        _configureUniswapV4Pool(uniswapV4Pool);

        /// LOGS
        console2.log("Mock WETH/USD price feed address:", address(priceFeed));
        console2.log("Mock USDC address:", address(USDC));
        console2.log("Mock WETH address:", address(WETH));

        vm.stopBroadcast();

    }

    ////////// CONFIGURE AAVE V3 MOCK POOL ///////////

    function _configureAaveV3Pool(
        MockAaveV3Pool _aaveV3Pool
    ) internal {
        // Set USDC (debt token) 
        _aaveV3Pool.setAssetSupported(address(USDC), true);
        _aaveV3Pool.setAssetReservement(address(USDC), INITIAL_USDC_BALANCE);
        USDC.mint(address(aaveV3Pool), INITIAL_USDC_BALANCE);
        // Set WETH (collateral token)
        _aaveV3Pool.setAssetSupported(address(WETH), true);
        _aaveV3Pool.setAssetReservement(address(WETH), INITIAL_WETH_BALANCE);
        WETH.mint(address(aaveV3Pool), INITIAL_WETH_BALANCE);
    }

    ////////// CONFIGURE UNISWAP V4 MOCK POOL ///////////

    function _configureUniswapV4Pool(
        MockUniswapV4PoolManager _uniswapV4Pool
    ) internal {
        // Mint tokens to the pool
        USDC.mint(address(uniswapV4Pool), INITIAL_USDC_BALANCE);
        WETH.mint(address(uniswapV4Pool), INITIAL_WETH_BALANCE);

        // Setup token path
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);

        // Create PoolKey for the tokenA/tokenB pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(address(USDC)),
            fee: uint24(POOL_FEE),
            tickSpacing: 60,  // Adjust based on your fee tier
            hooks: IHooks(address(0))  // No hooks, or use your hooks address
        });

        // Encode the PoolKey (not the pool manager address)
        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(poolKey);

        // Setup fees array
        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        // Initialize the pool in the mock (so sqrtPriceX96 != 0)
        uint160 sqrtPriceX96 = 2967187660000000000000000000000;
        _uniswapV4Pool.initialize(
            poolKey,
            sqrtPriceX96,  
            1000e18
        );

        // Register the swap path
        uniswapAdapter.registerSwapPath(
            address(WETH),
            address(USDC),
            path,
            poolData,
            fees
        );
    }

}