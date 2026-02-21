// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol"; // Interface for the LiiBorrow Debt Manager
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract SupplyToLiidia is Script {
    IDebtManager debtManager;
    MockERC20 weth;

    address private DebtManagerAddress = address(1); // Replace with actual DebtManager address
    address private WETHAddress = address(1); // Replace with actual WETH address
    uint256 private USER = vm.envUint("USERS_PRIVATE_KEY");

    uint256 constant INITIAL_BALANCE = 10e18;
    uint256 constant SUPPLY_AMOUNT = 1e18;

    function run() public {

        vm.startBroadcast(USER);

        // get user wallet address
        address userAddress = vm.addr(USER);
        // mint WETH to user wallet for testing
        weth = MockERC20(WETHAddress);
        weth.mint(userAddress, SUPPLY_AMOUNT);

        // Create contract instance
        debtManager = IDebtManager(DebtManagerAddress);
        // Approve DebtManager to spend user's WETH
        weth.approve(DebtManagerAddress, INITIAL_BALANCE);
        // Supply to LiiBorrow
        debtManager.depositCollateralERC20(WETHAddress, SUPPLY_AMOUNT);

        // Log
        console2.log("Successfully supplied 1 WETH to the protocol!");
        console2.log("Price at $2000 USD");

        vm.stopBroadcast();
    }
}