// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol"; // Interface for the LiiBorrow Debt Manager
import {HelperConfig} from "./HelperConfig.s.sol";

contract BorrowFromLiidia is Script {
    IDebtManager debtManager;
    HelperConfig helperConfig;

    uint256 private USER = vm.envUint("PRIVATE_KEY_USER");
    uint256 constant BORROW_AMOUNT = 1200e6;

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        // Create contract instance
        debtManager = IDebtManager(helperConfig.debtManagerAddress());

        // Log health factor before borrow
        uint256 hfBefore = debtManager.getHealthFactor(vm.addr(USER));
        (uint256 aaveDebtBefore, ) = debtManager.getUserDebt(vm.addr(USER));
        uint256 balance = debtManager.getCollateralBalanceOfUser(vm.addr(USER), address(helperConfig.WETH()));
        console2.log("User collateral balance from DebtManager: %s WETH", balance / 1e18);
        console2.log("User Health Factor before borrow: %s", hfBefore);
        console2.log("User Debt before borrow: %s USDC", aaveDebtBefore / 1e6);
        console2.log("------------------------------------------------------------");

        vm.startBroadcast(USER);

        // Borrow USDC
        debtManager.borrowUsdc(BORROW_AMOUNT);
        // Log
        console2.log("Successfully borrowed 1200 USDC from the protocol!");

        vm.stopBroadcast();

        // Log health factor after borrow
        uint256 hfAfter = debtManager.getHealthFactor(vm.addr(USER));
        (uint256 aaveDebtAfter, ) = debtManager.getUserDebt(vm.addr(USER));
        bool isLiquid = debtManager.isLiquidatable(vm.addr(USER));
        console2.log("------------------------------------------------------------");
        console2.log("User Debt after borrow: %s USDC", aaveDebtAfter / 1e6);
        console2.log("User Health Factor after borrow: %s", hfAfter);
        console2.log("User is liquidatable after borrow: %s", isLiquid);
        
    }
}
