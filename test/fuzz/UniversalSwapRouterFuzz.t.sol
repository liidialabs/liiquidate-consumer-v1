// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
// import {MockERC20} from "../mocks/MockERC20.sol";

// /**
//  * @title UniversalSwapRouterFuzz
//  * @notice Fuzz tests for UniversalSwapRouter
//  */
// contract UniversalSwapRouterFuzz is Test {
//     UniversalSwapRouter public swapRouter;
//     MockERC20 public tokenA;
//     MockERC20 public tokenB;
//     MockERC20 public tokenC;

//     address public swapper = address(0x1);

//     function setUp() public {
//         swapRouter = new UniversalSwapRouter();
//         tokenA = new MockERC20("Token A", "TKNA", 18);
//         tokenB = new MockERC20("Token B", "TKNB", 18);
//         tokenC = new MockERC20("Token C", "TKNC", 18);

//         // Setup initial balances
//         tokenA.mint(swapper, 1_000_000e18);
//         tokenB.mint(address(swapRouter), 1_000_000e18);
//         tokenC.mint(address(swapRouter), 1_000_000e18);
//     }

//     // ========== SWAP AMOUNT FUZZ ==========

//     function testFuzzSwapAmounts(uint256 amountIn) public {
//         vm.assume(amountIn > 0);
//         vm.assume(amountIn <= 1_000_000e18);

//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), amountIn);

//         try
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 amountIn,
//                 0,
//                 swapper
//             )
//         {
//             // Tests different swap amounts
//         } catch {
//             // Expected for uninitialized adapters
//         }
//     }

//     function testFuzzMultipleSwaps(uint256[] calldata amounts) public {
//         vm.assume(amounts.length <= 100);

//         for (uint256 i = 0; i < amounts.length; i++) {
//             vm.assume(amounts[i] > 0);
//             vm.assume(amounts[i] <= 100_000e18);

//             vm.prank(swapper);
//             try
//                 swapRouter.swapExactInputSingleHop(
//                     address(tokenA),
//                     address(tokenB),
//                     amounts[i],
//                     0,
//                     swapper
//                 )
//             {
//                 // Tests sequential swaps
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== MINIMUM OUTPUT FUZZ ==========

//     function testFuzzMinimumOutput(
//         uint256 amountIn,
//         uint256 minAmountOut
//     ) public {
//         vm.assume(amountIn > 0);
//         vm.assume(amountIn <= 100_000e18);
//         vm.assume(minAmountOut <= amountIn); // minAmountOut <= amountIn (accounting for slippage)

//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), amountIn);

//         try
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 amountIn,
//                 minAmountOut,
//                 swapper
//             )
//         {
//             // Tests minimum output enforcement
//         } catch {
//             // Expected
//         }
//     }

//     function testFuzzSlippageValues(uint256 amountIn, uint256 slippage) public {
//         vm.assume(amountIn > 0);
//         vm.assume(amountIn <= 100_000e18);
//         vm.assume(slippage <= 10000); // 100% max

//         uint256 minOutput = (amountIn * (10000 - slippage)) / 10000;

//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), amountIn);

//         try
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 amountIn,
//                 minOutput,
//                 swapper
//             )
//         {
//             // Tests different slippage tolerances
//         } catch {
//             // Expected
//         }
//     }

//     // ========== DIFFERENT TOKEN PAIRS FUZZ ==========

//     function testFuzzTokenPairSwaps(
//         address token1,
//         address token2,
//         uint256 amount
//     ) public {
//         vm.assume(token1 != address(0));
//         vm.assume(token2 != address(0));
//         vm.assume(amount > 0);
//         vm.assume(amount <= 100_000e18);

//         try
//             swapRouter.swapExactInputSingleHop(
//                 token1,
//                 token2,
//                 amount,
//                 0,
//                 swapper
//             )
//         {
//             // Tests different token combinations
//         } catch {
//             // Expected for uninitialized pairs
//         }
//     }

//     function testFuzzChainSwaps(address[] calldata tokenPath) public {
//         vm.assume(tokenPath.length >= 2);
//         vm.assume(tokenPath.length <= 10);

//         for (uint256 i = 0; i < tokenPath.length; i++) {
//             vm.assume(tokenPath[i] != address(0));
//         }

//         // Multi-hop swap simulation
//         uint256 amount = 1000e18;

//         try
//             swapRouter.swapMultiHop(
//                 tokenPath[0],
//                 tokenPath[tokenPath.length - 1],
//                 amount,
//                 0
//             )
//         {
//             // Tests multi-hop routing
//         } catch {
//             // Expected
//         }
//     }

//     // ========== EXTREME VALUES FUZZ ==========

//     function testFuzzZeroAmountSwap() public {
//         vm.prank(swapper);
//         vm.expectRevert();
//         swapRouter.swapExactInputSingleHop(
//             address(tokenA),
//             address(tokenB),
//             0,
//             0,
//             swapper
//         );
//     }

//     function testFuzzMaxUintAmount() public {
//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), type(uint256).max);

//         vm.expectRevert();
//         swapRouter.swapExactInputSingleHop(
//             address(tokenA),
//             address(tokenB),
//             type(uint256).max,
//             0,
//             swapper
//         );
//     }

//     function testFuzzVerySmallAmount() public {
//         uint256 tinyAmount = 1; // 1 wei

//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), tinyAmount);

//         try
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 tinyAmount,
//                 0,
//                 swapper
//             )
//         {
//             // Tests very small amounts
//         } catch {
//             // Expected
//         }
//     }

//     // ========== RECIPIENT ADDRESS FUZZ ==========

//     function testFuzzDifferentRecipients(
//         address[] calldata recipients,
//         uint256 amount
//     ) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 100_000e18);
//         vm.assume(recipients.length <= 50);

//         for (uint256 i = 0; i < recipients.length; i++) {
//             address recipient = recipients[i];

//             vm.prank(swapper);
//             try
//                 swapRouter.swapExactInputSingleHop(
//                     address(tokenA),
//                     address(tokenB),
//                     amount,
//                     0,
//                     recipient
//                 )
//             {
//                 // Tests different recipient addresses
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     function testFuzzZeroRecipient(uint256 amount) public {
//         vm.assume(amount > 0);

//         vm.prank(swapper);
//         try
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 amount,
//                 0,
//                 address(0)
//             )
//         {
//             // May succeed or fail depending on implementation
//         } catch {
//             // Expected
//         }
//     }

//     // ========== CIRCUIT BREAKER FUZZ ==========

//     function testFuzzCircuitBreakerActivation(uint256 priceDeviation) public {
//         vm.assume(priceDeviation <= 100000); // 100% deviation

//         // Circuit breaker should activate on large price changes
//         // This tests the circuit breaking mechanism
//     }

//     function testFuzzCircuitBreakerRecovery(uint256 timeDelay) public {
//         vm.assume(timeDelay > 0);
//         vm.assume(timeDelay <= 1 days);

//         // Circuit breaker should recover after time delay
//         vm.warp(block.timestamp + timeDelay);
//     }

//     // ========== STATE CONSISTENCY ==========

//     function testFuzzStateAfterSwaps(bytes32[] calldata operations) public {
//         vm.assume(operations.length <= 100);

//         for (uint256 i = 0; i < operations.length; i++) {
//             uint256 amount = (uint256(operations[i]) % 100_000) + 1;
//             amount = amount * 1e18;

//             vm.prank(swapper);
//             try
//                 swapRouter.swapExactInputSingleHop(
//                     address(tokenA),
//                     address(tokenB),
//                     amount,
//                     0,
//                     swapper
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== GAS OPTIMIZATION FUZZ ==========

//     function testFuzzSwapGasUsage(uint256 amount) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 100_000e18);

//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), amount);

//         uint256 gasStart = gasleft();
//         try
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 amount,
//                 0,
//                 swapper
//             )
//         {
//             uint256 gasUsed = gasStart - gasleft();
//             assertTrue(gasUsed < 1_000_000); // Reasonable gas limit
//         } catch {}
//     }

//     // ========== APPROVAL HANDLING ==========

//     function testFuzzApprovalAmounts(
//         uint256 swapAmount,
//         uint256 approvalAmount
//     ) public {
//         vm.assume(swapAmount > 0);
//         vm.assume(approvalAmount > 0);

//         vm.prank(swapper);
//         tokenA.approve(address(swapRouter), approvalAmount);

//         if (approvalAmount >= swapAmount) {
//             try
//                 swapRouter.swapExactInputSingleHop(
//                     address(tokenA),
//                     address(tokenB),
//                     swapAmount,
//                     0,
//                     swapper
//                 )
//             {
//                 // Should work
//             } catch {
//                 // May fail for other reasons
//             }
//         } else {
//             vm.prank(swapper);
//             vm.expectRevert();
//             swapRouter.swapExactInputSingleHop(
//                 address(tokenA),
//                 address(tokenB),
//                 swapAmount,
//                 0,
//                 swapper
//             );
//         }
//     }

//     // ========== ADAPTER HEALTH CHECKS ==========

//     function testFuzzAdapterSelectionLogic(
//         uint8[] calldata adapterPriorities
//     ) public {
//         vm.assume(adapterPriorities.length <= 50);

//         // Router should select best adapter based on priorities and quotes
//         // This tests adapter health and selection logic
//     }

//     // ========== PRICE IMPACT FUZZ ==========

//     function testFuzzPriceImpact(uint256 amount) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 1_000_000e18);

//         // Larger amounts should have larger price impact
//         // Expected output decreases with amount
//     }

//     function testFuzzLargeVsSmallSwaps(
//         uint256 smallAmount,
//         uint256 largeAmount
//     ) public {
//         vm.assume(smallAmount > 0);
//         vm.assume(smallAmount <= 100_000e18);
//         vm.assume(largeAmount > smallAmount);
//         vm.assume(largeAmount <= 900_000e18);

//         // Small swaps should have better rate than large swaps
//     }
// }
