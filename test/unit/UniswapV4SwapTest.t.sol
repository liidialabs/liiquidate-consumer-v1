// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {UniswapV4Adapter} from "../../src/swappers/UniswapV4Adapter.sol";
import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {TestHelpers} from "../mocks/TestHelpers.sol";
import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";

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

    address public user = address(0x1);
    address public liquidator = address(0x2);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant SWAP_AMOUNT = 100_000e18;
    uint256 constant POOL_FEE = 3000; // 0.3%

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

        // Create pool manager
        mockPoolManager = new MockUniswapV4PoolManager();

        // Create swap adapter
        swapAdapter = new UniswapV4Adapter(address(mockPoolManager));

        // Setup initial balances
        tokenA.mint(user, INITIAL_BALANCE);
        tokenB.mint(address(mockPoolManager), INITIAL_BALANCE);
        tokenC.mint(address(mockPoolManager), INITIAL_BALANCE);
    }

    // ========== SWAP PATH REGISTRATION TESTS ==========

    function testRegisterSimpleSwapPath() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager)); // Placeholder pool data

        uint24[] memory fees = new uint24[](1);
        fees[0] = POOL_FEE;

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
        fees[0] = POOL_FEE;
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
        fees[0] = POOL_FEE;

        vm.expectRevert("Invalid tokens");
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
        fees[0] = POOL_FEE;

        vm.expectRevert("Invalid tokens");
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

        vm.expectRevert("Path must have at least 2 tokens");
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
        fees[0] = POOL_FEE;

        vm.expectRevert("Path must start with tokenIn");
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
        fees[0] = POOL_FEE;

        vm.expectRevert("Path must end with tokenOut");
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
        fees[0] = POOL_FEE;
        fees[1] = POOL_FEE;

        vm.expectRevert("poolData length mismatch");
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
        fees[0] = POOL_FEE;

        vm.expectRevert("fees length mismatch");
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
        fees[0] = POOL_FEE;

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
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = POOL_FEE;

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

        assertTrue(swapAdapter.isPathSupported(swapPath));
    }

    function testIsPathSupportedReturnsFalseForUnregisteredPath() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = POOL_FEE;

        ISwapAdapter.SwapPath memory swapPath = ISwapAdapter.SwapPath({
            tokens: path,
            poolData: poolData,
            fees: fees
        });

        assertFalse(swapAdapter.isPathSupported(swapPath));
    }

    // ========== GET SWAP PATH TESTS ==========

    function testGetSwapPathReturnsRegisteredPath() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees = new uint24[](1);
        fees[0] = POOL_FEE;

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
        fees1[0] = POOL_FEE;

        // Path 2: B -> C
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenC);

        bytes[] memory poolData2 = new bytes[](1);
        poolData2[0] = abi.encode(address(mockPoolManager));

        uint24[] memory fees2 = new uint24[](1);
        fees2[0] = POOL_FEE;

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
        fees1[0] = POOL_FEE;

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
        fees[0] = POOL_FEE;

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
        fees[0] = POOL_FEE;

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
        fees[0] = POOL_FEE;

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
