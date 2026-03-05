// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IMockAaveV3Pool} from "../test/mocks/interfaces/IMockAaveV3Pool.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockChainlinkOracle.sol";
import {IMockAaveOracle} from "../test/mocks/interfaces/IMockAaveOracle.sol";

/// @title SupplyToLiidia
/// @notice Supplies collateral to the LiiBorrow protocol for testing
/// @dev Mints WETH to user and deposits it as collateral in the DebtManager
contract SupplyToLiidia is Script {
    IDebtManager debtManager;
    MockERC20 WETH;
    HelperConfig helperConfig;
    IMockAaveV3Pool _mockAaveV3Pool;
    IMockAaveOracle aaveOracle;
    MockV3Aggregator priceFeed;

    /// @notice User private key from environment
    uint256 private USER = vm.envUint("PRIVATE_KEY_USER");
    /// @notice Amount of WETH to supply (1 WETH)
    uint256 constant SUPPLY_AMOUNT = 1e18;

    /// @notice Main supply function
    /// @dev Mints WETH to user, approves DebtManager, deposits collateral
    function run() public {
        // deploy helperConfig
        helperConfig = new HelperConfig();
        // fetch addresses
        (
            address mockChainlinkOracle,
            address mockAaveV3Oracle,
            address mockAaveV3Pool
        ) = helperConfig.activeMockConfig();
        (
            address debtManagerAddress,,
            address weth,
            address usdc
        ) = helperConfig.activeLiiBorrowConfig();

        WETH = MockERC20(weth);
        _mockAaveV3Pool = IMockAaveV3Pool(mockAaveV3Pool);
        priceFeed = MockV3Aggregator(mockChainlinkOracle);
        aaveOracle = IMockAaveOracle(mockAaveV3Oracle);

        vm.startBroadcast(USER);

        address userAddress = vm.addr(USER);

        WETH.mint(userAddress, SUPPLY_AMOUNT);

        debtManager = IDebtManager(debtManagerAddress);
        WETH.approve(debtManagerAddress, SUPPLY_AMOUNT);
        debtManager.depositCollateralERC20(weth, SUPPLY_AMOUNT);

        _mockAaveV3Pool.setUserAccountData(
            address(debtManager),
            200000e8,
            0,
            160000e8,
            8250,
            8000,
            type(uint256).max
        );

        console2.log("Successfully supplied 1 WETH to the protocol!");
        console2.log("Price at $2000 USD");
        console2.log("------------------------------------------------------------");

        vm.stopBroadcast();

        uint256 balance = debtManager.getCollateralBalanceOfUser(userAddress, weth);
        console2.log("User collateral balance from DebtManager: %s WETH", balance );
    }
}