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
            ) = getSepoliaConfig(); // change to getMainnetConfig when not deploying, currently using sepolia as we using Tenderly Virtual TestNet
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
        address aaveV3PoolAddress = 0xa543f90B8F35EaA0b6c16E774828ebaAd42a0155;
        address uniswapV4PoolAddress = 0x60E2c27bF334ebF7013f973f59f006076dc61e80;

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
            console2.log("Deployed MockAaveV3Pool on %s", aaveV3PoolAddress);
            console2.log("Deployed MockUniswapV4PoolManager on %s", uniswapV4PoolAddress);
            console2.log("------------------------------------------------------");
        }
        
        vm.stopBroadcast();

        sepoliaNetworkConfig = NetworkConfig({
            forwarderAddress: 0xA3D1AD4Ac559a6575a114998AffB2fB2Ec97a7D9, // chainlink Sepolia forwarder address
            aaveV3PoolAddress: aaveV3PoolAddress,
            uniswapV4PoolAddress: uniswapV4PoolAddress
        });

        sepoliaLiiBorrowConfig = LiiBorrowConfig({
            debtManagerAddress: 0x4E0Af3287669D331BB5B858B738B0be069b7C750,
            aaveAddress: 0x4fc08467e75db0123480d869239Afd9CCBeE0951,
            weth: 0x49C954F846e870FE5402C7F65cD035592c81aadB,
            usdc: 0x8ca959E4c4745df0E2fE5CE5fAcFD3F35ae509e9
        });
        sepoliaLiiquidateConfig = LiiquidateConfig({
            adapterRegistryAddress: 0x8d1D8766396C828ADa63B508186A83B8289d4bA1,
            flashLoanRouterAddress: 0xbAAc86Db65BBd8A92741780FF4157eB5f490c51f,
            universalSwapRouterAddress: 0xFB43092C66D31942440AFb113cA6F26e061C85D9,
            liiquidateAddress: 0xa9D309dFe0924Ba65A5EFa9D9Ea9528E43562934,
            uniswapV4FlashloanAddress: 0x435b2c4135517700ba80EaD194930f49239Fdb8e,
            aaveV3FlashloanAddress: 0x555d05ccf5590068679c07519445705f9f8CB62f,
            uniswapV4AdapterAddress: 0xb2Bf9de9308747e5f0dafCb48c45928442261700,
            liiBorrowV1AdapterAddress: 0xBC3192c86c99c1dCE635Fe2C9cCA375e2Ab1556D
        });
        sepoliaMockConfig = MockConfig({
            mockChainlinkOracle: 0x1E1e2a398EBA72C5D4bdEA909F3bC928eFfF4505,
            mockAaveV3Oracle: 0xDFe8c6121b43e3B5bd0731F724007D0119B838bc,
            mockAaveV3Pool: 0xd64033432e085905487A490441C0cF8D47E1c40f
        });
    }
}