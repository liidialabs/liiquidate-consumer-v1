// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV4} from "../../src/flashloans/UniswapV4.sol";
import {UniswapV4Adapter} from "../../src/swappers/UniswapV4Adapter.sol";
import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
import {MockDebtManager} from "../mocks/MockDebtManager.sol";
import {MockDebtManagerAdapter} from "../mocks/MockDebtManagerAdapter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {LiquidationParams} from "../../src/types/DataTypes.sol";
import { ILiquidationAdapter } from "../../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolIdLibrary, PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MIN_SQRT_PRICE} from "../../src/types/Constants.sol";
import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";

/**
 * @title UniswapV4FlashLoanTest
 * @notice Tests for Uniswap V4 flash loan provider with unlock callback
 */
contract UniswapV4FlashLoanTest is Test {
    using PoolIdLibrary for PoolKey;

    UniswapV4 public uniswapV4;
    UniswapV4Adapter public uniswapV4Adapter;
    MockUniswapV4PoolManager public mockPoolManager;
    MockERC20 public debtToken;
    MockERC20 public collateralToken;
    // MockERC20 public tokenDebt;
    // MockERC20 public tokenVia;
    // MockERC20 public tokenColl;
    UniversalSwapRouter public swapRouter;
    MockDebtManager public debtManager;
    MockDebtManagerAdapter public debtManagerAdapter;

    address public user = address(0x1);
    address public user2 = address(0x2);
    address public liquidator = address(0x3);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant DEBT_TO_COVER = 700e18;
    uint256 constant POOL_FEE = 3000; // 0.3%

    event UnlockCallback(bytes data);
    event Take(address indexed currency, address to, uint256 amount);
    event Sync(address indexed currency);
    event Settle();

    function setUp() public {
        // Create tokens
        debtToken = new MockERC20("Debt Token", "DEBT", 18);
        collateralToken = new MockERC20("Collateral Token", "COLL", 18);

        // tokenDebt = new MockERC20("TokenA", "TokenA", 6);
        // tokenVia = new MockERC20("TokenB", "TokenB", 18);
        // tokenColl = new MockERC20("TokenC", "TokenC", 18);

        // Create mock pool manager
        mockPoolManager = new MockUniswapV4PoolManager();

        /////////////// DEBTMANAGER ////////////////

        // Create mock debtManager & debtManagerAdapter
        debtManager = new MockDebtManager();
        debtManagerAdapter = new MockDebtManagerAdapter(
            address(debtManager),
            "DebtManager1"
        );

        // 
        debtToken.mint(address(debtManager), 1_000_000e18);
        collateralToken.mint(address(debtManager), 1_000_000e18);

        // Configure collateral
        // 10% liquidation bonus, 80% liquidation threshold
        debtManager.configureCollateral(
            address(collateralToken),
            0.1e18,  // 10% bonus for liquidators
            0.8e18   // 80% LTV threshold
        );
        
        // Configure debt asset
        debtManager.configureDebtAsset(
            address(debtToken),
            0.05e18,      // 5% annual rate
            1000000e18    // Max borrow
        );
        
        // Set initial prices
        // WETH = $2000, USDC = $1
        debtManager.setAssetPrice(address(collateralToken), 2000e8);
        debtManager.setAssetPrice(address(debtToken), 1e8);

        // Setup user account
        // User deposits 1 WETH ($2000) as collateral
        // User borrows 1200 USDC ($1200) - this is 60% LTV initially (healthy)
        debtManager.setupUserAccount(
            user,
            address(collateralToken),
            1e18,      // 1 WETH - collateral
            address(debtToken),
            1200e18    // 1200 USDC - debt
        );

        debtManager.setupUserAccount(
            user2,
            address(collateralToken),
            1e18,      // 1 WETH - collateral
            address(debtToken),
            1200e18    // 1200 USDC - debt
        );

        // Make position liquidatable by dropping WETH price
        // New WETH price = $1400
        // Collateral value = $1400
        // Health Factor = (1400 * 0.8) / 1200 = 0.933 < 1.0 (LIQUIDATABLE!)
        // debtManager.setAssetPrice(WETH, 1400e8);

        // Update the user's account with new price
        // debtManager.updateUserCollateral(user, WETH, 1e18);

        ///////////////////////////////////////////////

        // Create swap router
        swapRouter = new UniversalSwapRouter();

        // Create swap adapter
        uniswapV4Adapter = new UniswapV4Adapter(
            address(mockPoolManager)
        );

        // register adapter and add to priority queu
        swapRouter.registerAdapter(address(uniswapV4Adapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = uniswapV4Adapter.protocolId();
        swapRouter.setProtocolPriority(protocols);

        _createPoolKeys();

        // Create flash loan provider
        uniswapV4 = new UniswapV4(
            address(mockPoolManager),
            address(swapRouter)
        );

        // Setup initial balances
        debtToken.mint(address(mockPoolManager), 1_000_000e18);
        collateralToken.mint(address(mockPoolManager), 1_000_000e18);
    }

    // ========== HELPER ============

    function _createPoolKeys() internal {
        // 1. Setup token path
        address[] memory path = new address[](2);
        path[0] = address(collateralToken);
        path[1] = address(debtToken);

        // 2. Create PoolKey for the tokenA/tokenB pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(collateralToken)),
            currency1: Currency.wrap(address(debtToken)),
            fee: uint24(POOL_FEE),
            tickSpacing: 60,  // Adjust based on your fee tier
            hooks: IHooks(address(0))  // No hooks, or use your hooks address
        });

        // 3. Encode the PoolKey (not the pool manager address)
        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(poolKey);

        // 4. Setup fees array
        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        // 5. Initialize the pool in the mock (so sqrtPriceX96 != 0)
        uint160 sqrtPriceX96 = 2967187660000000000000000000000;
        mockPoolManager.initialize(
            poolKey,
            sqrtPriceX96,  // Or your desired initial price
            1000e18
        );

        // 6. Register the swap path
        uniswapV4Adapter.registerSwapPath(
            address(collateralToken),
            address(debtToken),
            path,
            poolData,
            fees
        );

        // 7. Get and verify the swap path
        ISwapAdapter.SwapPath memory swapPath = uniswapV4Adapter.getSwapPath(
            address(collateralToken),
            address(debtToken)
        );

        // Assertions
        assertEq(swapPath.tokens.length, 2, "Should have 2 tokens");
        assertEq(swapPath.poolData.length, 1, "Should have 1 pool");
        assertEq(swapPath.fees.length, 1, "Should have 1 fee");
        assertEq(swapPath.tokens[0], address(collateralToken), "First token should be tokenA");
        assertEq(swapPath.tokens[1], address(debtToken), "Second token should be tokenB");
        
        assertTrue(uniswapV4Adapter.isPathSupported(swapPath), "Path should be supported");        
    }

    function _liquidateUserGetPayload(address _user) 
    internal returns(ILiquidationAdapter.ExecutionPayload memory payload) {
        debtManager.setAssetPrice(address(collateralToken), 1400e8);
        debtManager.updateUserCollateral(_user, address(collateralToken), 1e18);

        payload  = debtManagerAdapter.buildExecutionPayload(
            _user, 
            DEBT_TO_COVER, 
            address(debtToken), 
            address(collateralToken)
        );
    }

    // ========== QUOTE ===========

    function testQuote() public {
        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: address(collateralToken),
                tokenOut: address(debtToken),
                amountIn: 0.55e18,
                amountOut: 0,
                minAmountOut: 700e18,
                maxAmountIn: 0,
                recipient: address(this),
                deadline: block.timestamp + 1000,
                isExactInput: true
            });
        
        (, uint256 amountOut) = uniswapV4Adapter.quoteMultiHop(params);

        console.log("AmountOut: ", amountOut);
        assertLt(700e18, amountOut);
    }

    function test_debugStorageSlots() public view {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(collateralToken)),
            currency1: Currency.wrap(address(debtToken)),
            fee: uint24(POOL_FEE),
            tickSpacing: 60,  // Adjust based on your fee tier
            hooks: IHooks(address(0))  // No hooks, or use your hooks address
        });

        PoolId poolId = poolKey.toId();
        
        // Check what's in the pools mapping
        (uint160 price, int24 tick, uint128 liquidity) = mockPoolManager.getPoolState(poolKey);
        console.log("From getPoolState:");
        console.log("  sqrtPriceX96:", price);
        console.log("  tick:", uint256(int256(tick)));
        console.log("  liquidity:", liquidity);
        
        // Check what extsload returns
        bytes32 baseSlot = keccak256(abi.encode(poolId, 6)); // POOLS_SLOT = 6
        console.log("Base slot:", uint256(baseSlot));
        
        bytes32 slot0Data = mockPoolManager.extsload(baseSlot);
        console.log("Slot 0 data:", uint256(slot0Data));
        
        bytes32 liquiditySlot = bytes32(uint256(baseSlot) + 1);
        bytes32 liquidityData = mockPoolManager.extsload(liquiditySlot);
        console.log("Liquidity slot data:", uint256(liquidityData));
        
        // Try using getLiquidity if it exists
        uint128 liquidityFromGetter = mockPoolManager.getLiquidity(poolId);
        console.log("From getLiquidity:", liquidityFromGetter);
    }

    // ========== BASIC FLASH LOAN TESTS ==========

    function testFlashLoanInitiation() public {
        ILiquidationAdapter.ExecutionPayload memory payload  = _liquidateUserGetPayload(user);

        assertEq(debtToken.balanceOf(liquidator), 0);

        vm.prank(liquidator);
        uniswapV4.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload.target,
            payload.callData
        );

        assertGt(debtToken.balanceOf(liquidator), 69e18);
    }

    function testFlashLoanRevertsWithZeroAmount() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert();
        uniswapV4.flashLoan(
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
        vm.expectRevert();
        uniswapV4.flashLoan(
            address(0),
            address(collateralToken),
            DEBT_TO_COVER,
            address(this),
            callbackData
        );
    }

    function testFlashLoanRevertsWithZeroCollateralAsset() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert();
        uniswapV4.flashLoan(
            address(debtToken),
            address(0),
            DEBT_TO_COVER,
            address(this),
            callbackData
        );
    }

    function testFlashLoanRevertsWithZeroTargetContract() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert();
        uniswapV4.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            address(0),
            callbackData
        );
    }

    // ========== UNLOCK CALLBACK TESTS ==========

    function testUnlockCallbackRevertsIfNotPoolManager() public {
        bytes memory callbackData = "";

        vm.prank(user);
        vm.expectRevert();
        uniswapV4.unlockCallback(callbackData);
    }

    // ========== MULTIPLE FLASH LOANS ==========

    function testMultipleFlashLoansInSequence() public {
        ILiquidationAdapter.ExecutionPayload memory payload1  = _liquidateUserGetPayload(user);
        ILiquidationAdapter.ExecutionPayload memory payload2  = _liquidateUserGetPayload(user2);

        vm.prank(liquidator);
        uniswapV4.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload1.target,
            payload1.callData
        );

        vm.prank(liquidator);
        uniswapV4.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload2.target,
            payload2.callData
        );
    }

    // ========== PROVIDER ID ==========

    function testProviderIDIsCorrect() public view {
        bytes32 expectedId = keccak256("UNISWAP_V4");
        assertEq(uniswapV4.id(), expectedId);
    }

    function testProviderIDIsConsistent() public view {
        bytes32 id1 = uniswapV4.id();
        bytes32 id2 = uniswapV4.id();
        assertEq(id1, id2);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function testConstructorSetsPoolManagerCorrectly() public view {
        assertEq(
            address(uniswapV4.poolManager()),
            address(mockPoolManager)
        );
    }

    function testConstructorSetsSwapRouterCorrectly() public view {
        assertEq(address(uniswapV4.swapRouter()), address(swapRouter));
    }

    function testConstructorRevertsWithZeroPoolManager() public {
        vm.expectRevert();
        new UniswapV4(address(0), address(swapRouter));
    }

    function testConstructorRevertsWithZeroSwapRouter() public {
        vm.expectRevert();
        new UniswapV4(address(mockPoolManager), address(0));
    }

    // ========== TOKEN RESCUE ==========

    function testRescueTokens() public {
        uint256 tokenAmount = 1000e18;
        debtToken.mint(address(uniswapV4), tokenAmount);

        vm.prank(uniswapV4.owner());
        uniswapV4.rescueTokens(address(debtToken), tokenAmount);

        assertEq(debtToken.balanceOf(uniswapV4.owner()), tokenAmount);
    }

    function testRescueTokensRevertsIfNotOwner() public {
        uint256 tokenAmount = 1000e18;
        debtToken.mint(address(uniswapV4), tokenAmount);

        vm.prank(user);
        vm.expectRevert();
        uniswapV4.rescueTokens(address(debtToken), tokenAmount);
    }

    function testRescuePartialTokens() public {
        uint256 totalAmount = 1000e18;
        uint256 rescueAmount = 500e18;

        debtToken.mint(address(uniswapV4), totalAmount);

        vm.prank(uniswapV4.owner());
        uniswapV4.rescueTokens(address(debtToken), rescueAmount);

        assertEq(debtToken.balanceOf(uniswapV4.owner()), rescueAmount);
        assertEq(
            debtToken.balanceOf(address(uniswapV4)),
            totalAmount - rescueAmount
        );
    }

    // ========== RECEIVE FUNCTION ==========

    function testReceiveETH() public {
        address provider = address(uniswapV4);
        vm.deal(user, 1 ether);

        vm.prank(user);
        (bool success, ) = provider.call{value: 1 ether}("");
        assertTrue(success);
    }

    // ========== GAS EFFICIENCY ==========

    function testFlashLoanGasUsage() public {
        ILiquidationAdapter.ExecutionPayload memory payload  = _liquidateUserGetPayload(user);

        vm.prank(liquidator);
        uint256 gasStart = gasleft();
        uniswapV4.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload.target,
            payload.callData
        );
        uint256 gasUsed = gasStart - gasleft();

        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 1_000_000);
    }

    // ========== OWNERSHIP ==========

    function testOwnershipIsSet() public {
        assertEq(uniswapV4.owner(), address(this));
    }

    function testOwnerCanTransferOwnership() public {
        address newOwner = address(0x20);
        uniswapV4.transferOwnership(newOwner);
        assertEq(uniswapV4.owner(), newOwner);
    }
}
