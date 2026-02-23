// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {MockChainlinkAutomationForwarder} from "../test/mocks/MockChainlinkAutomationForwarder.sol";
import {MockAaveV3Pool} from "../test/mocks/MockAaveV3Pool.sol";
import {MockUniswapV4PoolManager} from "../test/mocks/MockUniswapV4PoolManager.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    MockChainlinkAutomationForwarder forwarder;
    MockUniswapV4PoolManager uniswapV4Pool;
    MockAaveV3Pool aaveV3pool;

    // Constants for known addresses on Sepolia
    address public constant debtManagerAddress = 0xCb737805008c5a01928DD572A164F5b8001c562d;
    address public constant aaveAddress = 0x2853eA59358977011a8Bf653ab00d975871e3D6e;
    address public constant WETH = 0x394A1145Cc4480cD047ad065a5Ece23D4fcC2E1d;
    address public constant USDC = 0xf8340a3BB21282Af32B567e0ACE1Cc5c4eF63a73;
    address public constant mockPool = 0xDB79AF69617bFcB71D55E7575bFbb1De86151eF9;
    address public constant mockAaveV3Oracle = 0x10C979d0f556799262CF3934e211BDA4e4E9074A;

    address public constant forwarderAddress = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88; 

    address public constant uniswapV4PoolAddress = 0x64700291F4E2329047acf0B4F9c8c796D336B97d;
    address public constant aaveV3PoolAddress = 0x10f5F49BC55bCf438A023cd923A1d7127C6E270F;
    address public constant adapterRegistryAddress = 0x8043986Ed349E4C08A0f2b6AaA86dDE7DC6E0487;
    address public constant flashLoanRouterAddress = 0x23350762BC9f90de70fdDBa7ca1B3fa176FDA43A;
    address public constant universalSwapRouterAddress = 0x35ce0B20c91369bc430BB62D18C05267aE7338bd;
    address public constant liiquidateAddress = 0x29521DB6c3A2a62216c2beC98cc6A620DA6ba9A5;
    address public constant uniswapV4AdapterAddress = 0x82C136DF94c0e0318b10d152dDe58eD6c646cc02;
    address public constant uniswapV4FlashloanAddress = 0x48487E0EC3022B3bE0e00fA61F5826c82Adb8F49;
    address public constant aaveV3FlashloanAddress = 0x177AbA67e06fD2dEaB774A058456Ef3062761735;

    address public constant mockChainlinkOracle = 0x391d99c8C51447Ae2A03f22e364DED4d34A50Cb8;
    address public constant liiBorrowV1AdapterAddress = 0x5d45bF860070e05553DAB447710C904a1006fA9c;

    uint256 public deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

    struct NetworkConfig {
        address forwarderAddress;
        address aaveV3PoolAddress;
        address uniswapV4PoolAddress;
    }

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        // if (block.chainid == 111_55_111) {
        //     activeNetworkConfig = getSepoliaConfig();
        //     if(activeNetworkConfig.aaveV3PoolAddress == address(0)) {
        //         activeNetworkConfig = getOrCreateConfig();
        //     }
        // } else if (block.chainid == 84532) {
        //     activeNetworkConfig = getBaseSepoliaConfig();
        // }
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0)
        });
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0)
        });
    }

    function getOrCreateConfig() public returns (NetworkConfig memory createdNetworkConfig) {
        vm.startBroadcast();

        // forwarder = new MockChainlinkAutomationForwarder();
        uniswapV4Pool = new MockUniswapV4PoolManager();
        aaveV3pool = new MockAaveV3Pool();

        // Logs
        console2.log("Deployed MockUniswapV4PoolManager on %s", address(uniswapV4Pool));
        console2.log("Deployed MockAaveV3Pool on %s", address(aaveV3pool));
        console2.log("------------------------------------------------------");
        
        vm.stopBroadcast();

        createdNetworkConfig = NetworkConfig({
            forwarderAddress: forwarderAddress,
            aaveV3PoolAddress: address(aaveV3pool),
            uniswapV4PoolAddress: address(uniswapV4Pool)
        });
    }
}