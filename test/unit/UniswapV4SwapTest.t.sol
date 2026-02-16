// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {UniswapV4Adapter} from "../../src/swappers/UniswapV4Adapter.sol";
import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../mocks/TestHelpers.sol";
import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";
import {MIN_SQRT_PRICE} from "../../src/types/Constants.sol";

/**
 * @title UniswapV4SwapTest
 * @notice Tests for Uniswap V4 swap adapter
 */
contract UniswapV4SwapTest is Test {
    UniswapV4Adapter public swapAdapter;
    MockUniswapV4PoolManager public mockPoolManager;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;
    MockERC20 public tokenD;

    address public user = address(0x1);
    address public liquidator = address(0x2);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant SWAP_AMOUNT = 100_000e18;
    uint256 constant POOL_FEE = 3000; // 0.3%
    bytes32 public constant PROVIDER_ID = keccak256("AAVE_V3");

    event SwapPathRegistered(
        address indexed tokenIn,
        address indexed tokenOut,
        address[] path,
        bytes[] poolData,
        uint24[] fees
    );

    event Swap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    function setUp() public {
        // Create tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);
        tokenC = new MockERC20("Token C", "TKNC", 18);
        tokenD = new MockERC20("Token D", "TKND", 18);

        // Create pool manager
        mockPoolManager = new MockUniswapV4PoolManager();

        // Create swap adapter
        swapAdapter = new UniswapV4Adapter(address(mockPoolManager));

        // Setup initial balances
        tokenA.mint(user, INITIAL_BALANCE);
        tokenB.mint(user, 10_000e18);

        tokenA.mint(address(mockPoolManager), INITIAL_BALANCE);
        tokenB.mint(address(mockPoolManager), 100_000e18);
        tokenC.mint(address(mockPoolManager), INITIAL_BALANCE);

        _createPoolKeys();
    }

    // ========= HELPER ==============

    function _createPoolKeys() internal {
        // 1. Setup token path
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // 2. Create PoolKey for the tokenA/tokenB pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
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
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );

        // 7. Get and verify the swap path
        ISwapAdapter.SwapPath memory swapPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );

        // Assertions
        assertEq(swapPath.tokens.length, 2, "Should have 2 tokens");
        assertEq(swapPath.poolData.length, 1, "Should have 1 pool");
        assertEq(swapPath.fees.length, 1, "Should have 1 fee");
        assertEq(swapPath.tokens[0], address(tokenA), "First token should be tokenA");
        assertEq(swapPath.tokens[1], address(tokenB), "Second token should be tokenB");
        
        assertTrue(swapAdapter.isPathSupported(swapPath), "Path should be supported");        
    }

    // =========== PERFORM A SWAP =============

    function testSuccessfulSwap() public {
        ISwapAdapter.MultiHopParams memory params = ISwapAdapter.MultiHopParams({
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            amountIn: 0.55e18,
            amountOut: 0, // Not used for exactInput
            minAmountOut: 760e18, // Slippage protection
            maxAmountIn: type(uint256).max, // Not used for exactInput
            recipient: user, // Tokens received here
            deadline: block.timestamp + 300, // 5 minute deadline
            isExactInput: true // Exact input swap
        });

        uint256 balanceBefore = tokenB.balanceOf(user);

        vm.startPrank(user);
        // Approve
        tokenA.approve(address(swapAdapter), type(uint256).max);
        // Swap
        (, uint256 amountOut) = swapAdapter.swapMultiHop(
            params, 
            PROVIDER_ID
        );
        vm.stopPrank();

        assertGt(amountOut, 760e18);

        uint256 balanceAfter = tokenB.balanceOf(user);
        assertGt(balanceAfter, balanceBefore);
    }

    // ========== SWAP PATH REGISTRATION TESTS ==========

    function testRegisterSimpleSwapPath() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager)); // Placeholder pool data

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );

        // Verify path was registered
        ISwapAdapter.SwapPath memory registeredPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );
        assertEq(registeredPath.tokens.length, 2);
        assertEq(registeredPath.tokens[0], address(tokenA));
        assertEq(registeredPath.tokens[1], address(tokenB));
    }

    function testRegisterMultiHopSwapPath() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        bytes[] memory poolData = new bytes[](2);
        poolData[0] = abi.encode(address(mockPoolManager));
        poolData[1] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](2);
        fees[0] = uint24(POOL_FEE);
        fees[1] = 500; // 0.05% for second hop

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenC),
            path,
            poolData,
            fees
        );

        // Verify multi-hop path
        ISwapAdapter.SwapPath memory registeredPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenC)
        );
        assertEq(registeredPath.tokens.length, 3);
        assertEq(registeredPath.fees.length, 2);
    }

    function testRegisterSwapPathRevertsWithZeroTokenIn() public {
        address[] memory path = new address[](2);
        path[0] = address(0);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(0),
            address(tokenB),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsWithZeroTokenOut() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(0);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(0),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsWithPathTooShort() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        bytes[] memory poolData = new bytes[](0);
        uint24[] memory fees = new uint24[](0);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsWithWrongPathStart() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenB); // Wrong start token
        path[1] = address(tokenC);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenC),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsWithWrongPathEnd() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenC); // Wrong end token

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsWithPoolDataMismatch() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        bytes[] memory poolData = new bytes[](1); // Wrong count
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](2);
        fees[0] = uint24(POOL_FEE);
        fees[1] = uint24(POOL_FEE);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenC),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsWithFeesMismatch() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        bytes[] memory poolData = new bytes[](2);
        poolData[0] = abi.encode(address(mockPoolManager));
        poolData[1] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1); // Wrong count
        fees[0] = uint24(POOL_FEE);

        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenC),
            path,
            poolData,
            fees
        );
    }

    function testRegisterSwapPathRevertsIfNotOwner() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        vm.prank(user);
        vm.expectRevert();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );
    }

    // ========== PROTOCOL ID TESTS ==========

    function testProtocolIDIsCorrect() public {
        bytes32 expectedId = keccak256("UNISWAP_V4");
        assertEq(swapAdapter.protocolId(), expectedId);
    }

    function testProtocolIDIsConsistent() public {
        bytes32 id1 = swapAdapter.protocolId();
        bytes32 id2 = swapAdapter.protocolId();
        assertEq(id1, id2);
    }

    // ========== PATH SUPPORT TESTS ==========

    function testIsPathSupportedReturnsTrueForRegisteredPath() public {
        // 1. Setup token path
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenD);

        // 2. Create PoolKey for the tokenA/tokenD pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenD)),
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
        mockPoolManager.initialize(
            poolKey,
            MIN_SQRT_PRICE,  // Or your desired initial price
            100e18
        );

        // 6. Register the swap path
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenD),
            path,
            poolData,
            fees
        );

        // 7. Get and verify the swap path
        ISwapAdapter.SwapPath memory swapPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenD)
        );

        // Assertions
        assertEq(swapPath.tokens.length, 2, "Should have 2 tokens");
        assertEq(swapPath.poolData.length, 1, "Should have 1 pool");
        assertEq(swapPath.fees.length, 1, "Should have 1 fee");
        assertEq(swapPath.tokens[0], address(tokenA), "First token should be tokenA");
        assertEq(swapPath.tokens[1], address(tokenD), "Second token should be tokenD");
        
        assertTrue(swapAdapter.isPathSupported(swapPath), "Path should be supported");
    }

    function testIsPathSupportedReturnsTrueForMultiHopPath() public {
        // Path: tokenA -> tokenB -> tokenC
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenD);
        path[2] = address(tokenC);

        // Create PoolKeys for both hops
        PoolKey memory poolKey1 = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenD)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        PoolKey memory poolKey2 = PoolKey({
            currency0: Currency.wrap(address(tokenD)),
            currency1: Currency.wrap(address(tokenC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // Encode both pools
        bytes[] memory poolData = new bytes[](2);
        poolData[0] = abi.encode(poolKey1);
        poolData[1] = abi.encode(poolKey2);

        uint24[] memory fees = new uint24[](2);
        fees[0] = 3000;
        fees[1] = 3000;

        // Initialize both pools
        mockPoolManager.initialize(poolKey1, MIN_SQRT_PRICE, 100e18);
        mockPoolManager.initialize(poolKey2, MIN_SQRT_PRICE, 100e18);

        // Register path
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenC),
            path,
            poolData,
            fees
        );

        ISwapAdapter.SwapPath memory swapPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenC)
        );

        assertTrue(swapAdapter.isPathSupported(swapPath), "Multi-hop path should be supported");
    }

    function testIsPathSupportedReturnsFalseForUninitializedPool() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenC);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(poolKey);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;

        // DON'T initialize the pool - sqrtPriceX96 will be 0

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenC),
            path,
            poolData,
            fees
        );

        ISwapAdapter.SwapPath memory swapPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenC)
        );

        assertFalse(swapAdapter.isPathSupported(swapPath), "Uninitialized pool should not be supported");
    }

    function testIsPathSupportedReturnsFalseForMismatchedTokens() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);  // Wrong token!

        // Pool is tokenB/tokenC, but path says tokenA/tokenB
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(tokenB)),
            currency1: Currency.wrap(address(tokenC)),  // Mismatch
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(poolKey);

        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;

        mockPoolManager.initialize(poolKey, MIN_SQRT_PRICE, 100e18);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );

        ISwapAdapter.SwapPath memory swapPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );

        assertFalse(swapAdapter.isPathSupported(swapPath), "Mismatched tokens should not be supported");
    }

    function testIsPathSupportedReturnsFalseForInvalidArrayLengths() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Wrong: 2 pools for 2 tokens (should be 1 pool)
        bytes[] memory poolData = new bytes[](2);
        poolData[0] = abi.encode(PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        }));
        poolData[1] = abi.encode(PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        }));

        uint24[] memory fees = new uint24[](2);
        fees[0] = 3000;
        fees[1] = 3000;

        ISwapAdapter.SwapPath memory swapPath = ISwapAdapter.SwapPath({
            tokens: path,
            poolData: poolData,
            fees: fees
        });

        assertFalse(swapAdapter.isPathSupported(swapPath), "Invalid array lengths should not be supported");
    }

    function _createPoolKey(
        address token0,
        address token1,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: _getTickSpacing(fee),
            hooks: IHooks(address(0))
        });
    }

    function _getTickSpacing(uint24 fee) internal pure returns (int24) {
        if (fee == 500) return 10;
        if (fee == 3000) return 60;
        if (fee == 10000) return 200;
        return 60; // default
    }

    // ========== GET SWAP PATH TESTS ==========

    function testGetSwapPathReturnsRegisteredPath() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );

        ISwapAdapter.SwapPath memory retrievedPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );

        assertEq(retrievedPath.tokens[0], address(tokenA));
        assertEq(retrievedPath.tokens[1], address(tokenB));
        assertEq(retrievedPath.fees[0], POOL_FEE);
    }

    function testGetSwapPathReturnsEmptyPathForUnregistered() public {
        ISwapAdapter.SwapPath memory path = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenC)
        );

        assertEq(path.tokens.length, 0);
    }

    // ========== CONSTRUCTOR TESTS ==========

    function testConstructorSetsPoolManagerCorrectly() public {
        assertEq(address(swapAdapter.poolManager()), address(mockPoolManager));
    }

    function testConstructorRevertsWithZeroPoolManager() public {
        vm.expectRevert();
        new UniswapV4Adapter(address(0));
    }

    // ========== OWNERSHIP TESTS ==========

    function testOwnershipIsSet() public {
        assertEq(swapAdapter.owner(), address(this));
    }

    function testOwnerCanTransferOwnership() public {
        address newOwner = address(0x20);
        swapAdapter.transferOwnership(newOwner);
        assertEq(swapAdapter.owner(), newOwner);
    }

    function testOwnerCanRenounceOwnership() public {
        swapAdapter.renounceOwnership();
        assertEq(swapAdapter.owner(), address(0));
    }

    // ========== RECEIVE FUNCTION ==========

    function testReceiveETH() public {
        vm.deal(user, 1 ether);

        vm.prank(user);
        (bool success, ) = address(swapAdapter).call{value: 1 ether}("");
        assertTrue(success);
    }

    // ========== INTEGRATION TESTS ==========

    function testMultiplePathsCanBeRegistered() public {
        // Path 1: A -> B
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        bytes[] memory poolData1 = new bytes[](1);
        poolData1[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees1 = new uint24[](1);
        fees1[0] = uint24(POOL_FEE);

        // Path 2: B -> C
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenC);

        bytes[] memory poolData2 = new bytes[](1);
        poolData2[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees2 = new uint24[](1);
        fees2[0] = uint24(POOL_FEE);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path1,
            poolData1,
            fees1
        );

        swapAdapter.registerSwapPath(
            address(tokenB),
            address(tokenC),
            path2,
            poolData2,
            fees2
        );

        // Verify both paths
        ISwapAdapter.SwapPath memory retrievedPath1 = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );
        ISwapAdapter.SwapPath memory retrievedPath2 = swapAdapter.getSwapPath(
            address(tokenB),
            address(tokenC)
        );

        assertEq(retrievedPath1.tokens.length, 2);
        assertEq(retrievedPath2.tokens.length, 2);
    }

    function testPathCanBeOverwritten() public {
        address[] memory path1 = new address[](2);
        path1[0] = address(tokenA);
        path1[1] = address(tokenB);

        bytes[] memory poolData1 = new bytes[](1);
        poolData1[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees1 = new uint24[](1);
        fees1[0] = uint24(POOL_FEE);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path1,
            poolData1,
            fees1
        );

        // Overwrite with different fees
        uint24[] memory fees2 = new uint24[](1);
        fees2[0] = 500; // Different fee

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path1,
            poolData1,
            fees2
        );

        ISwapAdapter.SwapPath memory retrievedPath = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );

        assertEq(retrievedPath.fees[0], 500);
    }

    function testReversePairRegistration() public {
        address[] memory pathAB = new address[](2);
        pathAB[0] = address(tokenA);
        pathAB[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            pathAB,
            poolData,
            fees
        );

        // Register reverse path
        address[] memory pathBA = new address[](2);
        pathBA[0] = address(tokenB);
        pathBA[1] = address(tokenA);

        swapAdapter.registerSwapPath(
            address(tokenB),
            address(tokenA),
            pathBA,
            poolData,
            fees
        );

        // Both should exist
        ISwapAdapter.SwapPath memory pathABResult = swapAdapter.getSwapPath(
            address(tokenA),
            address(tokenB)
        );
        ISwapAdapter.SwapPath memory pathBAResult = swapAdapter.getSwapPath(
            address(tokenB),
            address(tokenA)
        );

        assertEq(pathABResult.tokens[0], address(tokenA));
        assertEq(pathBAResult.tokens[0], address(tokenB));
    }

    // ========== GAS EFFICIENCY ==========

    function testRegisterPathGasUsage() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        uint256 gasStart = gasleft();
        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );
        uint256 gasUsed = gasStart - gasleft();

        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 500_000); // Less than 500k gas
    }

    function testGetPathGasUsage() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        swapAdapter.registerSwapPath(
            address(tokenA),
            address(tokenB),
            path,
            poolData,
            fees
        );

        uint256 gasStart = gasleft();
        swapAdapter.getSwapPath(address(tokenA), address(tokenB));
        uint256 gasUsed = gasStart - gasleft();

        assertTrue(gasUsed > 0);
        assertTrue(gasUsed < 50_000); // View function, should be cheap
    }
}
