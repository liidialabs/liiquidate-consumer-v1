// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol"; // Interface for the LiiBorrow Debt Manager

contract BorrowFromLiidia is Script {
    IDebtManager debtManager;

    address private DebtManagerAddress = address(1); // Replace with actual DebtManager address
    uint256 private USER = vm.envUint("USERS_PRIVATE_KEY");
    uint256 constant BORROW_AMOUNT = 1000e6; // Replace with price that we can simulate

    function run() public {

        vm.startBroadcast(USER);

        // Create contract instance
        debtManager = IDebtManager(DebtManagerAddress);
        // Borrow USDC
        debtManager.borrowUsdc(BORROW_AMOUNT);
        // Log
        console2.log("Successfully borrowed 1000 USDC from the protocol!");

        vm.stopBroadcast();

    }
}