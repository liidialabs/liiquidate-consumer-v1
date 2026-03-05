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
    /// @notice Current active LiiBorrow configuration
    LiiBorrowConfig public activeLiiBorrowConfig;
    /// @notice Current active Liiquidate configuration
    LiiquidateConfig public activeLiiquidateConfig;
    /// @notice Current active MockConfig configuration
    MockConfig public activeMockConfig;

    /// @notice Mock contracts instances
    MockChainlinkAutomationForwarder forwarder;
    MockUniswapV4PoolManager uniswapV4Pool;
    MockAaveV3Pool aaveV3pool;

    /// @notice Deployer private key from environment
    uint256 public deployerKey = vm.envUint("PRIVATE_KEY_DEPLOYER");

    /// @notice Network configuration structure
    /// @dev Contains addresses for Chainlink forwarder and protocol pools
    struct NetworkConfig {
        address forwarderAddress;
        address aaveV3PoolAddress;
        address uniswapV4PoolAddress;
    }

    /// @notice LiiBorrow configuration structure
    /// @dev Contains DebtManager addresses for DebtManager, Aave, WETH and USDC
    struct LiiBorrowConfig {
        address debtManagerAddress;
        address aaveAddress;
        address weth;
        address usdc;
    }

    /// @notice Liiquidate configuration structure
    /// @dev Contains addresses for flash loan contracts, swappers and core contracts
    struct LiiquidateConfig {
        address adapterRegistryAddress;
        address flashLoanRouterAddress;
        address universalSwapRouterAddress;
        address liiquidateAddress;
        address uniswapV4FlashloanAddress;
        address aaveV3FlashloanAddress;
        address uniswapV4AdapterAddress;
        address liiBorrowV1AdapterAddress;
    }

    /// @notice Mock contracts configuration structure
    /// @dev Contains addresses for mocks
    struct MockConfig {
        address mockChainlinkOracle;
        address mockAaveV3Oracle;
        address mockAaveV3Pool;
    }


    /// @notice Fetchs config data based on chain
    constructor() {
        // sepolia
        if (block.chainid == 111_55_111) {
            (
                activeNetworkConfig,
                activeLiiBorrowConfig,
                activeLiiquidateConfig,
                activeMockConfig
            ) = getSepoliaConfig();
        }
        // mainnet
        if(block.chainid == 1) {
            (
                activeNetworkConfig,
                activeLiiBorrowConfig,
                activeLiiquidateConfig,
                activeMockConfig
            ) = getMainnetConfig();
        }
    }

    /// @notice Returns Mainnet network configuration
    /// @return mainnetNetworkConfig NetworkConfig with Mainnet addresses
    function getMainnetConfig() public pure returns (
        NetworkConfig memory mainnetNetworkConfig,
        LiiBorrowConfig memory mainnetLiiBorrowConfig,
        LiiquidateConfig memory mainnetLiiquidateConfig,
        MockConfig memory mainnetMockConfig
    ) {
        mainnetNetworkConfig = NetworkConfig({
            forwarderAddress: address(0),
            aaveV3PoolAddress: address(0),
            uniswapV4PoolAddress: address(0)
        });
        mainnetLiiBorrowConfig = LiiBorrowConfig({
            debtManagerAddress: address(0),
            aaveAddress: address(0),
            weth: address(0),
            usdc: address(0)
        });
        mainnetLiiquidateConfig = LiiquidateConfig({
            adapterRegistryAddress: address(0),
            flashLoanRouterAddress: address(0),
            universalSwapRouterAddress: address(0),
            liiquidateAddress: address(0),
            uniswapV4FlashloanAddress: address(0),
            aaveV3FlashloanAddress: address(0),
            uniswapV4AdapterAddress: address(0),
            liiBorrowV1AdapterAddress: address(0)
        });
        mainnetMockConfig = MockConfig({
            mockChainlinkOracle: address(0),
            mockAaveV3Oracle: address(0),
            mockAaveV3Pool: address(0)
        });
    }

    /// @notice Returns Sepolia network configuration
    /// @dev Includes deployed mocks
    /// @return sepoliaNetworkConfig NetworkConfig with Sepolia addresses
    function getSepoliaConfig() public returns (
        NetworkConfig memory sepoliaNetworkConfig,
        LiiBorrowConfig memory sepoliaLiiBorrowConfig,
        LiiquidateConfig memory sepoliaLiiquidateConfig,
        MockConfig memory sepoliaMockConfig
    ) {

        // update address(0) values after deploying
        address aaveV3PoolAddress = address(0);
        address uniswapV4PoolAddress = address(0);

        vm.startBroadcast();

        // deploy only if both aaveV3PoolAddress & uniswapV4PoolAddress are zeroAddress
        if(aaveV3PoolAddress == address(0) && uniswapV4PoolAddress == address(0)) {
            // deploy mocks
            uniswapV4Pool = new MockUniswapV4PoolManager();
            aaveV3pool = new MockAaveV3Pool();
            // assign addresses 
            aaveV3PoolAddress = address(aaveV3pool);
            uniswapV4PoolAddress = address(uniswapV4Pool);
            // Log addresses
            console2.log("Deployed MockUniswapV4PoolManager on %s", aaveV3PoolAddress);
            console2.log("Deployed MockAaveV3Pool on %s", uniswapV4PoolAddress);
            console2.log("------------------------------------------------------");
        }
        
        vm.stopBroadcast();

        sepoliaNetworkConfig = NetworkConfig({
            forwarderAddress: 0x15fC6ae953E024d975e77382eEeC56A9101f9F88, // chainlink Sepolia forwarder address
            aaveV3PoolAddress: aaveV3PoolAddress,
            uniswapV4PoolAddress: uniswapV4PoolAddress
        });

        sepoliaLiiBorrowConfig = LiiBorrowConfig({
            debtManagerAddress: address(0),
            aaveAddress: address(0),
            weth: address(0),
            usdc: address(0)
        });
        sepoliaLiiquidateConfig = LiiquidateConfig({
            adapterRegistryAddress: address(0),
            flashLoanRouterAddress: address(0),
            universalSwapRouterAddress: address(0),
            liiquidateAddress: address(0),
            uniswapV4FlashloanAddress: address(0),
            aaveV3FlashloanAddress: address(0),
            uniswapV4AdapterAddress: address(0),
            liiBorrowV1AdapterAddress: address(0)
        });
        sepoliaMockConfig = MockConfig({
            mockChainlinkOracle: address(0),
            mockAaveV3Oracle: address(0),
            mockAaveV3Pool: address(0)
        });
    }
}