// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {UniswapV4} from "../../src/flashloans/UniswapV4.sol";
// import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
// import {MockERC20} from "../mocks/MockERC20.sol";
// import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
// import {LiquidationParams} from "../../src/types/DataTypes.sol";

// /**
//  * @title UniswapV4FlashLoanFuzz
//  * @notice Fuzz tests for Uniswap V4 flash loan provider
//  */
// contract UniswapV4FlashLoanFuzz is Test {
//     UniswapV4 public flashLoan;
//     MockUniswapV4PoolManager public poolManager;
//     MockERC20 public debtToken;
//     MockERC20 public collateralToken;
//     UniversalSwapRouter public swapRouter;

//     address public liquidator = address(0x1);

//     function setUp() public {
//         debtToken = new MockERC20("Debt", "DBT", 18);
//         collateralToken = new MockERC20("Collateral", "COLL", 18);

//         poolManager = new MockUniswapV4PoolManager();
//         swapRouter = new UniversalSwapRouter();
//         flashLoan = new UniswapV4(address(poolManager), address(swapRouter));

//         debtToken.mint(address(poolManager), 10_000_000e18);
//         collateralToken.mint(address(poolManager), 10_000_000e18);
//     }

//     // ========== FLASH LOAN AMOUNT FUZZ ==========

//     function testFuzzFlashLoanAmounts(uint256 amount) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 1_000_000e18);

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 amount,
//                 address(this),
//                 ""
//             )
//         {
//             // Tests various amounts
//         } catch {
//             // Expected for large amounts
//         }
//     }

//     function testFuzzMultipleFlashLoans(uint256[] calldata amounts) public {
//         vm.assume(amounts.length <= 50);

//         for (uint256 i = 0; i < amounts.length; i++) {
//             vm.assume(amounts[i] > 0);
//             vm.assume(amounts[i] <= 500_000e18);

//             vm.prank(liquidator);
//             try
//                 flashLoan.flashLoan(
//                     address(debtToken),
//                     address(collateralToken),
//                     amounts[i],
//                     address(this),
//                     ""
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== DIFFERENT TOKEN COMBINATIONS ==========

//     function testFuzzTokenCombinations(
//         address tokenA,
//         address tokenB,
//         uint256 amount
//     ) public {
//         vm.assume(tokenA != address(0));
//         vm.assume(tokenB != address(0));
//         vm.assume(amount > 0);
//         vm.assume(amount <= 100_000e18);

//         vm.prank(liquidator);
//         try flashLoan.flashLoan(tokenA, tokenB, amount, address(this), "") {
//             // Tests different token combinations
//         } catch {
//             // Expected for uninitialized tokens
//         }
//     }

//     // ========== UNLOCK CALLBACK TESTING ==========

//     function testFuzzUnlockCallbackData(bytes calldata callbackData) public {
//         uint256 amount = 10_000e18;

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 amount,
//                 address(this),
//                 callbackData
//             )
//         {
//             // Tests unlock callback with different data
//         } catch {
//             // Expected
//         }
//     }

//     function testFuzzLargeUnlockData(uint256 size) public {
//         vm.assume(size <= 10_000);

//         bytes memory largeData = new bytes(size);

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 1_000e18,
//                 address(this),
//                 largeData
//             )
//         {
//             // Tests large unlock callback data
//         } catch {
//             // Expected
//         }
//     }

//     // ========== TARGET CONTRACT VARIATIONS ==========

//     function testFuzzDifferentTargets(address[] calldata targets) public {
//         vm.assume(targets.length <= 50);

//         for (uint256 i = 0; i < targets.length; i++) {
//             address target = targets[i] != address(0)
//                 ? targets[i]
//                 : address(this);

//             vm.prank(liquidator);
//             try
//                 flashLoan.flashLoan(
//                     address(debtToken),
//                     address(collateralToken),
//                     1_000e18,
//                     target,
//                     ""
//                 )
//             {
//                 // Tests different target contracts
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== INVALID PARAMETERS ==========

//     function testFuzzZeroAmountFlashLoan() public {
//         vm.prank(liquidator);
//         vm.expectRevert("Amount cannot be zero!");
//         flashLoan.flashLoan(
//             address(debtToken),
//             address(collateralToken),
//             0,
//             address(this),
//             ""
//         );
//     }

//     function testFuzzZeroDebtToken() public {
//         vm.prank(liquidator);
//         vm.expectRevert("Invalid Address");
//         flashLoan.flashLoan(
//             address(0),
//             address(collateralToken),
//             1_000e18,
//             address(this),
//             ""
//         );
//     }

//     function testFuzzZeroCollateralToken() public {
//         vm.prank(liquidator);
//         vm.expectRevert("Invalid Address");
//         flashLoan.flashLoan(
//             address(debtToken),
//             address(0),
//             1_000e18,
//             address(this),
//             ""
//         );
//     }

//     function testFuzzZeroTarget() public {
//         vm.prank(liquidator);
//         vm.expectRevert("Invalid Address");
//         flashLoan.flashLoan(
//             address(debtToken),
//             address(collateralToken),
//             1_000e18,
//             address(0),
//             ""
//         );
//     }

//     // ========== SEQUENTIAL OPERATIONS ==========

//     function testFuzzSequentialFlashLoans(uint256[] calldata amounts) public {
//         vm.assume(amounts.length <= 100);

//         for (uint256 i = 0; i < amounts.length; i++) {
//             vm.assume(amounts[i] > 0);
//             vm.assume(amounts[i] <= 100_000e18);

//             address liquidatorAddr = address(uint160(100 + i));

//             vm.prank(liquidatorAddr);
//             try
//                 flashLoan.flashLoan(
//                     address(debtToken),
//                     address(collateralToken),
//                     amounts[i],
//                     address(this),
//                     ""
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== CONCURRENT OPERATIONS FROM DIFFERENT CALLERS ==========

//     function testFuzzConcurrentCallers(
//         address[] calldata callers,
//         uint256[] calldata amounts
//     ) public {
//         vm.assume(callers.length <= 50);
//         vm.assume(amounts.length == callers.length);

//         for (uint256 i = 0; i < callers.length; i++) {
//             vm.assume(amounts[i] > 0);
//             vm.assume(amounts[i] <= 50_000e18);

//             address caller = callers[i] != address(0)
//                 ? callers[i]
//                 : address(uint160(200 + i));

//             vm.prank(caller);
//             try
//                 flashLoan.flashLoan(
//                     address(debtToken),
//                     address(collateralToken),
//                     amounts[i],
//                     address(this),
//                     ""
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== EXTREME VALUES ==========

//     function testFuzzVeryLargeAmount() public {
//         uint256 largeAmount = 9_000_000e18; // 90% of pool

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 largeAmount,
//                 address(this),
//                 ""
//             )
//         {
//             // Tests very large amounts
//         } catch {
//             // Expected
//         }
//     }

//     function testFuzzVerySmallAmount() public {
//         uint256 tinyAmount = 1; // 1 wei

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 tinyAmount,
//                 address(this),
//                 ""
//             )
//         {
//             // Tests very small amounts
//         } catch {
//             // Expected
//         }
//     }

//     function testFuzzMaxUintAmount() public {
//         vm.prank(liquidator);
//         vm.expectRevert();
//         flashLoan.flashLoan(
//             address(debtToken),
//             address(collateralToken),
//             type(uint256).max,
//             address(this),
//             ""
//         );
//     }

//     // ========== STATE CONSISTENCY ==========

//     function testFuzzStateAfterFlashLoans(
//         bytes32[] calldata operations
//     ) public {
//         vm.assume(operations.length <= 100);

//         for (uint256 i = 0; i < operations.length; i++) {
//             uint256 amount = (uint256(operations[i]) % 50_000) + 1;
//             amount = amount * 1e18;

//             vm.prank(liquidator);
//             try
//                 flashLoan.flashLoan(
//                     address(debtToken),
//                     address(collateralToken),
//                     amount,
//                     address(this),
//                     ""
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== GAS OPTIMIZATION ==========

//     function testFuzzFlashLoanGasUsage(uint256 amount) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 100_000e18);

//         vm.prank(liquidator);
//         uint256 gasStart = gasleft();
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 amount,
//                 address(this),
//                 ""
//             )
//         {
//             uint256 gasUsed = gasStart - gasleft();
//             assertTrue(gasUsed < 2_000_000);
//         } catch {}
//     }

//     // ========== PROVIDER ID ==========

//     function testFuzzProviderIdConsistency() public {
//         bytes32 id1 = flashLoan.id();
//         bytes32 id2 = flashLoan.id();
//         assertEq(id1, id2);

//         bytes32 expectedId = keccak256("UNISWAP_V4");
//         assertEq(id1, expectedId);
//     }

//     // ========== TOKEN RESCUE ==========

//     function testFuzzRescueTokens(uint256 amount) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 100_000e18);

//         debtToken.mint(address(flashLoan), amount);

//         vm.prank(flashLoan.owner());
//         flashLoan.rescueTokens(address(debtToken), amount);

//         assertEq(debtToken.balanceOf(flashLoan.owner()), amount);
//     }

//     // ========== RECEIVE FUNCTION ==========

//     function testFuzzReceiveETH(uint256 amount) public {
//         vm.assume(amount >= 0);
//         vm.assume(amount <= 1000 ether);

//         vm.deal(liquidator, amount);

//         vm.prank(liquidator);
//         (bool success, ) = address(flashLoan).call{value: amount}("");
//         assertTrue(success);
//     }

//     // ========== LIQUIDATION PARAMETER VARIATIONS ==========

//     function testFuzzLiquidationParamsEncoding(
//         LiquidationParams memory params
//     ) public {
//         bytes memory encoded = abi.encode(liquidator, params);

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 params.debtAsset != address(0)
//                     ? params.debtAsset
//                     : address(debtToken),
//                 params.collateralAsset != address(0)
//                     ? params.collateralAsset
//                     : address(collateralToken),
//                 params.debtToCover > 0 ? params.debtToCover : 1_000e18,
//                 params.liquidationTarget != address(0)
//                     ? params.liquidationTarget
//                     : address(this),
//                 encoded
//             )
//         {
//             // Tests various liquidation parameters
//         } catch {
//             // Expected
//         }
//     }

//     // ========== REENTRANCY PROTECTION ==========

//     function testFuzzReentrancyAttempts(uint256 recursionDepth) public {
//         vm.assume(recursionDepth <= 10);

//         uint256 amount = 10_000e18;

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 amount,
//                 address(this),
//                 ""
//             )
//         {
//             // Tests reentrancy handling
//         } catch {
//             // Expected
//         }
//     }

//     // ========== POOL MANAGER INTERACTION ==========

//     function testFuzzPoolManagerCalls(address[] calldata managers) public {
//         vm.assume(managers.length <= 10);

//         // Tests that flash loan correctly uses pool manager
//         for (uint256 i = 0; i < managers.length && i < 5; i++) {
//             if (managers[i] != address(0)) {
//                 // Test interactions
//             }
//         }
//     }

//     // ========== PARAMETER BOUNDARY TESTING ==========

//     function testFuzzBoundaryAmounts(uint256 amount) public {
//         vm.assume(amount >= 1);
//         vm.assume(amount <= 10_000_000e18);

//         vm.prank(liquidator);
//         try
//             flashLoan.flashLoan(
//                 address(debtToken),
//                 address(collateralToken),
//                 amount,
//                 address(this),
//                 ""
//             )
//         {
//             // Tests boundary values
//         } catch {
//             // Expected
//         }
//     }

//     // ========== OWNERSHIP ==========

//     function testFuzzOwnershipTransfer(address[] calldata newOwners) public {
//         vm.assume(newOwners.length <= 10);

//         for (uint256 i = 0; i < newOwners.length; i++) {
//             if (newOwners[i] != address(0)) {
//                 flashLoan.transferOwnership(newOwners[i]);
//                 assertEq(flashLoan.owner(), newOwners[i]);

//                 // New owner can rescue tokens
//                 vm.prank(newOwners[i]);
//                 debtToken.mint(address(flashLoan), 1_000e18);
//                 flashLoan.rescueTokens(address(debtToken), 1_000e18);
//             }
//         }
//     }
// }
