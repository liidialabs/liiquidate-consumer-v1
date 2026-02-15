// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MockChainlinkAutomationForwarder} from "../test/mocks/MockChainlinkAutomationForwarder.sol";
import {MockAaveV3Pool} from "../test/mocks/MockAaveV3Pool.sol";
import {MockUniswapV4PoolManager} from "../test/mocks/MockUniswapV4PoolManager.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    MockChainlinkAutomationForwarder forwarder;
    MockUniswapV4PoolManager uniswapV4Pool;
    MockAaveV3Pool aaveV3pool;

    struct NetworkConfig {
        address forwarder;
        address aaveV3Pool;
        address uniswapV4Pool;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11_155_111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            forwarder: address(0),
            aaveV3Pool: address(0),
            uniswapV4Pool: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY")
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            forwarder: address(0),
            aaveV3Pool: address(0),
            uniswapV4Pool: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.forwarder != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        forwarder = new MockChainlinkAutomationForwarder();
        uniswapV4Pool = new MockUniswapV4PoolManager();
        aaveV3pool = new MockAaveV3Pool();
        
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            forwarder: address(forwarder),
            aaveV3Pool: address(aaveV3pool),
            uniswapV4Pool: address(uniswapV4Pool),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}