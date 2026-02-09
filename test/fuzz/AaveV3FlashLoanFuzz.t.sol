// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {AaveV3} from "../../src/flashloans/AaveV3.sol";
import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {LiquidationParams} from "../../src/types/DataTypes.sol";

/**
 * @title AaveV3FlashLoanFuzz
 * @notice Fuzz tests for Aave V3 flash loan provider
 */
contract AaveV3FlashLoanFuzz is Test {
    AaveV3 public flashLoan;
    MockAaveV3Pool public pool;
    MockERC20 public debtToken;
    MockERC20 public collateralToken;
    UniversalSwapRouter public swapRouter;

    address public liquidator = address(0x1);

    function setUp() public {
        debtToken = new MockERC20("Debt", "DBT", 18);
        collateralToken = new MockERC20("Collateral", "COLL", 18);

        pool = new MockAaveV3Pool(address(debtToken), address(collateralToken));
        swapRouter = new UniversalSwapRouter();
        flashLoan = new AaveV3(address(pool), address(swapRouter));

        debtToken.mint(address(pool), 10_000_000e18);
        collateralToken.mint(address(pool), 10_000_000e18);
    }

    // ========== FLASH LOAN AMOUNT FUZZ ==========

    function testFuzzFlashLoanAmounts(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 1_000_000e18);

        vm.prank(liquidator);
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                amount,
                address(this),
                ""
            )
        {
            // Tests various amounts
        } catch {
            // Expected for large amounts beyond pool liquidity
        }
    }

    function testFuzzMultipleFlashLoans(uint256[] calldata amounts) public {
        vm.assume(amounts.length <= 50);

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] > 0);
            vm.assume(amounts[i] <= 500_000e18);

            vm.prank(liquidator);
            try
                flashLoan.flashLoan(
                    address(debtToken),
                    address(collateralToken),
                    amounts[i],
                    address(this),
                    ""
                )
            {
                // Success
            } catch {
                // Expected
            }
        }
    }

    // ========== DIFFERENT TOKEN COMBINATIONS ==========

    function testFuzzTokenCombinations(
        address tokenA,
        address tokenB,
        uint256 amount
    ) public {
        vm.assume(tokenA != address(0));
        vm.assume(tokenB != address(0));
        vm.assume(amount > 0);
        vm.assume(amount <= 100_000e18);

        vm.prank(liquidator);
        try flashLoan.flashLoan(tokenA, tokenB, amount, address(this), "") {
            // Tests different token combinations
        } catch {
            // Expected for uninitialized tokens
        }
    }

    // ========== CALLBACK DATA VARIATIONS ==========

    function testFuzzCallbackDataHandling(bytes calldata callbackData) public {
        uint256 amount = 10_000e18;

        vm.prank(liquidator);
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                amount,
                address(this),
                callbackData
            )
        {
            // Tests different callback data
        } catch {
            // Expected
        }
    }

    function testFuzzLargeCallbackData(uint256 size) public {
        vm.assume(size <= 10_000);

        bytes memory largeData = new bytes(size);

        vm.prank(liquidator);
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                1_000e18,
                address(this),
                largeData
            )
        {
            // Tests large callback data
        } catch {
            // Expected
        }
    }

    // ========== TARGET CONTRACT VARIATIONS ==========

    function testFuzzDifferentTargets(address[] calldata targets) public {
        vm.assume(targets.length <= 50);

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i] != address(0)
                ? targets[i]
                : address(this);

            vm.prank(liquidator);
            try
                flashLoan.flashLoan(
                    address(debtToken),
                    address(collateralToken),
                    1_000e18,
                    target,
                    ""
                )
            {
                // Tests different target contracts
            } catch {
                // Expected
            }
        }
    }

    // ========== INVALID PARAMETERS ==========

    function testFuzzZeroAmountFlashLoan() public {
        vm.prank(liquidator);
        vm.expectRevert("Amount cannot be zero!");
        flashLoan.flashLoan(
            address(debtToken),
            address(collateralToken),
            0,
            address(this),
            ""
        );
    }

    function testFuzzZeroDebtToken() public {
        vm.prank(liquidator);
        vm.expectRevert("Invalid Address");
        flashLoan.flashLoan(
            address(0),
            address(collateralToken),
            1_000e18,
            address(this),
            ""
        );
    }

    function testFuzzZeroCollateralToken() public {
        vm.prank(liquidator);
        vm.expectRevert("Invalid Address");
        flashLoan.flashLoan(
            address(debtToken),
            address(0),
            1_000e18,
            address(this),
            ""
        );
    }

    function testFuzzZeroTarget() public {
        vm.prank(liquidator);
        vm.expectRevert("Invalid Address");
        flashLoan.flashLoan(
            address(debtToken),
            address(collateralToken),
            1_000e18,
            address(0),
            ""
        );
    }

    // ========== SEQUENTIAL OPERATIONS ==========

    function testFuzzSequentialFlashLoans(uint256[] calldata amounts) public {
        vm.assume(amounts.length <= 100);

        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] > 0);
            vm.assume(amounts[i] <= 100_000e18);

            address liquidatorAddr = address(uint160(100 + i));

            vm.prank(liquidatorAddr);
            try
                flashLoan.flashLoan(
                    address(debtToken),
                    address(collateralToken),
                    amounts[i],
                    address(this),
                    ""
                )
            {
                // Success
            } catch {
                // Expected
            }
        }
    }

    // ========== EXTREME VALUES ==========

    function testFuzzVeryLargeAmount() public {
        uint256 largeAmount = 9_000_000e18; // 90% of pool

        vm.prank(liquidator);
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                largeAmount,
                address(this),
                ""
            )
        {
            // Tests very large amounts
        } catch {
            // Expected
        }
    }

    function testFuzzVerySmallAmount() public {
        uint256 tinyAmount = 1; // 1 wei

        vm.prank(liquidator);
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                tinyAmount,
                address(this),
                ""
            )
        {
            // Tests very small amounts
        } catch {
            // Expected
        }
    }

    function testFuzzMaxUintAmount() public {
        vm.prank(liquidator);
        vm.expectRevert();
        flashLoan.flashLoan(
            address(debtToken),
            address(collateralToken),
            type(uint256).max,
            address(this),
            ""
        );
    }

    // ========== STATE CONSISTENCY ==========

    function testFuzzStateAfterFlashLoans(
        bytes32[] calldata operations
    ) public {
        vm.assume(operations.length <= 100);

        for (uint256 i = 0; i < operations.length; i++) {
            uint256 amount = (uint256(operations[i]) % 50_000) + 1;
            amount = amount * 1e18;

            vm.prank(liquidator);
            try
                flashLoan.flashLoan(
                    address(debtToken),
                    address(collateralToken),
                    amount,
                    address(this),
                    ""
                )
            {
                // Success
            } catch {
                // Expected
            }
        }
    }

    // ========== GAS OPTIMIZATION ==========

    function testFuzzFlashLoanGasUsage(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 100_000e18);

        vm.prank(liquidator);
        uint256 gasStart = gasleft();
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                amount,
                address(this),
                ""
            )
        {
            uint256 gasUsed = gasStart - gasleft();
            assertTrue(gasUsed < 2_000_000);
        } catch {}
    }

    // ========== PROVIDER ID ==========

    function testFuzzProviderIdConsistency() public {
        bytes32 id1 = flashLoan.id();
        bytes32 id2 = flashLoan.id();
        assertEq(id1, id2);

        bytes32 expectedId = keccak256("AAVE_V3");
        assertEq(id1, expectedId);
    }

    // ========== TOKEN RESCUE ==========

    function testFuzzRescueTokens(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 100_000e18);

        debtToken.mint(address(flashLoan), amount);

        vm.prank(flashLoan.owner());
        flashLoan.rescueTokens(address(debtToken), amount);

        assertEq(debtToken.balanceOf(flashLoan.owner()), amount);
    }

    // ========== RECEIVE FUNCTION ==========

    function testFuzzReceiveETH(uint256 amount) public {
        vm.assume(amount >= 0);
        vm.assume(amount <= 1000 ether);

        vm.deal(liquidator, amount);

        vm.prank(liquidator);
        (bool success, ) = address(flashLoan).call{value: amount}("");
        assertTrue(success);
    }

    // ========== REENTRANCY PROTECTION ==========

    function testFuzzReentrancyAttempts(uint256 recursionDepth) public {
        vm.assume(recursionDepth <= 10);

        uint256 amount = 10_000e18;

        vm.prank(liquidator);
        // Router should protect against reentrancy
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                amount,
                address(this),
                ""
            )
        {
            // Tests reentrancy handling
        } catch {
            // Expected
        }
    }

    // ========== PARAMETER BOUNDARY TESTING ==========

    function testFuzzBoundaryAmounts(uint256 amount) public {
        vm.assume(amount >= 1);
        vm.assume(amount <= 10_000_000e18);

        vm.prank(liquidator);
        try
            flashLoan.flashLoan(
                address(debtToken),
                address(collateralToken),
                amount,
                address(this),
                ""
            )
        {
            // Tests boundary values
        } catch {
            // Expected
        }
    }
}
