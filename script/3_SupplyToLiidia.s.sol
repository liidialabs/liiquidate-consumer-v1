// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol"; // Interface for the LiiBorrow Debt Manager
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IMockAaveV3Pool} from "../test/mocks/interfaces/IMockAaveV3Pool.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockChainlinkOracle.sol";
import {IMockAaveOracle} from "../test/mocks/interfaces/IMockAaveOracle.sol";

contract SupplyToLiidia is Script {
    IDebtManager debtManager;
    MockERC20 weth;
    HelperConfig helperConfig;
    IMockAaveV3Pool mockAaveV3Pool;
    IMockAaveOracle aaveOracle;
    MockV3Aggregator priceFeed;

    uint256 private USER = vm.envUint("PRIVATE_KEY_USER");

    int256 constant NEW_PRICE = 2000e8;
    uint256 constant SUPPLY_AMOUNT = 1e18;

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        // create contract instances
        weth = MockERC20(helperConfig.WETH());
        mockAaveV3Pool = IMockAaveV3Pool(helperConfig.mockPool());
        priceFeed = MockV3Aggregator(helperConfig.mockChainlinkOracle());
        aaveOracle = IMockAaveOracle(helperConfig.mockAaveV3Oracle());

        vm.startBroadcast(USER);

        // get user wallet address
        address userAddress = vm.addr(USER);

        // reset price to $2000 USD before supplying collateral
        aaveOracle.setAssetPrice(helperConfig.WETH(), uint256(NEW_PRICE));
        priceFeed.updateAnswer(NEW_PRICE);

        // mint WETH to user wallet for testing
        weth.mint(userAddress, SUPPLY_AMOUNT);

        // Create contract instance
        debtManager = IDebtManager(helperConfig.debtManagerAddress());
        // Approve DebtManager to spend user's WETH
        weth.approve(helperConfig.debtManagerAddress(), SUPPLY_AMOUNT);
        // Supply to LiiBorrow
        debtManager.depositCollateralERC20(helperConfig.WETH(), SUPPLY_AMOUNT);

        // set user account data for testing
        mockAaveV3Pool.setUserAccountData(
            address(debtManager),
            200000e8, // total collateral value in USD
            0, // total debt value in USD
            160000e8, // available borrows in USD 
            8250, // LLTV
            8000, // LTV
            type(uint256).max // health factor as no borrows have been made
        );

        // Log
        console2.log("Successfully supplied 1 WETH to the protocol!");
        console2.log("Price at $2000 USD");
        console2.log("------------------------------------------------------------");

        vm.stopBroadcast();

        uint256 balance = debtManager.getCollateralBalanceOfUser(userAddress, address(weth));
        console2.log("User collateral balance from DebtManager: %s WETH", balance / 1e18);
    }
}