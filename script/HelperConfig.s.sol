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
    address public constant debtManagerAddress = 0x3f26685991D09eCd40227Efb7649Ca2A371708CC;
    address public constant aaveAddress = 0x2853eA59358977011a8Bf653ab00d975871e3D6e;
    address public constant WETH = 0x394A1145Cc4480cD047ad065a5Ece23D4fcC2E1d;
    address public constant USDC = 0xf8340a3BB21282Af32B567e0ACE1Cc5c4eF63a73;
    address public constant mockPool = 0xDB79AF69617bFcB71D55E7575bFbb1De86151eF9;
    address public constant mockAaveV3Oracle = 0x10C979d0f556799262CF3934e211BDA4e4E9074A;

    address public constant forwarderAddress = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88; 

    address public constant uniswapV4PoolAddress = 0xdB3Be29F46988C7cb8517aB4152982e5ac318222;
    address public constant aaveV3PoolAddress = 0xf546bCddbBAE1446EB9B5BE9a411BE8B81e8475A;
    address public constant adapterRegistryAddress = 0x4CB625A5249397f19B4CC536A6E9188326f6c407;
    address public constant flashLoanRouterAddress = 0x9C94Fa6637B37B5e7507937a83955B2c616Eeac4;
    address public constant universalSwapRouterAddress = 0xe727F23641399B9869c4e96ae605b09a6459B4a1;
    address public constant liiquidateAddress = 0x898E7153F0F4A209b277D21f62111aeE28537dCb;
    address public constant uniswapV4AdapterAddress = 0x04bEC3Af60eC545BbEfC1B14411D72dcDC654684;
    address public constant uniswapV4FlashloanAddress = 0xec5f7FBC9C6751f24E7a91A0f84780ab1044BD5B;
    address public constant aaveV3FlashloanAddress = 0xd34aa92863367e71CB3f007e08f0ddCb1a9E1cC4;

    address public constant mockChainlinkOracle = 0xaeEffddcC3095DC4037D58B654a371b7Ff679F30;
    address public constant liiBorrowV1AdapterAddress = 0xb4Bae94D879888EbB1e3f8e4D73ddD9a49dACFC9;

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

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0)
        });
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
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