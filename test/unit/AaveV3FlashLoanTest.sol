// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AaveV3} from "../../src/flashloans/AaveV3.sol";
import {UniswapV4Adapter} from "../../src/swappers/UniswapV4Adapter.sol";
import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {LiquidationParams} from "../../src/types/DataTypes.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolIdLibrary, PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MIN_SQRT_PRICE} from "../../src/types/Constants.sol";
import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";
import { ILiquidationAdapter } from "../../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {MockDebtManager} from "../mocks/MockDebtManager.sol";
import {MockDebtManagerAdapter} from "../mocks/MockDebtManagerAdapter.sol";
import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";

/**
 * @title AaveV3FlashLoanTest
 * @notice Tests for Aave V3 flash loan provider
 */
contract AaveV3FlashLoanTest is Test {
    using PoolIdLibrary for PoolKey;

    AaveV3 public aaveV3;
    UniswapV4Adapter public uniswapV4Adapter;
    MockAaveV3Pool public mockPool;
    MockERC20 public debtToken;
    MockERC20 public collateralToken;
    UniversalSwapRouter public swapRouter;
    MockDebtManager public debtManager;
    MockDebtManagerAdapter public debtManagerAdapter;
    MockUniswapV4PoolManager public mockPoolManager;

    address public user = address(0x1);
    address public user2 = address(0x2);
    address public liquidator = address(0x3);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant POOL_FEE = 3000; // 0.5%
    uint256 constant DEBT_TO_COVER = 700e18;

    event FlashLoan(address indexed asset, uint256 amount, uint256 fee);

    function setUp() public {
        // Create tokens
        debtToken = new MockERC20("Debt Token", "DEBT", 18);
        collateralToken = new MockERC20("Collateral Token", "COLL", 18);

        // Create mock pool then add assets
        mockPool = new MockAaveV3Pool();
        
        mockPool.setAssetSupported(address(debtToken), true);
        mockPool.setAssetReservement(address(debtToken), 1_000_000e18);
        debtToken.mint(address(mockPool), 1_000_000e18);

        mockPool.setAssetSupported(address(collateralToken), true);
        mockPool.setAssetReservement(address(collateralToken), INITIAL_BALANCE);
        collateralToken.mint(address(mockPool), INITIAL_BALANCE);

        // Create swap router (simplified for testing)
        // In real environment, this would be configured with adapters
        swapRouter = new UniversalSwapRouter();

        // Create mock uniswap v4 pool manager
        mockPoolManager = new MockUniswapV4PoolManager();

        // Create swap adapter
        uniswapV4Adapter = new UniswapV4Adapter(
            address(mockPoolManager)
        );

        _createPoolKeys();

        // register adapter and add to priority queu
        swapRouter.registerAdapter(address(uniswapV4Adapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = uniswapV4Adapter.protocolId();
        swapRouter.setProtocolPriority(protocols);

        // Create flash loan provider
        aaveV3 = new AaveV3(address(mockPool), address(swapRouter));

        // Setup initial balances
        debtToken.mint(address(mockPool), 1_000_000e18);
        collateralToken.mint(address(mockPool), INITIAL_BALANCE);
        collateralToken.mint(user, INITIAL_BALANCE);

        /////////////// DEBTMANAGER ////////////////

        // Create mock debtManager & debtManagerAdapter
        debtManager = new MockDebtManager();
        debtManagerAdapter = new MockDebtManagerAdapter(
            address(debtManager),
            "AaveV3_Test_Adapter"
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

        ///////////////////////////////////////////////

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

    function testAaveQuote() public {
        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: address(collateralToken),
                tokenOut: address(debtToken),
                amountIn: 0.55e18,
                amountOut: 0,
                minAmountOut: 750e18,
                maxAmountIn: 0,
                recipient: address(this),
                deadline: block.timestamp + 1000,
                isExactInput: true
            });
        
        (, uint256 amountOut) = uniswapV4Adapter.quoteMultiHop(params);

        console.log("AmountOut: ", amountOut);
        assertLt(750e18, amountOut);
    }    

    // ========== BASIC FLASH LOAN TESTS ==========

    function testAaveFlashLoanInitiation() public {
        ILiquidationAdapter.ExecutionPayload memory payload  = _liquidateUserGetPayload(user);

        assertEq(debtToken.balanceOf(liquidator), 0);

        vm.prank(liquidator);
        aaveV3.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload.target,
            payload.callData
        );

        // assertGt(debtToken.balanceOf(liquidator), 0);

        console.log("Liquidator Balance: ", debtToken.balanceOf(liquidator));
    }

    function testFlashLoanRevertsWithZeroAmount() public {
        bytes memory callbackData = "";

        vm.prank(liquidator);
        vm.expectRevert();
        aaveV3.flashLoan(
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
        vm.expectRevert(AaveV3.InvalidAddress.selector);
        aaveV3.flashLoan(
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
        vm.expectRevert(AaveV3.InvalidAddress.selector);
        aaveV3.flashLoan(
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
        vm.expectRevert(AaveV3.InvalidAddress.selector);
        aaveV3.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            address(0),
            callbackData
        );
    }

    // ========== MULTIPLE FLASH LOANS ==========

    function testMultipleFlashLoansInSequence() public {
        ILiquidationAdapter.ExecutionPayload memory payload1  = _liquidateUserGetPayload(user);
        ILiquidationAdapter.ExecutionPayload memory payload2  = _liquidateUserGetPayload(user2);

        // First flash loan
        vm.prank(liquidator);
        aaveV3.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload1.target,
            payload1.callData
        );

        // Second flash loan
        vm.prank(liquidator);
        aaveV3.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload2.target,
            payload2.callData
        );
    }

    // ========== PROVIDER ID ==========

    function testProviderIDIsCorrect() public {
        bytes32 expectedId = keccak256("AAVE_V3");
        assertEq(aaveV3.id(), expectedId);
    }

    function testProviderIDIsConsistent() public {
        bytes32 id1 = aaveV3.id();
        bytes32 id2 = aaveV3.id();
        assertEq(id1, id2);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function testConstructorSetsPoolCorrectly() public {
        assertEq(address(aaveV3.pool()), address(mockPool));
    }

    function testConstructorSetsSwapRouterCorrectly() public {
        assertEq(address(aaveV3.swapRouter()), address(swapRouter));
    }

    function testConstructorRevertsWithZeroPool() public {
        vm.expectRevert();
        new AaveV3(address(0), address(swapRouter));
    }

    function testConstructorRevertsWithZeroSwapRouter() public {
        vm.expectRevert();
        new AaveV3(address(mockPool), address(0));
    }

    // ========== TOKEN RESCUE ==========

    function testRescueTokens() public {
        uint256 tokenAmount = 1000e18;
        debtToken.mint(address(aaveV3), tokenAmount);

        vm.prank(aaveV3.owner());
        aaveV3.rescueTokens(address(debtToken), tokenAmount);

        assertEq(debtToken.balanceOf(aaveV3.owner()), tokenAmount);
    }

    function testRescueTokensRevertsIfNotOwner() public {
        uint256 tokenAmount = 1000e18;
        debtToken.mint(address(aaveV3), tokenAmount);

        vm.prank(user);
        vm.expectRevert();
        aaveV3.rescueTokens(address(debtToken), tokenAmount);
    }

    function testRescuePartialTokens() public {
        uint256 totalAmount = 1000e18;
        uint256 rescueAmount = 500e18;

        debtToken.mint(address(aaveV3), totalAmount);

        vm.prank(aaveV3.owner());
        aaveV3.rescueTokens(address(debtToken), rescueAmount);

        assertEq(debtToken.balanceOf(aaveV3.owner()), rescueAmount);
        assertEq(
            debtToken.balanceOf(address(aaveV3)),
            totalAmount - rescueAmount
        );
    }

    // ========== RECEIVE FUNCTION ==========

    function testReceiveETH() public {
        address provider = address(aaveV3);
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
        aaveV3.flashLoan(
            address(debtToken),
            address(collateralToken),
            DEBT_TO_COVER,
            payload.target,
            payload.callData
        );
        uint256 gasUsed = gasStart - gasleft();

        // Gas usage should be reasonable
        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 1_000_000); // Less than 1M gas
    }
}
