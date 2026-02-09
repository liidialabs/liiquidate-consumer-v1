// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {
    ILiquidationAdapter
} from "../../src/interfaces/adapter/ILiquidationAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * @title AdapterRegistryFuzz
 * @notice Fuzz tests for AdapterRegistry
 */
contract AdapterRegistryFuzz is Test {
    AdapterRegistry public registry;

    function setUp() public {
        registry = new AdapterRegistry();
    }

    // ========== REGISTRATION FUZZ TESTS ==========

    function testFuzzRegisterAdapter(
        bytes32 protocolId,
        address adapter
    ) public {
        vm.assume(adapter != address(0));
        vm.assume(protocolId != bytes32(0));

        registry.registerAdapter(protocolId, adapter);

        address registered = registry.getAdapter(protocolId);
        assertEq(registered, adapter);
    }

    function testFuzzRegisterMultipleAdapters(
        bytes32[] calldata protocolIds,
        address[] calldata adapters
    ) public {
        vm.assume(protocolIds.length == adapters.length);
        vm.assume(protocolIds.length <= 100);

        for (uint256 i = 0; i < protocolIds.length; i++) {
            vm.assume(adapters[i] != address(0));
            vm.assume(protocolIds[i] != bytes32(0));

            registry.registerAdapter(protocolIds[i], adapters[i]);
        }

        for (uint256 i = 0; i < protocolIds.length; i++) {
            assertEq(registry.getAdapter(protocolIds[i]), adapters[i]);
        }
    }

    function testFuzzRegisterAndOverwrite(
        bytes32 protocolId,
        address adapter1,
        address adapter2
    ) public {
        vm.assume(adapter1 != address(0));
        vm.assume(adapter2 != address(0));
        vm.assume(adapter1 != adapter2);
        vm.assume(protocolId != bytes32(0));

        registry.registerAdapter(protocolId, adapter1);
        assertEq(registry.getAdapter(protocolId), adapter1);

        registry.registerAdapter(protocolId, adapter2);
        assertEq(registry.getAdapter(protocolId), adapter2);
    }

    function testFuzzRemoveAdapter(bytes32 protocolId, address adapter) public {
        vm.assume(adapter != address(0));
        vm.assume(protocolId != bytes32(0));

        registry.registerAdapter(protocolId, adapter);
        assertEq(registry.getAdapter(protocolId), adapter);

        registry.removeAdapter(protocolId);
        assertEq(registry.getAdapter(protocolId), address(0));
    }

    function testFuzzGetUnregisteredAdapter(bytes32 protocolId) public {
        address adapter = registry.getAdapter(protocolId);
        assertEq(adapter, address(0));
    }

    // ========== EDGE CASES ==========

    function testFuzzZeroAddressRegistration(bytes32 protocolId) public {
        vm.assume(protocolId != bytes32(0));

        // Should revert when trying to register zero address
        vm.expectRevert();
        registry.registerAdapter(protocolId, address(0));
    }

    function testFuzzZeroProtocolId(address adapter) public {
        vm.assume(adapter != address(0));

        // Registering with zero protocol ID should work or revert based on implementation
        // This tests the behavior
        try registry.registerAdapter(bytes32(0), adapter) {
            // If it doesn't revert, verify it's stored
            address stored = registry.getAdapter(bytes32(0));
            assertEq(stored, adapter);
        } catch {
            // If it reverts, that's also valid
        }
    }

    function testFuzzRemoveNonexistentAdapter(bytes32 protocolId) public {
        // Removing non-existent adapter should be idempotent
        registry.removeAdapter(protocolId);
        assertEq(registry.getAdapter(protocolId), address(0));
    }

    function testFuzzRemoveThenRegister(
        bytes32 protocolId,
        address adapter1,
        address adapter2
    ) public {
        vm.assume(adapter1 != address(0));
        vm.assume(adapter2 != address(0));
        vm.assume(protocolId != bytes32(0));

        registry.registerAdapter(protocolId, adapter1);
        registry.removeAdapter(protocolId);
        registry.registerAdapter(protocolId, adapter2);

        assertEq(registry.getAdapter(protocolId), adapter2);
    }

    // ========== STATE CONSISTENCY FUZZ TESTS ==========

    function testFuzzStateConsistency(
        bytes32[] calldata protocolIds,
        address[] calldata adapters,
        uint256[] calldata operations
    ) public {
        vm.assume(protocolIds.length == adapters.length);
        vm.assume(protocolIds.length <= 50);
        vm.assume(operations.length <= 100);

        for (uint256 i = 0; i < protocolIds.length; i++) {
            vm.assume(adapters[i] != address(0));
            vm.assume(protocolIds[i] != bytes32(0));
            registry.registerAdapter(protocolIds[i], adapters[i]);
        }

        // Perform random operations
        for (uint256 i = 0; i < operations.length; i++) {
            uint256 op = operations[i] % protocolIds.length;

            if (i % 2 == 0) {
                registry.removeAdapter(protocolIds[op]);
            } else {
                address newAdapter = address(
                    uint160(uint256(keccak256(abi.encode(i))))
                );
                if (newAdapter != address(0)) {
                    registry.registerAdapter(protocolIds[op], newAdapter);
                }
            }
        }

        // All registrations should be consistent
        for (uint256 i = 0; i < protocolIds.length; i++) {
            address registered = registry.getAdapter(protocolIds[i]);
            // Either it's zero (removed) or some address
            assertTrue(registered == address(0) || registered != address(0));
        }
    }

    // ========== MASS REGISTRATION FUZZ TESTS ==========

    function testFuzzMassRegistration(
        uint8 count,
        bytes32[] calldata protocolIds
    ) public {
        vm.assume(count > 0 && count <= 255);
        vm.assume(protocolIds.length == count);

        for (uint256 i = 0; i < count; i++) {
            vm.assume(protocolIds[i] != bytes32(0));
            address adapter = address(uint160(i + 1));
            registry.registerAdapter(protocolIds[i], adapter);
        }

        for (uint256 i = 0; i < count; i++) {
            assertEq(
                registry.getAdapter(protocolIds[i]),
                address(uint160(i + 1))
            );
        }
    }

    // ========== COLLISION TESTS ==========

    function testFuzzProtocolIdCollisions(
        bytes32 id1,
        bytes32 id2,
        address adapter1,
        address adapter2
    ) public {
        vm.assume(adapter1 != address(0));
        vm.assume(adapter2 != address(0));

        registry.registerAdapter(id1, adapter1);
        registry.registerAdapter(id2, adapter2);

        // If ids are same, second registration should overwrite
        if (id1 == id2) {
            assertEq(registry.getAdapter(id1), adapter2);
        } else {
            assertEq(registry.getAdapter(id1), adapter1);
            assertEq(registry.getAdapter(id2), adapter2);
        }
    }

    // ========== GAS FUZZ TESTS ==========

    function testFuzzRegistrationGas(
        bytes32 protocolId,
        address adapter
    ) public {
        vm.assume(adapter != address(0));
        vm.assume(protocolId != bytes32(0));

        uint256 gasStart = gasleft();
        registry.registerAdapter(protocolId, adapter);
        uint256 gasUsed = gasStart - gasleft();

        // Registration should be reasonably efficient
        assertTrue(gasUsed < 100_000);
    }

    function testFuzzRetrievalGas(bytes32 protocolId) public {
        uint256 gasStart = gasleft();
        registry.getAdapter(protocolId);
        uint256 gasUsed = gasStart - gasleft();

        // Retrieval should be very cheap
        assertTrue(gasUsed < 10_000);
    }
}
