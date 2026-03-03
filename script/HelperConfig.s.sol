// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {MockChainlinkAutomationForwarder} from "../test/mocks/MockChainlinkAutomationForwarder.sol";
import {MockAaveV3Pool} from "../test/mocks/MockAaveV3Pool.sol";
import {MockUniswapV4PoolManager} from "../test/mocks/MockUniswapV4PoolManager.sol";

/// @title HelperConfig
/// @notice Configuration contract for managing network-specific addresses and deployment settings
/// @dev Provides pre-configured addresses for Sepolia testnet and helper functions for local anvil testing
contract HelperConfig is Script {
    /// @notice Current active network configuration
    NetworkConfig public activeNetworkConfig;

    MockChainlinkAutomationForwarder forwarder;
    MockUniswapV4PoolManager uniswapV4Pool;
    MockAaveV3Pool aaveV3pool;

    // Constants for known addresses on Sepolia
    /// @notice LiiBorrow DebtManager address on Sepolia
    address public constant debtManagerAddress = 0x3f26685991D09eCd40227Efb7649Ca2A371708CC;
    /// @notice Aave V3 Pool address on Sepolia
    address public constant aaveAddress = 0x2853eA59358977011a8Bf653ab00d975871e3D6e;
    /// @notice WETH token address on Sepolia
    address public constant WETH = 0x394A1145Cc4480cD047ad065a5Ece23D4fcC2E1d;
    /// @notice USDC token address on Sepolia
    address public constant USDC = 0xf8340a3BB21282Af32B567e0ACE1Cc5c4eF63a73;
    /// @notice Mock Pool address for testing
    address public constant mockPool = 0xDB79AF69617bFcB71D55E7575bFbb1De86151eF9;
    /// @notice Mock Aave Oracle address
    address public constant mockAaveV3Oracle = 0x10C979d0f556799262CF3934e211BDA4e4E9074A;
    /// @notice Chainlink Automation Forwarder address
    address public constant forwarderAddress = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88; 
    /// @notice Uniswap V4 Pool Manager address
    address public constant uniswapV4PoolAddress = 0xdB3Be29F46988C7cb8517aB4152982e5ac318222;
    /// @notice Aave V3 Pool address
    address public constant aaveV3PoolAddress = 0xf546bCddbBAE1446EB9B5BE9a411BE8B81e8475A;
    /// @notice Adapter Registry address
    address public constant adapterRegistryAddress = 0x4CB625A5249397f19B4CC536A6E9188326f6c407;
    /// @notice Flash Loan Router address
    address public constant flashLoanRouterAddress = 0x9C94Fa6637B37B5e7507937a83955B2c616Eeac4;
    /// @notice Universal Swap Router address
    address public constant universalSwapRouterAddress = 0xe727F23641399B9869c4e96ae605b09a6459B4a1;
    /// @notice Liiquidate contract address
    address public constant liiquidateAddress = 0x87888dAEE178A598ff62E3E0c26Cb202e6E7fAC6;
    /// @notice Uniswap V4 Adapter address
    address public constant uniswapV4AdapterAddress = 0x04bEC3Af60eC545BbEfC1B14411D72dcDC654684;
    /// @notice Uniswap V4 Flashloan address
    address public constant uniswapV4FlashloanAddress = 0xec5f7FBC9C6751f24E7a91A0f84780ab1044BD5B;
    /// @notice Aave V3 Flashloan address
    address public constant aaveV3FlashloanAddress = 0xd34aa92863367e71CB3f007e08f0ddCb1a9E1cC4;
    /// @notice Mock Chainlink Oracle address
    address public constant mockChainlinkOracle = 0xaeEffddcC3095DC4037D58B654a371b7Ff679F30;
    /// @notice LiiBorrow V1 Adapter address
    address public constant liiBorrowV1AdapterAddress = 0xb4Bae94D879888EbB1e3f8e4D73ddD9a49dACFC9;

    /// @notice Deployer private key from environment
    uint256 public deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

    /// @notice Network configuration structure
    /// @dev Contains addresses for Chainlink forwarder and protocol pools
    struct NetworkConfig {
        address forwarderAddress;
        address aaveV3PoolAddress;
        address uniswapV4PoolAddress;
    }

    /// @notice Default Anvil private key for local testing
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {}

    /// @notice Returns Base Sepolia network configuration
    /// @return mainnetNetworkConfig NetworkConfig with zero addresses
    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory mainnetNetworkConfig) {
        mainnetNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0)
        });
    }

    /// @notice Returns Sepolia network configuration
    /// @return sepoliaNetworkConfig NetworkConfig with Sepolia addresses
    function getSepoliaConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0)
        });
    }

    /// @notice Creates or retrieves local anvil configuration with deployed mocks
    /// @dev Deploys MockUniswapV4PoolManager and MockAaveV3Pool for local testing
    /// @return createdNetworkConfig NetworkConfig with mock addresses
    function getOrCreateConfig() public returns (NetworkConfig memory createdNetworkConfig) {
        vm.startBroadcast();

        uniswapV4Pool = new MockUniswapV4PoolManager();
        aaveV3pool = new MockAaveV3Pool();

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