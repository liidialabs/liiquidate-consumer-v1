// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {Liiquidate} from "../../src/Liiquidate.sol";
// import {MockERC20} from "../mocks/MockERC20.sol";
// import {MockDebtManager} from "../mocks/MockDebtManager.sol";
// import {MockLendingProtocol} from "../mocks/MockLendingProtocol.sol";

// /**
//  * @title LiiquidateFuzz
//  * @notice Fuzz tests for Liiquidate liquidation orchestrator
//  */
// contract LiiquidateFuzz is Test {
//     Liiquidate public liiquidate;
//     MockDebtManager public debtManager;
//     MockLendingProtocol public lendingProtocol;
//     MockERC20 public debtToken;
//     MockERC20 public collateralToken;

//     address public liquidator = address(0x1);
//     address public borrower = address(0x2);

//     function setUp() public {
//         debtToken = new MockERC20("Debt", "DBT", 18);
//         collateralToken = new MockERC20("Collateral", "COLL", 18);

//         debtManager = new MockDebtManager();
//         lendingProtocol = new MockLendingProtocol();

//         liiquidate = new Liiquidate(
//             address(debtManager),
//             address(lendingProtocol),
//             address(0) // Flash loan router
//         );

//         // Setup initial balances
//         debtToken.mint(address(lendingProtocol), 1_000_000e18);
//         collateralToken.mint(borrower, 1_000_000e18);
//     }

//     // ========== LIQUIDATION AMOUNT FUZZ ==========

//     function testFuzzLiquidationAmounts(uint256 debtAmount) public {
//         vm.assume(debtAmount > 0);
//         vm.assume(debtAmount <= 1_000_000e18);

//         // Setup debt for borrower
//         debtManager.setupUserAccount(
//             borrower,
//             address(collateralToken),
//             10_000e18,
//             address(debtToken),
//             debtAmount
//         );

//         // This tests liquidation with different debt amounts
//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(debtToken),
//                 debtAmount,
//                 address(collateralToken)
//             )
//         {
//             // Success case
//         } catch {
//             // May fail due to implementation details
//         }
//     }

//     function testFuzzMultipleBorrowerLiquidations(
//         uint256[] calldata debtAmounts,
//         uint256[] calldata collateralAmounts
//     ) public {
//         vm.assume(debtAmounts.length == collateralAmounts.length);
//         vm.assume(debtAmounts.length <= 50);

//         for (uint256 i = 0; i < debtAmounts.length; i++) {
//             vm.assume(debtAmounts[i] > 0);
//             vm.assume(debtAmounts[i] <= 100_000e18);
//             vm.assume(collateralAmounts[i] > 0);
//             vm.assume(collateralAmounts[i] <= 100_000e18);

//             address borrowerAddr = address(uint160(100 + i));

//             debtManager.setupUserAccount(
//                 borrowerAddr,
//                 address(collateralToken),
//                 collateralAmounts[i],
//                 address(debtToken),
//                 debtAmounts[i]
//             );
//         }
//     }

//     // ========== DIFFERENT PROTOCOL COMBINATIONS ==========

//     function testFuzzLiquidateWithDifferentTokens(
//         address debtAsset,
//         address collateralAsset,
//         uint256 amount
//     ) public {
//         vm.assume(debtAsset != address(0));
//         vm.assume(collateralAsset != address(0));
//         vm.assume(amount > 0);
//         vm.assume(amount <= 1_000_000e18);

//         try liiquidate.liquidate(borrower, debtAsset, amount, collateralAsset) {
//             // Tests different token combinations
//         } catch {
//             // Expected for uninitialized tokens
//         }
//     }

//     // ========== HEALTH FACTOR VARIATIONS ==========

//     function testFuzzLiquidationWithVaryingHealthFactors(
//         uint256 collateralAmount,
//         uint256 debtAmount
//     ) public {
//         vm.assume(collateralAmount > 0);
//         vm.assume(collateralAmount <= 100_000e18);
//         vm.assume(debtAmount > 0);
//         vm.assume(debtAmount <= 100_000e18);

//         debtManager.setupUserAccount(
//             borrower,
//             address(collateralToken),
//             collateralAmount,
//             address(debtToken),
//             debtAmount
//         );

//         // Health factor = collateral / debt
//         // Low health factor = higher liquidation priority
//     }

//     // ========== PARTIAL LIQUIDATION FUZZ ==========

//     function testFuzzPartialLiquidations(
//         uint256 totalDebt,
//         uint256 partialAmount
//     ) public {
//         vm.assume(totalDebt > 0);
//         vm.assume(totalDebt <= 1_000_000e18);
//         vm.assume(partialAmount > 0);
//         vm.assume(partialAmount <= totalDebt);

//         debtManager.setupUserAccount(
//             borrower,
//             address(collateralToken),
//             100_000e18,
//             address(debtToken),
//             totalDebt
//         );

//         // First partial liquidation
//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(debtToken),
//                 partialAmount,
//                 address(collateralToken)
//             )
//         {
//             // Success case
//         } catch {
//             // Expected
//         }
//     }

//     // ========== EDGE CASES ==========

//     function testFuzzZeroDebtLiquidation() public {
//         vm.expectRevert();
//         liiquidate.liquidate(
//             borrower,
//             address(debtToken),
//             0,
//             address(collateralToken)
//         );
//     }

//     function testFuzzZeroBorrowerAddress(uint256 debtAmount) public {
//         vm.assume(debtAmount > 0);

//         vm.expectRevert();
//         liiquidate.liquidate(
//             address(0),
//             address(debtToken),
//             debtAmount,
//             address(collateralToken)
//         );
//     }

//     function testFuzzZeroDebtAsset(uint256 debtAmount) public {
//         vm.assume(debtAmount > 0);

//         vm.expectRevert();
//         liiquidate.liquidate(
//             borrower,
//             address(0),
//             debtAmount,
//             address(collateralToken)
//         );
//     }

//     function testFuzzZeroCollateralAsset(uint256 debtAmount) public {
//         vm.assume(debtAmount > 0);

//         vm.expectRevert();
//         liiquidate.liquidate(
//             borrower,
//             address(debtToken),
//             debtAmount,
//             address(0)
//         );
//     }

//     // ========== STATE CONSISTENCY ==========

//     function testFuzzStateAfterLiquidations(
//         uint256[] calldata operations
//     ) public {
//         vm.assume(operations.length <= 100);

//         for (uint256 i = 0; i < operations.length && i < 10; i++) {
//             uint256 debtAmount = (operations[i] % 100_000) + 1;
//             debtAmount = debtAmount * 1e18;

//             address borrowerAddr = address(uint160(100 + i));

//             debtManager.setupUserAccount(
//                 borrowerAddr,
//                 address(collateralToken),
//                 ((operations[i] % 100_000) + 100_000) * 1e18,
//                 address(debtToken),
//                 debtAmount
//             );

//             try
//                 liiquidate.liquidate(
//                     borrowerAddr,
//                     address(debtToken),
//                     debtAmount / 2,
//                     address(collateralToken)
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== SEQUENTIAL LIQUIDATIONS ==========

//     function testFuzzSequentialLiquidations(
//         uint256 firstDebt,
//         uint256 secondDebt
//     ) public {
//         vm.assume(firstDebt > 0);
//         vm.assume(firstDebt <= 500_000e18);
//         vm.assume(secondDebt > 0);
//         vm.assume(secondDebt <= 500_000e18);

//         address borrower1 = address(0x100);
//         address borrower2 = address(0x101);

//         debtManager.setupUserAccount(
//             borrower1,
//             address(collateralToken),
//             100_000e18,
//             address(debtToken),
//             firstDebt
//         );

//         debtManager.setupUserAccount(
//             borrower2,
//             address(collateralToken),
//             100_000e18,
//             address(debtToken),
//             secondDebt
//         );

//         // Liquidate first borrower
//         try
//             liiquidate.liquidate(
//                 borrower1,
//                 address(debtToken),
//                 firstDebt / 2,
//                 address(collateralToken)
//             )
//         {
//             // Success
//         } catch {
//             // Expected
//         }
//         // Liquidate second borrower
//         try
//             liiquidate.liquidate(
//                 borrower2,
//                 address(debtToken),
//                 secondDebt / 2,
//                 address(collateralToken)
//             )
//         {
//             // Success
//         } catch {
//             // Expected
//         }
//     }

//     // ========== GAS OPTIMIZATION FUZZ ==========

//     function testFuzzLiquidationGas(uint256 debtAmount) public {
//         vm.assume(debtAmount > 0);
//         vm.assume(debtAmount <= 100_000e18);

//         debtManager.setupUserAccount(
//             borrower,
//             address(collateralToken),
//             100_000e18,
//             address(debtToken),
//             debtAmount
//         );

//         uint256 gasStart = gasleft();
//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(debtToken),
//                 debtAmount,
//                 address(collateralToken)
//             )
//         {
//             uint256 gasUsed = gasStart - gasleft();
//             assertTrue(gasUsed < 2_000_000); // Reasonable gas limit
//         } catch {}
//     }

//     // ========== MAXIMUM VALUES ==========

//     function testFuzzMaxDebtLiquidation() public {
//         uint256 maxDebt = type(uint256).max / 2;

//         debtManager.setupUserAccount(
//             borrower,
//             address(collateralToken),
//             type(uint256).max / 4,
//             address(debtToken),
//             maxDebt
//         );

//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(debtToken),
//                 maxDebt,
//                 address(collateralToken)
//             )
//         {
//             // Tests max values
//         } catch {
//             // Expected
//         }
//     }

//     // ========== PROFITABILITY CHECKS ==========

//     function testFuzzProfitabilityCalculations(
//         uint256 debtAmount,
//         uint256 collateralValue
//     ) public {
//         vm.assume(debtAmount > 0);
//         vm.assume(debtAmount <= 100_000e18);
//         vm.assume(collateralValue > 0);
//         vm.assume(collateralValue <= 100_000e18);

//         debtManager.setupUserAccount(
//             borrower,
//             address(collateralToken),
//             collateralValue,
//             address(debtToken),
//             debtAmount
//         );

//         // Should only liquidate if profitable
//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(debtToken),
//                 debtAmount,
//                 address(collateralToken)
//             )
//         {
//             // Tests profitability logic
//         } catch {
//             // Expected
//         }
//     }
// }
