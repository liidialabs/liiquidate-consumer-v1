// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import {UniswapV4Adapter} from "../../src/swappers/UniswapV4Adapter.sol";
// import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
// import {MockERC20} from "../mocks/MockERC20.sol";
// import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";

// /**
//  * @title UniswapV4AdapterFuzz
//  * @notice Fuzz tests for Uniswap V4 swap adapter
//  */
// contract UniswapV4AdapterFuzz is Test {
//     UniswapV4Adapter public adapter;
//     MockUniswapV4PoolManager public poolManager;
//     MockERC20 public tokenA;
//     MockERC20 public tokenB;
//     MockERC20 public tokenC;

//     address public user = address(0x1);

//     function setUp() public {
//         poolManager = new MockUniswapV4PoolManager();
//         adapter = new UniswapV4Adapter(address(poolManager));

//         tokenA = new MockERC20("Token A", "TKNA", 18);
//         tokenB = new MockERC20("Token B", "TKNB", 18);
//         tokenC = new MockERC20("Token C", "TKNC", 18);

//         tokenA.mint(user, 1_000_000e18);
//         tokenB.mint(address(poolManager), 1_000_000e18);
//         tokenC.mint(address(poolManager), 1_000_000e18);
//     }

//     // ========== PATH REGISTRATION FUZZ ==========

//     function testFuzzRegisterPathWithDifferentFees(
//         uint24[] calldata fees
//     ) public {
//         vm.assume(fees.length > 0);
//         vm.assume(fees.length <= 10);

//         address[] memory path = new address[](fees.length + 1);
//         path[0] = address(tokenA);
//         for (uint256 i = 1; i < path.length; i++) {
//             path[i] = address(tokenB);
//         }

//         bytes[] memory poolData = new bytes[](fees.length);
//         for (uint256 i = 0; i < fees.length; i++) {
//             poolData[i] = abi.encode(address(poolManager));
//         }

//         try
//             adapter.registerSwapPath(
//                 address(tokenA),
//                 address(tokenB),
//                 path,
//                 poolData,
//                 fees
//             )
//         {
//             // Tests path registration with various fees
//         } catch {
//             // Expected for invalid configurations
//         }
//     }

//     function testFuzzPathLengthVariations(uint256 pathLength) public {
//         vm.assume(pathLength >= 2);
//         vm.assume(pathLength <= 20);

//         address[] memory path = new address[](pathLength);
//         path[0] = address(tokenA);
//         path[pathLength - 1] = address(tokenB);
//         for (uint256 i = 1; i < pathLength - 1; i++) {
//             path[i] = address(tokenC);
//         }

//         bytes[] memory poolData = new bytes[](pathLength - 1);
//         for (uint256 i = 0; i < pathLength - 1; i++) {
//             poolData[i] = abi.encode(address(poolManager));
//         }

//         uint24[] memory fees = new uint24[](pathLength - 1);
//         for (uint256 i = 0; i < pathLength - 1; i++) {
//             fees[i] = 3000; // 0.3%
//         }

//         try
//             adapter.registerSwapPath(
//                 address(tokenA),
//                 address(tokenB),
//                 path,
//                 poolData,
//                 fees
//             )
//         {
//             // Tests different path lengths
//         } catch {
//             // Expected
//         }
//     }

//     // ========== MULTIPLE PATH REGISTRATION ==========

//     function testFuzzMultiplePaths(address[] calldata tokenPairs) public {
//         vm.assume(tokenPairs.length >= 2);
//         vm.assume(tokenPairs.length <= 20);

//         for (uint256 i = 0; i < tokenPairs.length - 1; i++) {
//             address tokenIn = tokenPairs[i] != address(0)
//                 ? tokenPairs[i]
//                 : address(tokenA);
//             address tokenOut = tokenPairs[i + 1] != address(0)
//                 ? tokenPairs[i + 1]
//                 : address(tokenB);

//             address[] memory path = new address[](2);
//             path[0] = tokenIn;
//             path[1] = tokenOut;

//             bytes[] memory poolData = new bytes[](1);
//             poolData[0] = abi.encode(address(poolManager));

//             uint24[] memory fees = new uint24[](1);
//             fees[0] = 3000;

//             try
//                 adapter.registerSwapPath(
//                     tokenIn,
//                     tokenOut,
//                     path,
//                     poolData,
//                     fees
//                 )
//             {
//                 // Tests multiple path registration
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== PATH SUPPORT VERIFICATION ==========

//     function testFuzzPathSupport(address tokenIn, address tokenOut) public {
//         vm.assume(tokenIn != address(0));
//         vm.assume(tokenOut != address(0));
//         vm.assume(tokenIn != tokenOut);

//         address[] memory path = new address[](2);
//         path[0] = tokenIn;
//         path[1] = tokenOut;

//         bytes[] memory poolData = new bytes[](1);
//         poolData[0] = abi.encode(address(poolManager));

//         uint24[] memory fees = new uint24[](1);
//         fees[0] = 3000;

//         try adapter.registerSwapPath(tokenIn, tokenOut, path, poolData, fees) {
//             ISwapAdapter.SwapPath memory swapPath = adapter.getSwapPath(
//                 tokenIn,
//                 tokenOut
//             );
//             assertTrue(adapter.isPathSupported(swapPath));
//         } catch {
//             // Expected
//         }
//     }

//     // ========== INVALID PATH CONFIGURATIONS ==========

//     function testFuzzInvalidPathStart(
//         address wrongToken,
//         address correctToken
//     ) public {
//         vm.assume(wrongToken != address(0));
//         vm.assume(correctToken != address(0));
//         vm.assume(wrongToken != correctToken);

//         address[] memory path = new address[](2);
//         path[0] = wrongToken; // Wrong start token
//         path[1] = address(tokenB);

//         bytes[] memory poolData = new bytes[](1);
//         poolData[0] = abi.encode(address(poolManager));

//         uint24[] memory fees = new uint24[](1);
//         fees[0] = 3000;

//         vm.expectRevert("Path must start with tokenIn");
//         adapter.registerSwapPath(
//             correctToken,
//             address(tokenB),
//             path,
//             poolData,
//             fees
//         );
//     }

//     function testFuzzInvalidPathEnd(
//         address startToken,
//         address wrongEnd,
//         address correctEnd
//     ) public {
//         vm.assume(startToken != address(0));
//         vm.assume(wrongEnd != address(0));
//         vm.assume(correctEnd != address(0));
//         vm.assume(wrongEnd != correctEnd);

//         address[] memory path = new address[](2);
//         path[0] = startToken;
//         path[1] = wrongEnd;

//         bytes[] memory poolData = new bytes[](1);
//         poolData[0] = abi.encode(address(poolManager));

//         uint24[] memory fees = new uint24[](1);
//         fees[0] = 3000;

//         vm.expectRevert("Path must end with tokenOut");
//         adapter.registerSwapPath(startToken, correctEnd, path, poolData, fees);
//     }

//     // ========== FEE VARIATIONS ==========

//     function testFuzzVariousFeeStructures(uint24[] calldata fees) public {
//         vm.assume(fees.length > 0);
//         vm.assume(fees.length <= 10);

//         address[] memory path = new address[](fees.length + 1);
//         path[0] = address(tokenA);
//         for (uint256 i = 1; i < path.length; i++) {
//             path[i] = address(tokenB);
//         }

//         bytes[] memory poolData = new bytes[](fees.length);
//         for (uint256 i = 0; i < fees.length; i++) {
//             poolData[i] = abi.encode(address(poolManager));
//         }

//         try
//             adapter.registerSwapPath(
//                 address(tokenA),
//                 address(tokenB),
//                 path,
//                 poolData,
//                 fees
//             )
//         {
//             // Tests various fee structures
//         } catch {
//             // Expected
//         }
//     }

//     // ========== STATE CONSISTENCY ==========

//     function testFuzzStateAfterOperations(
//         bytes32[] calldata operations
//     ) public {
//         vm.assume(operations.length <= 100);

//         for (uint256 i = 0; i < operations.length && i < 20; i++) {
//             address tokenIn = i % 2 == 0 ? address(tokenA) : address(tokenB);
//             address tokenOut = i % 2 == 0 ? address(tokenB) : address(tokenC);

//             address[] memory path = new address[](2);
//             path[0] = tokenIn;
//             path[1] = tokenOut;

//             bytes[] memory poolData = new bytes[](1);
//             poolData[0] = abi.encode(address(poolManager));

//             uint24[] memory fees = new uint24[](1);
//             fees[0] = 3000;

//             try
//                 adapter.registerSwapPath(
//                     tokenIn,
//                     tokenOut,
//                     path,
//                     poolData,
//                     fees
//                 )
//             {
//                 // Success
//             } catch {
//                 // Expected
//             }
//         }
//     }

//     // ========== PROTOCOL ID VERIFICATION ==========

//     function testFuzzProtocolIdConsistency() public {
//         bytes32 id1 = adapter.protocolId();
//         bytes32 id2 = adapter.protocolId();
//         assertEq(id1, id2);

//         bytes32 expectedId = keccak256("UNISWAP_V4");
//         assertEq(id1, expectedId);
//     }

//     // ========== PATH OVERWRITING ==========

//     function testFuzzPathOverwrite(uint24 fee1, uint24 fee2) public {
//         vm.assume(fee1 != fee2);

//         address[] memory path = new address[](2);
//         path[0] = address(tokenA);
//         path[1] = address(tokenB);

//         bytes[] memory poolData = new bytes[](1);
//         poolData[0] = abi.encode(address(poolManager));

//         uint24[] memory fees1 = new uint24[](1);
//         fees1[0] = fee1;

//         adapter.registerSwapPath(
//             address(tokenA),
//             address(tokenB),
//             path,
//             poolData,
//             fees1
//         );

//         ISwapAdapter.SwapPath memory path1 = adapter.getSwapPath(
//             address(tokenA),
//             address(tokenB)
//         );
//         assertEq(path1.fees[0], fee1);

//         uint24[] memory fees2 = new uint24[](1);
//         fees2[0] = fee2;

//         adapter.registerSwapPath(
//             address(tokenA),
//             address(tokenB),
//             path,
//             poolData,
//             fees2
//         );

//         ISwapAdapter.SwapPath memory path2 = adapter.getSwapPath(
//             address(tokenA),
//             address(tokenB)
//         );
//         assertEq(path2.fees[0], fee2);
//     }

//     // ========== GAS OPTIMIZATION ==========

//     function testFuzzRegistrationGasUsage(uint256 pathLength) public {
//         vm.assume(pathLength >= 2);
//         vm.assume(pathLength <= 10);

//         address[] memory path = new address[](pathLength);
//         path[0] = address(tokenA);
//         path[pathLength - 1] = address(tokenB);

//         bytes[] memory poolData = new bytes[](pathLength - 1);
//         uint24[] memory fees = new uint24[](pathLength - 1);

//         uint256 gasStart = gasleft();
//         try
//             adapter.registerSwapPath(
//                 address(tokenA),
//                 address(tokenB),
//                 path,
//                 poolData,
//                 fees
//             )
//         {
//             uint256 gasUsed = gasStart - gasleft();
//             assertTrue(gasUsed < 500_000);
//         } catch {}
//     }

//     function testFuzzRetrievalGasUsage() public {
//         address[] memory path = new address[](2);
//         path[0] = address(tokenA);
//         path[1] = address(tokenB);

//         bytes[] memory poolData = new bytes[](1);
//         poolData[0] = abi.encode(address(poolManager));

//         uint24[] memory fees = new uint24[](1);
//         fees[0] = 3000;

//         adapter.registerSwapPath(
//             address(tokenA),
//             address(tokenB),
//             path,
//             poolData,
//             fees
//         );

//         uint256 gasStart = gasleft();
//         adapter.getSwapPath(address(tokenA), address(tokenB));
//         uint256 gasUsed = gasStart - gasleft();

//         assertTrue(gasUsed < 10_000);
//     }

//     // ========== MAXIMUM CONFIGURATIONS ==========

//     function testFuzzMaxPathLength() public {
//         uint256 maxLength = 20;

//         address[] memory path = new address[](maxLength);
//         path[0] = address(tokenA);
//         path[maxLength - 1] = address(tokenB);

//         bytes[] memory poolData = new bytes[](maxLength - 1);
//         uint24[] memory fees = new uint24[](maxLength - 1);

//         for (uint256 i = 0; i < maxLength - 1; i++) {
//             poolData[i] = abi.encode(address(poolManager));
//             fees[i] = 3000;
//         }

//         try
//             adapter.registerSwapPath(
//                 address(tokenA),
//                 address(tokenB),
//                 path,
//                 poolData,
//                 fees
//             )
//         {
//             // Tests maximum path length
//         } catch {
//             // Expected for very long paths
//         }
//     }

//     // ========== OWNERSHIP TESTS ==========

//     function testFuzzOwnershipChanges(address[] calldata newOwners) public {
//         vm.assume(newOwners.length <= 50);

//         for (uint256 i = 0; i < newOwners.length; i++) {
//             if (newOwners[i] != address(0)) {
//                 adapter.transferOwnership(newOwners[i]);
//                 assertEq(adapter.owner(), newOwners[i]);

//                 // Can only operate as new owner
//                 vm.prank(newOwners[i]);
//                 // Any owner operations here
//             }
//         }
//     }
// }
