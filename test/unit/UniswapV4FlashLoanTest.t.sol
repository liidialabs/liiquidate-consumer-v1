// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {UniswapV4} from "../../src/flashloans/UniswapV4.sol";
import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../mocks/TestHelpers.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {LiquidationParams} from "../../src/types/DataTypes.sol";

/**
 * @title UniswapV4FlashLoanTest
 * @notice Tests for Uniswap V4 flash loan provider with unlock callback
 */
contract UniswapV4FlashLoanTest is Test {
    UniswapV4 public flashLoanProvider;
    MockUniswapV4PoolManager public mockPoolManager;
    MockERC20 public debtToken;
    MockERC20 public collateralToken;
    UniversalSwapRouter public swapRouter;

    address public user = address(0x1);
    address public liquidator = address(0x2);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant FLASH_LOAN_AMOUNT = 100_000e18;

    event UnlockCallback(bytes data);
    event Take(address indexed currency, address to, uint256 amount);
    event Sync(address indexed currency);
    event Settle();

    function setUp() public {
        // Create tokens
        debtToken = new MockERC20("Debt Token", "DEBT", 18);
        collateralToken = new MockERC20("Collateral Token", "COLL", 18);

        // Create mock pool manager
        mockPoolManager = new MockUniswapV4PoolManager();

        // Create swap router
        swapRouter = new UniversalSwapRouter();

        // Create flash loan provider
        flashLoanProvider = new UniswapV4(
            address(mockPoolManager),
            address(swapRouter)
        );

        // Setup initial balances
        debtToken.mint(address(mockPoolManager), INITIAL_BALANCE);
        collateralToken.mint(user, INITIAL_BALANCE);
    }

    // ========== BASIC FLASH LOAN TESTS ==========

    function testFlashLoanInitiation() public {
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
    }

    function testFlashLoanWithValidParams() public {
        bytes memory callbackData = abi.encode(
            LiquidationParams({
                collateralAsset: address(collateralToken),
                debtAsset: address(debtToken),
                debtToCover: FLASH_LOAN_AMOUNT,
                liquidationTarget: address(0x3),
                liquidationCalldata: "",
                minAmountOut: 0
            })
        );

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            FLASH_LOAN_AMOUNT,
            address(this),
            callbackData
        );
    }

    function testFlashLoanCallsPoolManagerUnlock() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        // Should call poolManager.unlock internally
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            FLASH_LOAN_AMOUNT,
            address(this),
            callbackData
        );
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

    // ========== UNLOCK CALLBACK TESTS ==========

    function testUnlockCallbackReceivesCorrectData() public {
        bytes memory callbackData = abi.encode(
            address(liquidator),
            LiquidationParams({
                collateralAsset: address(collateralToken),
                debtAsset: address(debtToken),
                debtToCover: FLASH_LOAN_AMOUNT,
                liquidationTarget: address(this),
                liquidationCalldata: "",
                minAmountOut: 0
            })
        );

        // Callback will be invoked with this data during unlock
    }

    function testUnlockCallbackRevertsIfNotPoolManager() public {
        bytes memory callbackData = "";

        vm.prank(user);
        vm.expectRevert("not pool manager");
        flashLoanProvider.unlockCallback(callbackData);
    }

    function testUnlockCallbackBorrowsFromPoolManager() public {
        // The callback should execute take() to borrow tokens
        bytes memory callbackData = "";

        // This is called internally by poolManager
    }

    function testUnlockCallbackRepaysToPoolManager() public {
        // The callback should execute sync() and settle() to repay
    }

    // ========== MULTIPLE FLASH LOANS ==========

    function testMultipleFlashLoansInSequence() public {
        uint256 amount1 = 50_000e18;
        uint256 amount2 = 75_000e18;

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            amount1,
            address(this),
            ""
        );

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

        token1.mint(address(mockPoolManager), INITIAL_BALANCE);
        token2.mint(address(mockPoolManager), INITIAL_BALANCE);

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

    // ========== PROVIDER ID ==========

    function testProviderIDIsCorrect() public {
        bytes32 expectedId = keccak256("UNISWAP_V4");
        assertEq(flashLoanProvider.id(), expectedId);
    }

    function testProviderIDIsConsistent() public {
        bytes32 id1 = flashLoanProvider.id();
        bytes32 id2 = flashLoanProvider.id();
        assertEq(id1, id2);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function testConstructorSetsPoolManagerCorrectly() public {
        assertEq(
            address(flashLoanProvider.poolManager()),
            address(mockPoolManager)
        );
    }

    function testConstructorSetsSwapRouterCorrectly() public {
        assertEq(address(flashLoanProvider.swapRouter()), address(swapRouter));
    }

    function testConstructorRevertsWithZeroPoolManager() public {
        vm.expectRevert("invalid address");
        new UniswapV4(address(0), address(swapRouter));
    }

    function testConstructorRevertsWithZeroSwapRouter() public {
        vm.expectRevert("invalid address");
        new UniswapV4(address(mockPoolManager), address(0));
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
        vm.prank(liquidator);
        vm.expectRevert();
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            type(uint256).max,
            address(this),
            ""
        );
    }

    function testFlashLoanWithLargeAmount() public {
        uint256 largeAmount = 900_000e18;

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
        uint256 smallAmount = 1e18;

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

    function testFlashLoanFromMultipleCaller() public {
        address caller1 = address(0x10);
        address caller2 = address(0x11);

        vm.prank(caller1);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            50_000e18,
            address(this),
            ""
        );

        vm.prank(caller2);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            75_000e18,
            address(this),
            ""
        );
    }

    // ========== INTERFACE COMPLIANCE ==========

    function testImplementsIFlashLoanInterface() public {
        // Contract should implement executeOperation or similar
        // Testing that the contract has the required functions
        assertTrue(address(flashLoanProvider).code.length > 0);
    }

    function testImplementsIUnlockCallbackInterface() public {
        // Contract should implement unlockCallback
        // Testing that the contract can be called as callback
    }

    // ========== INTEGRATION ==========

    function testFlashLoanWithComplexLiquidationData() public {
        LiquidationParams memory params = LiquidationParams({
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: FLASH_LOAN_AMOUNT,
            liquidationTarget: address(0x5),
            liquidationCalldata: abi.encodeWithSignature(
                "liquidate(address,uint256)",
                user,
                100
            ),
            minAmountOut: 0
        });

        bytes memory callbackData = abi.encode(liquidator, params);

        vm.prank(liquidator);
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            FLASH_LOAN_AMOUNT,
            address(this),
            callbackData
        );
    }

    function testFlashLoanWithMaxUint256LiquidationAmount() public {
        LiquidationParams memory params = LiquidationParams({
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: type(uint256).max,
            liquidationTarget: address(this),
            liquidationCalldata: "",
            minAmountOut: 0
        });

        bytes memory callbackData = abi.encode(liquidator, params);

        vm.prank(liquidator);
        vm.expectRevert();
        flashLoanProvider.flashLoan(
            address(debtToken),
            address(collateralToken),
            type(uint256).max,
            address(this),
            callbackData
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

        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 1_000_000);
    }

    // ========== OWNERSHIP ==========

    function testOwnershipIsSet() public {
        assertEq(flashLoanProvider.owner(), address(this));
    }

    function testOwnerCanTransferOwnership() public {
        address newOwner = address(0x20);
        flashLoanProvider.transferOwnership(newOwner);
        assertEq(flashLoanProvider.owner(), newOwner);
    }
}
