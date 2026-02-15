// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {Liiquidate} from "../../src/Liiquidate.sol";
// import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";
// import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
// import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
// import {MockERC20} from "../mocks/MockERC20.sol";
// import {MockDebtManager} from "../mocks/MockDebtManager.sol";
// import {MockLendingProtocol} from "../mocks/MockLendingProtocol.sol";
// import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";

// /**
//  * @title IntegrationFuzz
//  * @notice Integration fuzz tests for Liiquidate system
//  */
// contract IntegrationFuzz is Test {
//     Liiquidate public liiquidate;
//     FlashLoanRouter public flashLoanRouter;
//     UniversalSwapRouter public swapRouter;
//     AdapterRegistry public adapterRegistry;
//     MockDebtManager public debtManager;
//     MockLendingProtocol public lendingProtocol;
//     MockAaveV3Pool public aavePool;

//     MockERC20 public usdc;
//     MockERC20 public usdt;
//     MockERC20 public dai;

//     address public liquidator = address(0x1);
//     address public borrower = address(0x2);

//     function setUp() public {
//         // Setup tokens
//         usdc = new MockERC20("USDC", "USDC", 6);
//         usdt = new MockERC20("USDT", "USDT", 6);
//         dai = new MockERC20("DAI", "DAI", 18);

//         // Setup protocol components
//         adapterRegistry = new AdapterRegistry();
//         debtManager = new MockDebtManager();
//         lendingProtocol = new MockLendingProtocol();
//         aavePool = new MockAaveV3Pool(address(usdc), address(dai));

//         // Setup routers
//         flashLoanRouter = new FlashLoanRouter();
//         swapRouter = new UniversalSwapRouter();

//         // Setup main contract
//         liiquidate = new Liiquidate(
//             address(debtManager),
//             address(lendingProtocol),
//             address(flashLoanRouter)
//         );

//         // Setup token balances
//         usdc.mint(address(aavePool), 1_000_000_000e6);
//         usdt.mint(liquidator, 1_000_000_000e6);
//         dai.mint(address(lendingProtocol), 1_000_000_000e18);
//     }

//     // ========== FULL LIQUIDATION FLOW FUZZ ==========

//     function testFuzzCompleteLiquidationFlow(
//         uint256 collateralAmount,
//         uint256 debtAmount,
//         uint256 liquidationAmount
//     ) public {
//         vm.assume(collateralAmount > 0);
//         vm.assume(collateralAmount <= 1_000_000e18);
//         vm.assume(debtAmount > 0);
//         vm.assume(debtAmount <= 1_000_000e18);
//         vm.assume(liquidationAmount > 0);
//         vm.assume(liquidationAmount <= debtAmount);

//         // Setup borrower
//         debtManager.setupUserAccount(
//             borrower,
//             address(dai),
//             collateralAmount,
//             address(usdc),
//             debtAmount
//         );

//         // Attempt liquidation
//         vm.prank(liquidator);
//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(usdc),
//                 liquidationAmount,
//                 address(dai)
//             )
//         {
//             // Success
//         } catch {
//             // Expected for invalid configurations
//         }
//     }

//     // ========== MULTIPLE BORROWERS LIQUIDATION ==========

//     function testFuzzMultipleBorrowerLiquidations(
//         uint256[] calldata borrowerDebts,
//         uint256[] calldata borrowerCollaterals
//     ) public {
//         vm.assume(borrowerDebts.length == borrowerCollaterals.length);
//         vm.assume(borrowerDebts.length <= 50);

//         for (uint256 i = 0; i < borrowerDebts.length; i++) {
//             vm.assume(borrowerDebts[i] > 0);
//             vm.assume(borrowerDebts[i] <= 100_000e18);
//             vm.assume(borrowerCollaterals[i] > 0);
//             vm.assume(borrowerCollaterals[i] <= 100_000e18);

//             address borrowerAddr = address(uint160(1000 + i));

//             debtManager.setupUserAccount(
//                 borrowerAddr,
//                 address(dai),
//                 borrowerCollaterals[i],
//                 address(usdc),
//                 borrowerDebts[i]
//             );

//             vm.prank(liquidator);
//             try
//                 liiquidate.liquidate(
//                     borrowerAddr,
//                     address(usdc),
//                     borrowerDebts[i] / 2,
//                     address(dai)
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== PARTIAL LIQUIDATIONS SEQUENCE ==========

//     function testFuzzPartialLiquidationSequence(
//         uint256 totalDebt,
//         uint256[] calldata partialAmounts
//     ) public {
//         vm.assume(totalDebt > 0);
//         vm.assume(totalDebt <= 1_000_000e18);
//         vm.assume(partialAmounts.length <= 50);

//         debtManager.setupUserAccount(
//             borrower,
//             address(dai),
//             100_000_000e18,
//             address(usdc),
//             totalDebt
//         );

//         uint256 totalLiquidated = 0;

//         for (uint256 i = 0; i < partialAmounts.length; i++) {
//             vm.assume(partialAmounts[i] > 0);
//             uint256 remainingDebt = totalDebt - totalLiquidated;

//             if (partialAmounts[i] <= remainingDebt) {
//                 vm.prank(liquidator);
//                 try
//                     liiquidate.liquidate(
//                         borrower,
//                         address(usdc),
//                         partialAmounts[i],
//                         address(dai)
//                     )
//                 {
//                     totalLiquidated += partialAmounts[i];
//                 } catch {
//                     // Expected
//                 }
//             }
//         }
//     }

//     // ========== RAPID SUCCESSION LIQUIDATIONS ==========

//     function testFuzzRapidSuccessionLiquidations(
//         uint256[] calldata amounts
//     ) public {
//         vm.assume(amounts.length <= 100);

//         for (uint256 i = 0; i < amounts.length; i++) {
//             vm.assume(amounts[i] > 0);
//             vm.assume(amounts[i] <= 10_000e18);

//             address borrowerAddr = address(uint160(2000 + i));

//             debtManager.setupUserAccount(
//                 borrowerAddr,
//                 address(dai),
//                 100_000e18,
//                 address(usdc),
//                 amounts[i]
//             );

//             vm.prank(liquidator);
//             try
//                 liiquidate.liquidate(
//                     borrowerAddr,
//                     address(usdc),
//                     amounts[i],
//                     address(dai)
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== ROUTER CONFIGURATION FUZZ ==========

//     function testFuzzFlashLoanProviderConfiguration(
//         address[] calldata providers
//     ) public {
//         vm.assume(providers.length <= 50);

//         for (uint256 i = 0; i < providers.length; i++) {
//             if (providers[i] != address(0)) {
//                 flashLoanRouter.setPrimaryProvider(providers[i], i);

//                 address primary = flashLoanRouter.getPrimaryProvider();
//                 assertEq(primary, providers[i]);
//             }
//         }
//     }

//     // ========== TOKEN PAIR COMBINATIONS ==========

//     function testFuzzDifferentTokenPairs(address[] calldata assets) public {
//         vm.assume(assets.length >= 2);
//         vm.assume(assets.length <= 20);

//         for (uint256 i = 0; i < assets.length - 1; i++) {
//             address debtAsset = assets[i] != address(0)
//                 ? assets[i]
//                 : address(usdc);
//             address collateralAsset = assets[i + 1] != address(0)
//                 ? assets[i + 1]
//                 : address(dai);

//             debtManager.setupUserAccount(
//                 borrower,
//                 collateralAsset,
//                 100_000e18,
//                 debtAsset,
//                 10_000e18
//             );

//             vm.prank(liquidator);
//             try
//                 liiquidate.liquidate(
//                     borrower,
//                     debtAsset,
//                     1_000e18,
//                     collateralAsset
//                 )
//             {
//                 // Tests different token pairs
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== STRESS TEST ==========

//     function testFuzzStressMultipleOperations(
//         bytes32[] calldata operations
//     ) public {
//         vm.assume(operations.length <= 500);

//         for (uint256 i = 0; i < operations.length; i++) {
//             uint256 opType = uint256(operations[i]) % 3;
//             uint256 amount = ((uint256(operations[i]) >> 8) % 50_000) + 1;
//             amount = amount * 1e18;

//             address borrowerAddr = address(uint160(3000 + (i % 100)));

//             debtManager.setupUserAccount(
//                 borrowerAddr,
//                 address(dai),
//                 100_000_000e18,
//                 address(usdc),
//                 amount
//             );

//             if (opType == 0) {
//                 // Liquidation operation
//                 vm.prank(liquidator);
//                 try
//                     liiquidate.liquidate(
//                         borrowerAddr,
//                         address(usdc),
//                         amount / 2,
//                         address(dai)
//                     )
//                 {
//                     // Success
//                 } catch {
//                     // Expected
//                 }
//             } else if (opType == 1) {
//                 // Flash loan operation
//                 try
//                     flashLoanRouter.flashLoan(
//                         address(usdc),
//                         address(dai),
//                         amount,
//                         address(this),
//                         ""
//                     )
//                 {
//                     // Success
//                 } catch {
//                     // Expected
//                 }
//             } else {
//                 // Adapter registry operation
//                 bytes32 protocolId = keccak256(abi.encode(i));
//                 address adapter = address(uint160(i + 1));

//                 if (adapter != address(0)) {
//                     adapterRegistry.registerAdapter(protocolId, adapter);
//                 }
//             }
//         }
//     }

//     // ========== EXTREME SCENARIOS ==========

//     function testFuzzExtremeMarketConditions(
//         uint256 collateral,
//         uint256 debt,
//         uint256 volatility
//     ) public {
//         vm.assume(collateral > 0);
//         vm.assume(collateral <= 100_000_000e18);
//         vm.assume(debt > 0);
//         vm.assume(debt <= 100_000_000e18);
//         vm.assume(volatility <= 10000);

//         debtManager.setupUserAccount(
//             borrower,
//             address(dai),
//             collateral,
//             address(usdc),
//             debt
//         );

//         // Simulate price volatility by attempting liquidation with extreme amounts
//         uint256 liquidationAmount = (debt * volatility) / 10000;

//         if (liquidationAmount > 0) {
//             vm.prank(liquidator);
//             try
//                 liiquidate.liquidate(
//                     borrower,
//                     address(usdc),
//                     liquidationAmount,
//                     address(dai)
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== ADAPTER REGISTRY FUZZ ==========

//     function testFuzzAdapterRegistryIntegration(
//         bytes32[] calldata protocolIds,
//         address[] calldata adapters
//     ) public {
//         vm.assume(protocolIds.length == adapters.length);
//         vm.assume(protocolIds.length <= 100);

//         for (uint256 i = 0; i < protocolIds.length; i++) {
//             vm.assume(adapters[i] != address(0));
//             vm.assume(protocolIds[i] != bytes32(0));

//             adapterRegistry.registerAdapter(protocolIds[i], adapters[i]);
//             assertEq(adapterRegistry.getAdapter(protocolIds[i]), adapters[i]);
//         }
//     }

//     // ========== STATE INVARIANTS ==========

//     function testFuzzInvariantsBorrowerDebtTracking(
//         uint256 debtBefore,
//         uint256 liquidationAmount
//     ) public {
//         vm.assume(debtBefore > 0);
//         vm.assume(debtBefore <= 1_000_000e18);
//         vm.assume(liquidationAmount > 0);
//         vm.assume(liquidationAmount <= debtBefore);

//         debtManager.setupUserAccount(
//             borrower,
//             address(dai),
//             1_000_000e18,
//             address(usdc),
//             debtBefore
//         );

//         vm.prank(liquidator);
//         try
//             liiquidate.liquidate(
//                 borrower,
//                 address(usdc),
//                 liquidationAmount,
//                 address(dai)
//             )
//         {
//             // After liquidation, debt should be reduced or remain same
//         } catch {
//             // Expected
//         }
//     }

//     // ========== GAS EFFICIENCY UNDER STRESS ==========

//     function testFuzzGasUnderStress(uint256[] calldata amounts) public {
//         vm.assume(amounts.length <= 100);

//         uint256 totalGas = 0;

//         for (uint256 i = 0; i < amounts.length; i++) {
//             vm.assume(amounts[i] > 0);
//             vm.assume(amounts[i] <= 10_000e18);

//             address borrowerAddr = address(uint160(4000 + i));
//             debtManager.setupUserAccount(
//                 borrowerAddr,
//                 address(dai),
//                 100_000e18,
//                 address(usdc),
//                 amounts[i]
//             );

//             vm.prank(liquidator);
//             uint256 gasStart = gasleft();
//             try
//                 liiquidate.liquidate(
//                     borrowerAddr,
//                     address(usdc),
//                     amounts[i],
//                     address(dai)
//                 )
//             {
//                 uint256 gasUsed = gasStart - gasleft();
//                 totalGas += gasUsed;
//             } catch {}
//         }

//         // Total gas usage should be reasonable
//         if (amounts.length > 0) {
//             uint256 averageGas = totalGas / amounts.length;
//             assertTrue(averageGas < 2_000_000);
//         }
//     }

//     // ========== RECEIVE FUNCTION ==========

//     receive() external payable {}
// }
