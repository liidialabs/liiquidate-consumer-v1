// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {
    ILiquidationAdapter
} from "../../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {MockDebtManagerAdapter} from "../mocks/MockDebtManagerAdapter.sol";
import {MockDebtManager} from "../mocks/MockDebtManager.sol";

/**
 * @title AdapterRegistryTest
 * @notice Comprehensive test suite for the AdapterRegistry contract
 */
contract AdapterRegistryTest is Test {
    AdapterRegistry public registry;
    MockDebtManager public debtManager_A;
    MockDebtManager public debtManager_B;
    MockDebtManagerAdapter public debtManagerAdapter;
    MockDebtManagerAdapter public anotherAdapter;

    address public owner;
    address public adapter;
    string public constant PROTOCOL_A = "PROTOCOL_A";
    string public constant PROTOCOL_B = "PROTOCOL_B";

    event AdapterRegistered(string protocol, address adapter);
    event AdapterRemoved(string protocol);

    function setUp() public {
        owner = address(this);

        registry = new AdapterRegistry();

        debtManager_A = new MockDebtManager();
        debtManagerAdapter = new MockDebtManagerAdapter(address(debtManager_A), PROTOCOL_A);

        debtManager_B = new MockDebtManager();
        anotherAdapter = new MockDebtManagerAdapter(address(debtManager_B), PROTOCOL_B);
    }

    // ========== REGISTRATION TESTS ==========

    function test_RegisterAdapter_Success() public {
        vm.expectEmit(true, true, false, false);
        emit AdapterRegistered(PROTOCOL_A, address(debtManagerAdapter));

        registry.registerAdapter(address(debtManagerAdapter));

        address stored = registry.getAdapter(PROTOCOL_A);
        assertEq(stored, address(debtManagerAdapter), "Adapter should be stored correctly");
    }

    function test_RegisterAdapter_MultipleAdapters() public {
        registry.registerAdapter(address(debtManagerAdapter));
        registry.registerAdapter(address(anotherAdapter));

        assertEq(registry.getAdapter(PROTOCOL_A), address(debtManagerAdapter));
        assertEq(registry.getAdapter(PROTOCOL_B), address(anotherAdapter));
    }

    function test_RegisterAdapter_RejectZeroAddress() public {
        vm.expectRevert(AdapterRegistry.InvalidAddress.selector);
        registry.registerAdapter(address(0));
    }

    // ========== REMOVAL TESTS ==========

    function test_RemoveAdapter_Success() public {
        registry.registerAdapter(address(debtManagerAdapter));

        vm.expectEmit(true, false, false, false);
        emit AdapterRemoved(PROTOCOL_A);

        registry.removeAdapter(PROTOCOL_A);

        address stored = registry.getAdapter(PROTOCOL_A);
        assertEq(stored, address(0), "Adapter should be removed");
    }

    function test_RemoveAdapter_NonExistent() public {
        // Should not revert even if adapter doesn't exist
        registry.removeAdapter(PROTOCOL_A);

        assertEq(registry.getAdapter(PROTOCOL_A), address(0));
    }

    function test_RemoveAdapter_PreservesOtherAdapters() public {
        registry.registerAdapter(address(debtManagerAdapter));
        registry.registerAdapter(address(anotherAdapter));

        registry.removeAdapter(PROTOCOL_A);

        assertEq(registry.getAdapter(PROTOCOL_A), address(0));
        assertEq(registry.getAdapter(PROTOCOL_B), address(anotherAdapter));
    }

    // ========== GET ADAPTER TESTS ==========

    function test_GetAdapter_ReturnsZeroForUnregistered() public view {
        address stored = registry.getAdapter(PROTOCOL_A);
        assertEq(stored, address(0));
    }

    function test_GetAdapter_ReturnsCorrectAdapter() public {
        registry.registerAdapter(address(debtManagerAdapter));
        address stored = registry.getAdapter(PROTOCOL_A);
        assertEq(stored, address(debtManagerAdapter));
    }


    // ========== AUTHORIZATION TESTS ==========

    function test_RegisterAdapter_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        registry.registerAdapter(address(debtManagerAdapter));
    }

    function test_RemoveAdapter_OnlyOwner() public {
        registry.registerAdapter(address(debtManagerAdapter));
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        registry.removeAdapter(PROTOCOL_A);
    }

    function test_Owner_CanModify() public {
        // Owner is set during construction
        registry.registerAdapter(address(debtManagerAdapter));
        assertEq(registry.getAdapter(PROTOCOL_A), address(debtManagerAdapter));

        registry.removeAdapter(PROTOCOL_A);
        assertEq(registry.getAdapter(PROTOCOL_A), address(0));
    }

    // ========== EVENT TESTS ==========

    function test_RegisterAdapter_EmitsCorrectEvent() public {
        vm.expectEmit(true, true, false, false);
        emit AdapterRegistered(PROTOCOL_A, address(debtManagerAdapter));

        registry.registerAdapter(address(debtManagerAdapter));
    }

    function test_RemoveAdapter_EmitsCorrectEvent() public {
        registry.registerAdapter(address(debtManagerAdapter));

        vm.expectEmit(true, false, false, false);
        emit AdapterRemoved(PROTOCOL_A);

        registry.removeAdapter(PROTOCOL_A);
    }


    // ========== STATE CONSISTENCY TESTS ==========

    function test_RegistryConsistency_MultipleOperations() public {
        // Register multiple
        registry.registerAdapter(address(debtManagerAdapter));
        registry.registerAdapter(address(anotherAdapter));

        // Verify state
        assertEq(registry.getAdapter(PROTOCOL_A), address(debtManagerAdapter));
        assertEq(registry.getAdapter(PROTOCOL_B), address(anotherAdapter));

        // Remove one
        registry.removeAdapter(PROTOCOL_A);

        // Final state check
        assertEq(registry.getAdapter(PROTOCOL_A), address(0));
        assertEq(registry.getAdapter(PROTOCOL_B), address(anotherAdapter));
    }
}
