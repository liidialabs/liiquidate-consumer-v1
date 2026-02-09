// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {
    ILiquidationAdapter
} from "../../src/interfaces/adapter/ILiquidationAdapter.sol";

/**
 * @title AdapterRegistryTest
 * @notice Comprehensive test suite for the AdapterRegistry contract
 */
contract AdapterRegistryTest is Test {
    AdapterRegistry public registry;
    address public owner;
    address public adapter;
    address public anotherAdapter;
    bytes32 public constant PROTOCOL_ID = keccak256("PROTOCOL_A");
    bytes32 public constant PROTOCOL_B = keccak256("PROTOCOL_B");

    event AdapterRegistered(bytes32 protocol, address adapter);
    event AdapterRemoved(bytes32 protocol);

    function setUp() public {
        owner = address(this);
        adapter = makeAddr("adapter");
        anotherAdapter = makeAddr("anotherAdapter");

        registry = new AdapterRegistry();
    }

    // ========== REGISTRATION TESTS ==========

    function test_RegisterAdapter_Success() public {
        vm.expectEmit(true, true, false, false);
        emit AdapterRegistered(PROTOCOL_ID, adapter);

        registry.registerAdapter(PROTOCOL_ID, adapter);

        address stored = registry.getAdapter(PROTOCOL_ID);
        assertEq(stored, adapter, "Adapter should be stored correctly");
    }

    function test_RegisterAdapter_MultipleAdapters() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        registry.registerAdapter(PROTOCOL_B, anotherAdapter);

        assertEq(registry.getAdapter(PROTOCOL_ID), adapter);
        assertEq(registry.getAdapter(PROTOCOL_B), anotherAdapter);
    }

    function test_RegisterAdapter_OverwriteExisting() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        address newAdapter = makeAddr("newAdapter");

        registry.registerAdapter(PROTOCOL_ID, newAdapter);

        assertEq(registry.getAdapter(PROTOCOL_ID), newAdapter);
    }

    function test_RegisterAdapter_RejectZeroAddress() public {
        vm.expectRevert(bytes("invalid adapter"));
        registry.registerAdapter(PROTOCOL_ID, address(0));
    }

    function test_RegisterAdapter_WithMultipleProtocols() public {
        bytes32[] memory protocols = new bytes32[](3);
        address[] memory adapters = new address[](3);

        for (uint256 i = 0; i < 3; i++) {
            protocols[i] = keccak256(abi.encodePacked("PROTOCOL_", i));
            adapters[i] = makeAddr(string(abi.encodePacked("adapter_", i)));
        }

        for (uint256 i = 0; i < 3; i++) {
            registry.registerAdapter(protocols[i], adapters[i]);
        }

        for (uint256 i = 0; i < 3; i++) {
            assertEq(registry.getAdapter(protocols[i]), adapters[i]);
        }
    }

    // ========== REMOVAL TESTS ==========

    function test_RemoveAdapter_Success() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);

        vm.expectEmit(true, false, false, false);
        emit AdapterRemoved(PROTOCOL_ID);

        registry.removeAdapter(PROTOCOL_ID);

        address stored = registry.getAdapter(PROTOCOL_ID);
        assertEq(stored, address(0), "Adapter should be removed");
    }

    function test_RemoveAdapter_NonExistent() public {
        // Should not revert even if adapter doesn't exist
        registry.removeAdapter(PROTOCOL_ID);

        assertEq(registry.getAdapter(PROTOCOL_ID), address(0));
    }

    function test_RemoveAdapter_PreservesOtherAdapters() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        registry.registerAdapter(PROTOCOL_B, anotherAdapter);

        registry.removeAdapter(PROTOCOL_ID);

        assertEq(registry.getAdapter(PROTOCOL_ID), address(0));
        assertEq(registry.getAdapter(PROTOCOL_B), anotherAdapter);
    }

    function test_RemoveAdapter_AllowsReRegistration() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        registry.removeAdapter(PROTOCOL_ID);

        address newAdapter = makeAddr("newAdapter");
        registry.registerAdapter(PROTOCOL_ID, newAdapter);

        assertEq(registry.getAdapter(PROTOCOL_ID), newAdapter);
    }

    // ========== GET ADAPTER TESTS ==========

    function test_GetAdapter_ReturnsZeroForUnregistered() public {
        address stored = registry.getAdapter(PROTOCOL_ID);
        assertEq(stored, address(0));
    }

    function test_GetAdapter_ReturnsCorrectAdapter() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        address stored = registry.getAdapter(PROTOCOL_ID);
        assertEq(stored, adapter);
    }

    function test_GetAdapter_WithDifferentProtocolIds() public {
        bytes32[] memory protocolIds = new bytes32[](5);
        address[] memory adapterAddrs = new address[](5);

        for (uint256 i = 0; i < 5; i++) {
            protocolIds[i] = keccak256(abi.encodePacked("PROTOCOL_", i));
            adapterAddrs[i] = makeAddr(string(abi.encodePacked("adapter_", i)));
            registry.registerAdapter(protocolIds[i], adapterAddrs[i]);
        }

        for (uint256 i = 0; i < 5; i++) {
            assertEq(registry.getAdapter(protocolIds[i]), adapterAddrs[i]);
        }
    }

    // ========== AUTHORIZATION TESTS ==========

    function test_RegisterAdapter_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        registry.registerAdapter(PROTOCOL_ID, adapter);
    }

    function test_RemoveAdapter_OnlyOwner() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        registry.removeAdapter(PROTOCOL_ID);
    }

    function test_Owner_CanModify() public {
        // Owner is set during construction
        registry.registerAdapter(PROTOCOL_ID, adapter);
        assertEq(registry.getAdapter(PROTOCOL_ID), adapter);

        registry.removeAdapter(PROTOCOL_ID);
        assertEq(registry.getAdapter(PROTOCOL_ID), address(0));
    }

    // ========== EDGE CASE TESTS ==========

    function test_RegisterAdapter_SameAdapterMultipleProtocols() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);
        registry.registerAdapter(PROTOCOL_B, adapter);

        assertEq(registry.getAdapter(PROTOCOL_ID), adapter);
        assertEq(registry.getAdapter(PROTOCOL_B), adapter);
    }

    function test_RegisterAdapter_WithSpecialCharactersInProtocolId() public {
        bytes32 specialId = keccak256(abi.encodePacked("@#$%^&*()"));
        registry.registerAdapter(specialId, adapter);

        assertEq(registry.getAdapter(specialId), adapter);
    }

    function test_RegisterAdapter_LargeNumberOfAdapters() public {
        uint256 count = 100;
        bytes32[] memory protocols = new bytes32[](count);
        address[] memory adapterList = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            protocols[i] = keccak256(abi.encodePacked("PROTOCOL_", i));
            adapterList[i] = makeAddr(string(abi.encodePacked("adapter_", i)));
            registry.registerAdapter(protocols[i], adapterList[i]);
        }

        // Verify all are stored correctly
        for (uint256 i = 0; i < count; i++) {
            assertEq(registry.getAdapter(protocols[i]), adapterList[i]);
        }
    }

    function test_RemoveAdapter_BulkRemoval() public {
        uint256 count = 10;
        bytes32[] memory protocols = new bytes32[](count);

        for (uint256 i = 0; i < count; i++) {
            protocols[i] = keccak256(abi.encodePacked("PROTOCOL_", i));
            address adapterAddr = makeAddr(
                string(abi.encodePacked("adapter_", i))
            );
            registry.registerAdapter(protocols[i], adapterAddr);
        }

        for (uint256 i = 0; i < count; i++) {
            registry.removeAdapter(protocols[i]);
        }

        // Verify all are removed
        for (uint256 i = 0; i < count; i++) {
            assertEq(registry.getAdapter(protocols[i]), address(0));
        }
    }

    // ========== EVENT TESTS ==========

    function test_RegisterAdapter_EmitsCorrectEvent() public {
        vm.expectEmit(true, true, false, false);
        emit AdapterRegistered(PROTOCOL_ID, adapter);

        registry.registerAdapter(PROTOCOL_ID, adapter);
    }

    function test_RemoveAdapter_EmitsCorrectEvent() public {
        registry.registerAdapter(PROTOCOL_ID, adapter);

        vm.expectEmit(true, false, false, false);
        emit AdapterRemoved(PROTOCOL_ID);

        registry.removeAdapter(PROTOCOL_ID);
    }

    function test_MultipleRegistrations_EachEmitsEvent() public {
        bytes32[] memory protocols = new bytes32[](3);
        address[] memory adapterList = new address[](3);

        for (uint256 i = 0; i < 3; i++) {
            protocols[i] = keccak256(abi.encodePacked("PROTOCOL_", i));
            adapterList[i] = makeAddr(string(abi.encodePacked("adapter_", i)));
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.expectEmit(true, true, false, false);
            emit AdapterRegistered(protocols[i], adapterList[i]);
            registry.registerAdapter(protocols[i], adapterList[i]);
        }
    }

    // ========== STATE CONSISTENCY TESTS ==========

    function test_RegistryConsistency_RegisterRemoveRe_Register() public {
        // Register
        registry.registerAdapter(PROTOCOL_ID, adapter);
        assertEq(registry.getAdapter(PROTOCOL_ID), adapter);

        // Remove
        registry.removeAdapter(PROTOCOL_ID);
        assertEq(registry.getAdapter(PROTOCOL_ID), address(0));

        // Re-register with different adapter
        address newAdapter = makeAddr("newAdapter");
        registry.registerAdapter(PROTOCOL_ID, newAdapter);
        assertEq(registry.getAdapter(PROTOCOL_ID), newAdapter);
    }

    function test_RegistryConsistency_MultipleOperations() public {
        // Register multiple
        registry.registerAdapter(PROTOCOL_ID, adapter);
        registry.registerAdapter(PROTOCOL_B, anotherAdapter);

        // Update one
        address updatedAdapter = makeAddr("updatedAdapter");
        registry.registerAdapter(PROTOCOL_ID, updatedAdapter);

        // Verify state
        assertEq(registry.getAdapter(PROTOCOL_ID), updatedAdapter);
        assertEq(registry.getAdapter(PROTOCOL_B), anotherAdapter);

        // Remove one
        registry.removeAdapter(PROTOCOL_ID);

        // Final state check
        assertEq(registry.getAdapter(PROTOCOL_ID), address(0));
        assertEq(registry.getAdapter(PROTOCOL_B), anotherAdapter);
    }
}
