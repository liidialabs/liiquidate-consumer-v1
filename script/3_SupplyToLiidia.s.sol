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
    MockERC20 weth;
    HelperConfig helperConfig;
    IMockAaveV3Pool mockAaveV3Pool;
    IMockAaveOracle aaveOracle;
    MockV3Aggregator priceFeed;

    /// @notice User private key from environment
    uint256 private USER = vm.envUint("PRIVATE_KEY_USER");
    /// @notice Amount of WETH to supply (1 WETH)
    uint256 constant SUPPLY_AMOUNT = 1e18;

    /// @notice Main supply function
    /// @dev Mints WETH to user, approves DebtManager, deposits collateral
    function run() public {
        helperConfig = new HelperConfig();

        weth = MockERC20(helperConfig.WETH());
        mockAaveV3Pool = IMockAaveV3Pool(helperConfig.mockPool());
        priceFeed = MockV3Aggregator(helperConfig.mockChainlinkOracle());
        aaveOracle = IMockAaveOracle(helperConfig.mockAaveV3Oracle());

        vm.startBroadcast(USER);

        address userAddress = vm.addr(USER);

        weth.mint(userAddress, SUPPLY_AMOUNT);

        debtManager = IDebtManager(helperConfig.debtManagerAddress());
        weth.approve(helperConfig.debtManagerAddress(), SUPPLY_AMOUNT);
        debtManager.depositCollateralERC20(helperConfig.WETH(), SUPPLY_AMOUNT);

        mockAaveV3Pool.setUserAccountData(
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

        uint256 balance = debtManager.getCollateralBalanceOfUser(userAddress, address(weth));
        console2.log("User collateral balance from DebtManager: %s WETH", balance );
    }
}