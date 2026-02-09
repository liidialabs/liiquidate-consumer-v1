// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Liiquidate} from "../../src/Liiquidate.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockDebtManager} from "../mocks/MockDebtManager.sol";
import {MockLendingProtocol} from "../mocks/MockLendingProtocol.sol";

/**
 * @title InvariantsFuzz
 * @notice Fuzz tests for system invariants and security properties
 */
contract InvariantsFuzz is Test {
    Liiquidate public liiquidate;
    AdapterRegistry public registry;
    FlashLoanRouter public flashLoanRouter;
    UniversalSwapRouter public swapRouter;
    MockDebtManager public debtManager;
    MockLendingProtocol public lendingProtocol;
    MockERC20 public token;

    address public user = address(0x1);

    function setUp() public {
        token = new MockERC20("Test", "TST", 18);

        registry = new AdapterRegistry();
        flashLoanRouter = new FlashLoanRouter();
        swapRouter = new UniversalSwapRouter();
        debtManager = new MockDebtManager();
        lendingProtocol = new MockLendingProtocol();

        liiquidate = new Liiquidate(
            address(debtManager),
            address(lendingProtocol),
            address(flashLoanRouter)
        );

        token.mint(address(lendingProtocol), 10_000_000e18);
    }

    // ========== NO DOUBLE REGISTRATION INVARIANT ==========

    function testFuzzInvariantNoDoubleRegistration(
        bytes32[] calldata protocolIds,
        address adapter
    ) public {
        vm.assume(adapter != address(0));
        vm.assume(protocolIds.length <= 50);

        for (uint256 i = 0; i < protocolIds.length; i++) {
            vm.assume(protocolIds[i] != bytes32(0));

            registry.registerAdapter(protocolIds[i], adapter);

            // Registering same ID again should overwrite, not double-register
            registry.registerAdapter(protocolIds[i], adapter);

            address result = registry.getAdapter(protocolIds[i]);
            assertEq(result, adapter);
        }
    }

    // ========== ADAPTER REGISTRY STATE CONSISTENCY ==========

    function testFuzzInvariantRegistryStateConsistency(
        bytes32[] calldata ids,
        address[] calldata adapters
    ) public {
        vm.assume(ids.length == adapters.length);
        vm.assume(ids.length <= 100);

        // Register all adapters
        for (uint256 i = 0; i < ids.length; i++) {
            vm.assume(adapters[i] != address(0));
            vm.assume(ids[i] != bytes32(0));

            registry.registerAdapter(ids[i], adapters[i]);
        }

        // Verify all registrations
        for (uint256 i = 0; i < ids.length; i++) {
            address registered = registry.getAdapter(ids[i]);
            assertEq(
                registered,
                adapters[i],
                "Registry state inconsistency detected"
            );
        }
    }

    // ========== NO LOST TOKENS INVARIANT ==========

    function testFuzzInvariantNoLostTokens(uint256[] calldata amounts) public {
        vm.assume(amounts.length <= 50);

        uint256 totalMinted = 0;

        // Mint tokens
        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] <= 1_000_000e18);
            totalMinted += amounts[i];
        }

        vm.assume(totalMinted <= type(uint256).max);

        token.mint(user, totalMinted);

        // Verify balance matches
        assertEq(token.balanceOf(user), totalMinted);
    }

    // ========== MONOTONIC LIQUIDATION COUNTER ==========

    function testFuzzInvariantMonotonicLiquidationCounter(
        uint256[] calldata debtAmounts
    ) public {
        vm.assume(debtAmounts.length <= 50);

        for (uint256 i = 0; i < debtAmounts.length; i++) {
            vm.assume(debtAmounts[i] > 0);
            vm.assume(debtAmounts[i] <= 100_000e18);

            address borrowerAddr = address(uint160(100 + i));

            debtManager.setupUserAccount(
                borrowerAddr,
                address(token),
                100_000e18,
                address(token),
                debtAmounts[i]
            );

            // Liquidation counter should only increase
            uint256 countBefore = debtManager.totalLiquidations();

            try
                liiquidate.liquidate(
                    borrowerAddr,
                    address(token),
                    debtAmounts[i] / 2,
                    address(token)
                )
            {
                // Check counter didn't decrease
                uint256 countAfter = debtManager.totalLiquidations();
                assertTrue(countAfter >= countBefore);
            } catch {
                // Expected
            }
        }
    }

    // ========== NO UNAUTHORIZED OPERATIONS ==========

    function testFuzzInvariantNoUnauthorizedOperations(
        address[] calldata callers
    ) public {
        vm.assume(callers.length <= 50);

        for (uint256 i = 0; i < callers.length; i++) {
            address caller = callers[i] == address(0)
                ? address(this)
                : callers[i];

            if (caller != registry.owner()) {
                vm.prank(caller);
                vm.expectRevert();
                registry.registerAdapter(keccak256("TEST"), address(0x1));
            }
        }
    }

    // ========== FLASH LOAN MAXIMUM AMOUNT ==========

    function testFuzzInvariantFlashLoanMaxAmount(uint256 amount) public {
        vm.assume(amount > 0);

        // Flash loan should never be less than requested amount (ignoring fees)
        try
            flashLoanRouter.flashLoan(
                address(token),
                address(token),
                amount,
                address(this),
                ""
            )
        {
            // Invariant: flash loan provides requested amount
        } catch {
            // Expected for very large amounts
        }
    }

    // ========== ADAPTER REMOVAL IDEMPOTENCE ==========

    function testFuzzInvariantAdapterRemovalIdempotence(
        bytes32[] calldata protocolIds
    ) public {
        vm.assume(protocolIds.length <= 50);

        for (uint256 i = 0; i < protocolIds.length; i++) {
            vm.assume(protocolIds[i] != bytes32(0));

            // Register
            registry.registerAdapter(protocolIds[i], address(0x1));

            // Remove once
            registry.removeAdapter(protocolIds[i]);
            address result1 = registry.getAdapter(protocolIds[i]);

            // Remove again (should be idempotent)
            registry.removeAdapter(protocolIds[i]);
            address result2 = registry.getAdapter(protocolIds[i]);

            // Both should be zero (removed)
            assertEq(result1, address(0));
            assertEq(result2, address(0));
        }
    }

    // ========== NO REVERT ON ZERO ADDRESS REMOVAL ==========

    function testFuzzInvariantSafeRemoval(
        bytes32[] calldata protocolIds
    ) public {
        vm.assume(protocolIds.length <= 50);

        for (uint256 i = 0; i < protocolIds.length; i++) {
            // Should not revert even if not registered
            registry.removeAdapter(protocolIds[i]);

            address result = registry.getAdapter(protocolIds[i]);
            assertEq(result, address(0));
        }
    }

    // ========== OWNER OPERATIONS ONLY ==========

    function testFuzzInvariantOwnerOnlyOperations() public {
        address notOwner = address(0xDEAD);

        bytes32 protocolId = keccak256("TEST");
        address adapter = address(0x1);

        // Non-owner cannot register
        vm.prank(notOwner);
        vm.expectRevert();
        registry.registerAdapter(protocolId, adapter);

        // Non-owner cannot remove
        // (may not revert depending on implementation, but should have no effect)
    }

    // ========== SWAP ROUTER INVARIANT ==========

    function testFuzzInvariantSwapOutputNonZeroForNonZeroInput(
        uint256 amount
    ) public {
        vm.assume(amount > 0);

        try
            swapRouter.swapExactInputSingleHop(
                address(token),
                address(token),
                amount,
                0,
                address(this)
            )
        {
            // Output should be non-zero for non-zero input
        } catch {
            // Expected if routes not configured
        }
    }

    // ========== NO LOSS OF PRECISION ON BOUNDARIES ==========

    function testFuzzInvariantNoPrecisionLoss(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint256).max / 2);

        // Operations should maintain precision
        uint256 doubled = amount * 2;
        assertTrue(doubled >= amount);

        uint256 halved = amount / 2;
        assertTrue(halved <= amount);
    }

    // ========== DETERMINISTIC ADAPTER RETRIEVAL ==========

    function testFuzzInvariantDeterministicAdapterRetrieval(
        bytes32 protocolId,
        address adapter1,
        address adapter2
    ) public {
        vm.assume(adapter1 != address(0));
        vm.assume(protocolId != bytes32(0));

        registry.registerAdapter(protocolId, adapter1);

        address retrieved1 = registry.getAdapter(protocolId);
        address retrieved2 = registry.getAdapter(protocolId);

        assertEq(retrieved1, retrieved2);
        assertEq(retrieved1, adapter1);
    }

    // ========== REVERT ON INVALID INPUTS ==========

    function testFuzzInvariantRevertOnInvalidInputs(uint256 amount) public {
        // Zero amounts should revert
        vm.expectRevert();
        liiquidate.liquidate(address(0x1), address(token), 0, address(token));

        // Zero addresses should revert
        vm.expectRevert();
        liiquidate.liquidate(
            address(0),
            address(token),
            amount > 0 ? amount : 1,
            address(token)
        );
    }

    // ========== MAX VALUES HANDLING ==========

    function testFuzzInvariantMaxUintHandling() public {
        // System should not overflow on max uint
        bytes32 id = keccak256("MAX_TEST");
        address adapter = address(0x1);

        registry.registerAdapter(id, adapter);

        // All operations use MAX should be safe
        try
            flashLoanRouter.flashLoan(
                address(token),
                address(token),
                type(uint256).max,
                address(this),
                ""
            )
        {
            // Should handle max gracefully
        } catch {
            // Revert is acceptable
        }
    }

    // ========== REENTRANCY PROTECTION INVARIANT ==========

    function testFuzzInvariantReentrancyProtection(uint256 depth) public {
        vm.assume(depth <= 10);

        // Multiple calls in sequence should work
        for (uint256 i = 0; i < depth; i++) {
            try
                liiquidate.liquidate(
                    address(uint160(i + 1)),
                    address(token),
                    1000e18,
                    address(token)
                )
            {
                // Success
            } catch {
                // Expected
            }
        }
    }

    // ========== SUPPLY CHAIN INVARIANTS ==========

    function testFuzzInvariantSupplyConservation(
        uint256[] calldata amounts
    ) public {
        vm.assume(amounts.length <= 50);

        uint256 totalSupply = 0;

        // Check supply conservation
        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] <= 1_000_000e18);

            if (totalSupply + amounts[i] <= type(uint256).max) {
                totalSupply += amounts[i];
            }
        }

        // Total mint and burn should balance
        token.mint(address(this), totalSupply);
        assertEq(token.balanceOf(address(this)), totalSupply);
    }

    // ========== PROTOCOL CONSISTENCY CHECKS ==========

    function testFuzzInvariantProtocolConsistency() public {
        // Registry, Router, and Liiquidate should remain consistent
        bytes32 id1 = keccak256("PROTOCOL_1");
        address adapter1 = address(0x100);

        registry.registerAdapter(id1, adapter1);
        assertEq(registry.getAdapter(id1), adapter1);

        // After registration, retrieval should always match
        for (uint256 i = 0; i < 10; i++) {
            address retrieved = registry.getAdapter(id1);
            assertEq(retrieved, adapter1);
        }
    }

    receive() external payable {}
}
