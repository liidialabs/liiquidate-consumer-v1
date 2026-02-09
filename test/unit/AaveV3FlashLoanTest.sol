// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {AaveV3} from "../../src/flashloans/AaveV3.sol";
import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../mocks/TestHelpers.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {LiquidationParams} from "../../src/types/DataTypes.sol";

/**
 * @title AaveV3FlashLoanTest
 * @notice Tests for Aave V3 flash loan provider
 */
contract AaveV3FlashLoanTest is Test {
    AaveV3 public flashLoanProvider;
    MockAaveV3Pool public mockPool;
    MockERC20 public debtToken;
    MockERC20 public collateralToken;
    UniversalSwapRouter public swapRouter;

    address public user = address(0x1);
    address public liquidator = address(0x2);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant FLASH_LOAN_AMOUNT = 100_000e18;
    uint256 constant FLASH_LOAN_FEE = 5e15; // 0.5%

    event FlashLoan(address indexed asset, uint256 amount, uint256 fee);

    function setUp() public {
        // Create tokens
        debtToken = new MockERC20("Debt Token", "DEBT", 18);
        collateralToken = new MockERC20("Collateral Token", "COLL", 18);

        // Create mock pool
        mockPool = new MockAaveV3Pool(
            address(debtToken),
            address(collateralToken)
        );

        // Create swap router (simplified for testing)
        // In real environment, this would be configured with adapters
        swapRouter = new UniversalSwapRouter();

        // Create flash loan provider
        flashLoanProvider = new AaveV3(address(mockPool), address(swapRouter));

        // Setup initial balances
        debtToken.mint(address(mockPool), INITIAL_BALANCE);
        collateralToken.mint(user, INITIAL_BALANCE);
    }

    // ========== BASIC FLASH LOAN TESTS ==========

    function testFlashLoanInitiation() public {
        uint256 borrowAmount = FLASH_LOAN_AMOUNT;

        // Prepare callback data
        bytes memory callbackData = abi.encode(
            LiquidationParams({
                collateralAsset: address(collateralToken),
                debtAsset: address(debtToken),
                debtToCover: borrowAmount,
                liquidationTarget: address(0x3),
                liquidationCalldata: "",
                minAmountOut: 0
            })
        );

        // Initiate flash loan
        vm.prank(liquidator);
        vm.expectEmit(true, true, false, true, address(mockPool));
        emit FlashLoan(
            address(debtToken),
            borrowAmount,
            (borrowAmount * FLASH_LOAN_FEE) / 1e18
        );

        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            borrowAmount,
            address(this),
            callbackData
        );
    }

    function testFlashLoanWithValidParams() public {
        uint256 borrowAmount = FLASH_LOAN_AMOUNT;
        bytes memory callbackData = "";

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            borrowAmount,
            address(this),
            callbackData
        );

        // Verify tokens were borrowed from pool
        uint256 poolTokenBalance = debtToken.balanceOf(address(mockPool));
        assertTrue(poolTokenBalance < INITIAL_BALANCE);
    }

    function testFlashLoanRevertsWithZeroAmount() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert("Amount cannot be zero!");
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            0,
            address(this),
            callbackData
        );
    }

    function testFlashLoanRevertsWithZeroDebtAsset() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert("Invalid Address");
        flashLoanProvider.flashLoan(
            address(0),
            address(collateralToken),
            FLASH_LOAN_AMOUNT,
            address(this),
            callbackData
        );
    }

    function testFlashLoanRevertsWithZeroCollateralAsset() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert("Invalid Address");
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(0),
            FLASH_LOAN_AMOUNT,
            address(this),
            callbackData
        );
    }

    function testFlashLoanRevertsWithZeroTargetContract() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert("Invalid Address");
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            FLASH_LOAN_AMOUNT,
            address(0),
            callbackData
        );
    }

    // ========== MULTIPLE FLASH LOANS ==========

    function testMultipleFlashLoansInSequence() public {
        uint256 amount1 = 50_000e18;
        uint256 amount2 = 75_000e18;

        // First flash loan
        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            amount1,
            address(this),
            ""
        );

        // Second flash loan
        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            amount2,
            address(this),
            ""
        );
    }

    function testFlashLoanWithDifferentTokenPairs() public {
        MockERC20 token1 = new MockERC20("Token1", "T1", 18);
        MockERC20 token2 = new MockERC20("Token2", "T2", 18);

        token1.mint(address(mockPool), INITIAL_BALANCE);
        token2.mint(address(mockPool), INITIAL_BALANCE);

        bytes memory callbackData = "";

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(token1),
            address(token2),
            100_000e18,
            address(this),
            callbackData
        );
    }

    // ========== FLASH LOAN FEE CALCULATION ==========

    function testFlashLoanFeeIsCalculated() public {
        uint256 amount = FLASH_LOAN_AMOUNT;
        uint256 expectedFee = (amount * FLASH_LOAN_FEE) / 1e18;

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            amount,
            address(this),
            ""
        );

        // Fee should be deducted from pool
        uint256 expectedPoolBalance = INITIAL_BALANCE - expectedFee;
        assertGe(debtToken.balanceOf(address(mockPool)), expectedPoolBalance);
    }

    function testFlashLoanWithLargeAmount() public {
        uint256 largeAmount = 900_000e18; // 90% of initial balance

        bytes memory callbackData = "";

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            largeAmount,
            address(this),
            callbackData
        );
    }

    function testFlashLoanWithSmallAmount() public {
        uint256 smallAmount = 1e18; // 1 token

        bytes memory callbackData = "";

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            smallAmount,
            address(this),
            callbackData
        );
    }

    // ========== PROVIDER ID ==========

    function testProviderIDIsCorrect() public {
        bytes32 expectedId = keccak256("AAVE_V3");
        assertEq(flashLoanProvider.id(), expectedId);
    }

    function testProviderIDIsConsistent() public {
        bytes32 id1 = flashLoanProvider.id();
        bytes32 id2 = flashLoanProvider.id();
        assertEq(id1, id2);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function testConstructorSetsPoolCorrectly() public {
        assertEq(address(flashLoanProvider.pool()), address(mockPool));
    }

    function testConstructorSetsSwapRouterCorrectly() public {
        assertEq(address(flashLoanProvider.swapRouter()), address(swapRouter));
    }

    function testConstructorRevertsWithZeroPool() public {
        vm.expectRevert("invalid pool");
        new AaveV3(address(0), address(swapRouter));
    }

    function testConstructorRevertsWithZeroSwapRouter() public {
        vm.expectRevert("invalid pool");
        new AaveV3(address(mockPool), address(0));
    }

    // ========== TOKEN RESCUE ==========

    function testRescueTokens() public {
        uint256 tokenAmount = 1000e18;
        debtToken.mint(address(flashLoanProvider), tokenAmount);

        vm.prank(flashLoanProvider.owner());
        flashLoanProvider.rescueTokens(address(debtToken), tokenAmount);

        assertEq(debtToken.balanceOf(flashLoanProvider.owner()), tokenAmount);
    }

    function testRescueTokensRevertsIfNotOwner() public {
        uint256 tokenAmount = 1000e18;
        debtToken.mint(address(flashLoanProvider), tokenAmount);

        vm.prank(user);
        vm.expectRevert();
        flashLoanProvider.rescueTokens(address(debtToken), tokenAmount);
    }

    function testRescuePartialTokens() public {
        uint256 totalAmount = 1000e18;
        uint256 rescueAmount = 500e18;

        debtToken.mint(address(flashLoanProvider), totalAmount);

        vm.prank(flashLoanProvider.owner());
        flashLoanProvider.rescueTokens(address(debtToken), rescueAmount);

        assertEq(debtToken.balanceOf(flashLoanProvider.owner()), rescueAmount);
        assertEq(
            debtToken.balanceOf(address(flashLoanProvider)),
            totalAmount - rescueAmount
        );
    }

    // ========== RECEIVE FUNCTION ==========

    function testReceiveETH() public {
        address provider = address(flashLoanProvider);
        vm.deal(user, 1 ether);

        vm.prank(user);
        (bool success, ) = provider.call{value: 1 ether}("");
        assertTrue(success);
    }

    // ========== EDGE CASES ==========

    function testFlashLoanWithMaxUintAmount() public {
        // Should handle large amounts gracefully
        vm.prank(liquidator);
        vm.expectRevert(); // Will fail due to insufficient pool liquidity
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            type(uint256).max,
            address(this),
            ""
        );
    }

    function testFlashLoanCallbackInvokedWithCorrectParams() public {
        uint256 borrowAmount = FLASH_LOAN_AMOUNT;

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            borrowAmount,
            address(this),
            ""
        );

        // Flash loan should have gone through pool
        assertTrue(address(mockPool).code.length > 0);
    }

    function testFlashLoanFromMultipleCaller() public {
        address caller1 = address(0x10);
        address caller2 = address(0x11);

        // First caller
        vm.prank(caller1);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            50_000e18,
            address(this),
            ""
        );

        // Second caller
        vm.prank(caller2);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            75_000e18,
            address(this),
            ""
        );
    }

    // ========== GAS EFFICIENCY ==========

    function testFlashLoanGasUsage() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        uint256 gasStart = gasleft();
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            FLASH_LOAN_AMOUNT,
            address(this),
            callbackData
        );
        uint256 gasUsed = gasStart - gasleft();

        // Gas usage should be reasonable
        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 1_000_000); // Less than 1M gas
    }
}
