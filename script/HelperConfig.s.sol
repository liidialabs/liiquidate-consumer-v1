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
    address public constant debtManagerAddress = 0xFB56BcBB16eF411Ad25EE507d7c2430e561ae3E0;
    /// @notice Aave V3 Pool address on Sepolia
    address public constant aaveAddress = 0x4051A4D767C41074bA8d714083DB2308EA55B7c4;
    /// @notice WETH token address on Sepolia
    address public constant WETH = 0x6de4964bfEbCa1848c74FeaA6736b14898DfDB0c;
    /// @notice USDC token address on Sepolia
    address public constant USDC = 0x23256311E41354c00E880D5b923A64552f077FD3;
    /// @notice Mock Pool address for testing
    address public constant mockPool = 0xe1B210f9064001a2db724e8DA6166CD76737DD40;
    /// @notice Mock Aave Oracle address
    address public constant mockAaveV3Oracle = 0xe6dC6561a06cFD9969761913D38EcC58cE7227B9;
    /// @notice Chainlink Automation Forwarder address
    address public constant forwarderAddress = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88; 
    /// @notice Uniswap V4 Pool Manager address
    address public constant uniswapV4PoolAddress = 0x28bce4c43AE57CA894be69C73aD7366608098853;
    /// @notice Aave V3 Pool address
    address public constant aaveV3PoolAddress = 0xA4C3D01916A0a27f6F182B4b569C9936d5eB3BB6;
    /// @notice Adapter Registry address
    address public constant adapterRegistryAddress = 0xd74963e909FF1e68A16883addA3e17b892f78d35;
    /// @notice Flash Loan Router address
    address public constant flashLoanRouterAddress = 0xB55dB475d4791e4434308B9E1ba37916115F08b7;
    /// @notice Universal Swap Router address
    address public constant universalSwapRouterAddress = 0xa007e01273081543d476A9deFC3Bd985EcF5b34c;
    /// @notice Liiquidate contract address
    address public constant liiquidateAddress = 0xEaD1FCB130c0539b883b87513a900c9198c6d2d5;
    /// @notice Uniswap V4 Adapter address
    address public constant uniswapV4AdapterAddress = 0xff29F2B180C1616Afec88B910BC35E7e99eC8388;
    /// @notice Uniswap V4 Flashloan address
    address public constant uniswapV4FlashloanAddress = 0x04b9215dc984b771641D5d7bAcb54e1D2dD99b0e;
    /// @notice Aave V3 Flashloan address
    address public constant aaveV3FlashloanAddress = 0x6B02ceff69997592C5D3f8199C60A226ECE85eB8;
    /// @notice Mock Chainlink Oracle address
    address public constant mockChainlinkOracle = 0x82a9d607cC8df65AF2910E04211Ebd7e989f5379;
    /// @notice LiiBorrow V1 Adapter address
    address public constant liiBorrowV1AdapterAddress = 0x38e933A0d6582453E831c47e7D1863B634dB17f1;

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

    constructor() {
        // if (block.chainid == 111_55_111) {
        //     activeNetworkConfig = getSepoliaConfig();
        //     if(activeNetworkConfig.aaveV3PoolAddress == address(0)) {
        //         activeNetworkConfig = getMockConfigs();
        //     }
        // }
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
    function getMockConfigs() public returns (NetworkConfig memory createdNetworkConfig) {
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