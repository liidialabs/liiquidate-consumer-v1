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

    address private FORWARDER_ADDRESS;

    struct NetworkConfig {
        address forwarderAddress;
        address aaveV3PoolAddress;
        address uniswapV4PoolAddress;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 111_55_111) {
            activeNetworkConfig = getSepoliaConfig();
            if(activeNetworkConfig.aaveV3PoolAddress == address(0)) {
                activeNetworkConfig = getOrCreateConfig();
            }
        } else if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        }
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY")
        });
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY")
        });
    }

    function getOrCreateConfig() public returns (NetworkConfig memory createdNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.forwarderAddress != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        // forwarder = new MockChainlinkAutomationForwarder();
        FORWARDER_ADDRESS = 0x000000000000000000000000000000000000dEaD; // Replace with actual
        uniswapV4Pool = new MockUniswapV4PoolManager();
        aaveV3pool = new MockAaveV3Pool();

        // Logs
        console2.log("Forwarder Address on %s", FORWARDER_ADDRESS);
        console2.log("Deployed MockUniswapV4PoolManager on %s", address(uniswapV4Pool));
        console2.log("Deployed MockAaveV3Pool on %s", address(aaveV3pool));
        
        vm.stopBroadcast();

        createdNetworkConfig = NetworkConfig({
            forwarderAddress: FORWARDER_ADDRESS,
            aaveV3PoolAddress: address(aaveV3pool),
            uniswapV4PoolAddress: address(uniswapV4Pool),
            deployerKey: vm.envUint("DEPLOYER_PRIVATE_KEY")
        });
    }
}