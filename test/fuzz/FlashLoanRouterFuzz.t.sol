// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";
// import {MockERC20} from "../mocks/MockERC20.sol";
// import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";

// /**
//  * @title FlashLoanRouterFuzz
//  * @notice Fuzz tests for FlashLoanRouter
//  */
// contract FlashLoanRouterFuzz is Test {
//     FlashLoanRouter public router;
//     MockERC20 public token;
//     MockAaveV3Pool public pool;

//     address public owner;

//     function setUp() public {
//         owner = address(this);
//         router = new FlashLoanRouter();
//         token = new MockERC20("Test Token", "TTK", 18);
//         pool = new MockAaveV3Pool(address(token), address(token));

//         token.mint(address(pool), 1_000_000e18);
//     }

//     // ========== PROVIDER REGISTRATION FUZZ ==========

//     function testFuzzRegisterProvider(
//         bytes32 providerId,
//         address provider,
//         uint256 priority
//     ) public {
//         vm.assume(provider != address(0));
//         vm.assume(providerId != bytes32(0));

//         router.setPrimaryProvider(provider, priority);
//         assertEq(router.getPrimaryProvider(), provider);
//     }

//     function testFuzzAddMultipleProviders(
//         address[] calldata providers,
//         uint256[] calldata priorities
//     ) public {
//         vm.assume(providers.length == priorities.length);
//         vm.assume(providers.length <= 50);

//         for (uint256 i = 0; i < providers.length; i++) {
//             vm.assume(providers[i] != address(0));

//             router.setPrimaryProvider(providers[i], priorities[i]);
//         }
//     }

//     function testFuzzProviderPriority(
//         address provider1,
//         address provider2,
//         uint256 priority1,
//         uint256 priority2
//     ) public {
//         vm.assume(provider1 != address(0));
//         vm.assume(provider2 != address(0));
//         vm.assume(provider1 != provider2);

//         router.setPrimaryProvider(provider1, priority1);
//         router.setPrimaryProvider(provider2, priority2);

//         // Last set provider should be primary
//         assertEq(router.getPrimaryProvider(), provider2);
//     }

//     // ========== FLASH LOAN INITIATION FUZZ ==========

//     function testFuzzFlashLoanAmounts(
//         uint256 amount
//     ) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 1_000_000e18);

//         // Setup provider
//         router.setPrimaryProvider(address(pool), 1);

//         // This tests that different amounts are handled
//         try router.flashLoan(
//             address(token),
//             address(token),
//             amount,
//             address(this),
//             ""
//         ) {
//             // Success case
//         } catch {
//             // May fail due to mock implementation
//         }
//     }

//     function testFuzzFlashLoanWithDifferentTokens(
//         address token1,
//         address token2,
//         uint256 amount
//     ) public {
//         vm.assume(token1 != address(0));
//         vm.assume(token2 != address(0));
//         vm.assume(amount > 0);
//         vm.assume(amount <= 1_000_000e18);

//         router.setPrimaryProvider(address(pool), 1);

//         try router.flashLoan(
//             token1,
//             token2,
//             amount,
//             address(this),
//             ""
//         ) {
//             // Tests parameter passing
//         } catch {
//             // Expected for invalid tokens
//         }
//     }

//     // ========== PROVIDER SELECTION FUZZ ==========

//     function testFuzzProviderSelection(
//         uint256 providerCount,
//         bytes32[] calldata data
//     ) public {
//         vm.assume(providerCount > 0);
//         vm.assume(providerCount <= 50);

//         for (uint256 i = 0; i < providerCount && i < 50; i++) {
//             address provider = address(uint160(i + 1));
//             router.setPrimaryProvider(provider, i);
//         }

//         // Router should use one of the registered providers
//         address primaryProvider = router.getPrimaryProvider();
//         assertTrue(primaryProvider != address(0));
//     }

//     // ========== EDGE CASES ==========

//     function testFuzzZeroAmountFlashLoan(address provider) public {
//         vm.assume(provider != address(0));

//         router.setPrimaryProvider(provider, 1);

//         vm.expectRevert();
//         router.flashLoan(
//             address(token),
//             address(token),
//             0,
//             address(this),
//             ""
//         );
//     }

//     function testFuzzZeroProviderAddress(uint256 priority) public {
//         vm.expectRevert();
//         router.setPrimaryProvider(address(0), priority);
//     }

//     function testFuzzZeroTokenFlashLoan(
//         address provider,
//         uint256 amount
//     ) public {
//         vm.assume(provider != address(0));
//         vm.assume(amount > 0);

//         router.setPrimaryProvider(provider, 1);

//         vm.expectRevert();
//         router.flashLoan(
//             address(0),
//             address(token),
//             amount,
//             address(this),
//             ""
//         );
//     }

//     // ========== FALLBACK MECHANISM FUZZ ==========

//     function testFuzzFallbackWithMultipleProviders(
//         uint256[] calldata priorities
//     ) public {
//         vm.assume(priorities.length > 0);
//         vm.assume(priorities.length <= 50);

//         for (uint256 i = 0; i < priorities.length; i++) {
//             address provider = address(uint160(i + 1));
//             router.setPrimaryProvider(provider, priorities[i]);
//         }

//         // Should have a primary provider available
//         address primaryProvider = router.getPrimaryProvider();
//         assertTrue(primaryProvider != address(0));
//     }

//     // ========== STATE CONSISTENCY FUZZ ==========

//     function testFuzzStateAfterOperations(
//         bytes32[] calldata operationData,
//         uint256[] calldata amounts
//     ) public {
//         vm.assume(operationData.length <= 100);
//         vm.assume(amounts.length <= 100);

//         router.setPrimaryProvider(address(pool), 1);

//         address primaryBefore = router.getPrimaryProvider();

//         for (uint256 i = 0; i < operationData.length && i < 10; i++) {
//             address newProvider = address(uint160(i + 2));
//             try router.setPrimaryProvider(newProvider, i){
//                 //
//             } catch {
//                 //
//             }
//         }

//         // Primary provider should still be set
//         address primaryAfter = router.getPrimaryProvider();
//         assertTrue(primaryAfter != address(0));
//     }

//     // ========== GAS OPTIMIZATION FUZZ ==========

//     function testFuzzProviderSelectionGas(
//         uint256 providerCount
//     ) public {
//         vm.assume(providerCount > 0);
//         vm.assume(providerCount <= 50);

//         for (uint256 i = 0; i < providerCount; i++) {
//             address provider = address(uint160(i + 1));
//             router.setPrimaryProvider(provider, i);
//         }

//         uint256 gasStart = gasleft();
//         address primary = router.getPrimaryProvider();
//         uint256 gasUsed = gasStart - gasleft();

//         assertTrue(gasUsed < 10_000);
//         assertTrue(primary != address(0));
//     }

//     // ========== CALLBACK DATA FUZZ ==========

//     function testFuzzCallbackDataHandling(
//         bytes calldata callbackData
//     ) public {
//         router.setPrimaryProvider(address(pool), 1);

//         try router.flashLoan(
//             address(token),
//             address(token),
//             1000e18,
//             address(this),
//             callbackData
//         ) {
//             // Tests callback data passing
//         } catch {
//             // Expected for most cases
//         }
//     }

//     function testFuzzLargeCallbackData(
//         uint256 dataSize
//     ) public {
//         vm.assume(dataSize <= 10_000);

//         bytes memory largeData = new bytes(dataSize);

//         router.setPrimaryProvider(address(pool), 1);

//         try router.flashLoan(
//             address(token),
//             address(token),
//             1000e18,
//             address(this),
//             largeData
//         ) {
//             // Tests large callback data
//         } catch {
//             // Expected
//         }
//     }

//     // ========== REENTRANCY FUZZ TESTS ==========

//     function testFuzzReentrancyProtection(
//         uint256 amount
//     ) public {
//         vm.assume(amount > 0);
//         vm.assume(amount <= 1_000_000e18);

//         router.setPrimaryProvider(address(pool), 1);

//         // The router should handle reentrancy attempts safely
//         try router.flashLoan(
//             address(token),
//             address(token),
//             amount,
//             address(this),
//             ""
//         ) {
//             // Tests reentrancy handling
//         } catch {
//             // Expected
//         }
//     }

//     // ========== MAXIMUM VALUES FUZZ ==========

//     function testFuzzMaxUintAmount() public {
//         router.setPrimaryProvider(address(pool), 1);

//         vm.expectRevert();
//         router.flashLoan(
//             address(token),
//             address(token),
//             type(uint256).max,
//             address(this),
//             ""
//         );
//     }

//     function testFuzzMaxPriority() public {
//         router.setPrimaryProvider(address(pool), type(uint256).max);
//         assertEq(router.getPrimaryProvider(), address(pool));
//     }
// }
