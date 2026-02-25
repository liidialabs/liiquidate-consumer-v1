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

    address public constant uniswapV4PoolAddress = 0xdb04b6E343E627d0Bbb27be89acbaAAa725ed4e7;
    address public constant aaveV3PoolAddress = 0x05c19F220705dcfd95850a108852116a04471805;
    address public constant adapterRegistryAddress = 0x23402f076cfBB11b70f47422dF36EB3795fDabdc;
    address public constant flashLoanRouterAddress = 0x0A8D5CE8f56Bbd02b054e8894E5263a7c308eD30;
    address public constant universalSwapRouterAddress = 0xf5c3deBc4cf1598bb506C3e7ae85f415Ab81e053;
    address public constant liiquidateAddress = 0x79cDbbefC1b8fe6d907Cf439FF8897FE67d2EbEE;
    address public constant uniswapV4AdapterAddress = 0xFe041876187AA9912F401ef559Ffab3B87049628;
    address public constant uniswapV4FlashloanAddress = 0xb9F26047345f0d9644Cf773F68cB2bCa6D536D83;
    address public constant aaveV3FlashloanAddress = 0xBFCdbD2055C77D080204908071904Ac9Ee966F63;

    address public constant mockChainlinkOracle = 0x45B9FB5ff8871BEcA4CbCceA02647BAf6648c286;
    address public constant liiBorrowV1AdapterAddress = 0x86FC5bb9F9Ab147c2D4A087CE8013DaA58b7C3fd;

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