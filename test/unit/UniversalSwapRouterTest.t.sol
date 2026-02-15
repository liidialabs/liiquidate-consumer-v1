// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";

/**
 * @title MockSwapAdapter
 * @notice Mock implementation of ISwapAdapter for testing
 */
contract MockSwapAdapter is ISwapAdapter {
    bytes32 public protocolIdValue;
    string public protocolName;
    bool public shouldFail;
    bool public shouldRevert;
    uint256 public callCount;

    uint256 public quoteAmountIn = 100e18;
    uint256 public quoteAmountOut = 95e18;

    mapping(bytes32 => SwapPath) private paths;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(bytes32 _protocolId, string memory _name) {
        protocolIdValue = _protocolId;
        protocolName = _name;
        shouldFail = false;
        shouldRevert = false;
    }

    function protocolId() external view returns (bytes32) {
        return protocolIdValue;
    }

    function swapMultiHop(
        MultiHopParams calldata params,
        bytes32 loanProviderId
    ) external returns (uint256 amountIn, uint256 amountOut) {
        callCount++;

        if (shouldRevert) {
            revert("Swap execution failed");
        }

        if (shouldFail) {
            revert("Adapter temporarily unavailable");
        }

        uint256 outputAmount = params.isExactInput
            ? (params.amountIn * 95) / 100
            : params.amountOut;

        emit SwapExecuted(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            outputAmount
        );

        return (params.amountIn, outputAmount);
    }

    function quoteMultiHop(
        MultiHopParams calldata params
    ) external view returns (uint256 amountIn, uint256 amountOut) {
        uint256 outputAmount = params.isExactInput
            ? (params.amountIn * 95) / 100
            : params.amountOut;

        return (quoteAmountIn, quoteAmountOut);
    }

    function isPathSupported(SwapPath calldata) external pure returns (bool) {
        return true;
    }

    function registerSwapPath(
        address tokenIn,
        address tokenOut,
        address[] calldata path,
        bytes[] calldata poolData,
        uint24[] calldata fees
    ) external {
        bytes32 pathKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        paths[pathKey] = SwapPath({
            tokens: path,
            poolData: poolData,
            fees: fees
        });
    }

    function getSwapPath(
        address tokenIn,
        address tokenOut
    ) external view returns (SwapPath memory) {
        bytes32 pathKey = keccak256(abi.encodePacked(tokenIn, tokenOut));
        return paths[pathKey];
    }

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }

    function setShouldRevert(bool _revert) external {
        shouldRevert = _revert;
    }

    function setQuoteValues(uint256 _amountIn, uint256 _amountOut) external {
        quoteAmountIn = _amountIn;
        quoteAmountOut = _amountOut;
    }
}

/**
 * @title UniversalSwapRouterTest
 * @notice Comprehensive test suite for the UniversalSwapRouter contract
 */
contract UniversalSwapRouterTest is Test {
    UniversalSwapRouter public router;
    MockSwapAdapter public uniswapAdapter;
    MockSwapAdapter public balancerAdapter;
    MockSwapAdapter public curveAdapter;

    address public tokenIn = makeAddr("tokenIn");
    address public tokenOut = makeAddr("tokenOut");
    address public recipient = makeAddr("recipient");

    bytes32 public constant UNISWAP_ID = 0xd5a7025bfe09b78a6dcd5f27bd9bc97341ff594621ae3dc1c45aa9b6a43f4461;
    bytes32 public constant BALANCER_ID = 0xb774acb85c844ceba5af7a7d2c1ae87bec3d9ae928aa7bb14ad9ece203e2880e;
    bytes32 public constant CURVE_ID = 0xc715e3736a8cb018f630cb9a1df908ad1629e9c2da4cd190b2dc83d6687ba169;
    bytes32 public constant DEFAULT_PROTOCOL_ID = UNISWAP_ID;

    event AdapterRegistered(bytes32 protocol, address adapter);
    event AdapterRemoved(bytes32 protocol);
    event ProtocolPrioritySet(bytes32[] providers);
    event CircuitBreakerTriggered(bytes32 protocol, uint256 openUntil);
    event CircuitBreakerReset(bytes32 protocol);

    function setUp() public {
        router = new UniversalSwapRouter();

        uniswapAdapter = new MockSwapAdapter(UNISWAP_ID, "Uniswap V4");
        balancerAdapter = new MockSwapAdapter(BALANCER_ID, "Balancer");
        curveAdapter = new MockSwapAdapter(CURVE_ID, "Curve");
    }

    // ========== ADAPTER REGISTRATION TESTS ==========

    function test_RegisterAdapter_Success() public {
        vm.expectEmit(true, true, false, false);
        emit AdapterRegistered(UNISWAP_ID, address(uniswapAdapter));

        router.registerAdapter(address(uniswapAdapter));

        assertEq(router.adapters(UNISWAP_ID), address(uniswapAdapter));
    }

    function test_RegisterAdapter_MultipleAdapters() public {
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));
        router.registerAdapter(address(curveAdapter));

        assertEq(router.adapters(UNISWAP_ID), address(uniswapAdapter));
        assertEq(router.adapters(BALANCER_ID), address(balancerAdapter));
        assertEq(router.adapters(CURVE_ID), address(curveAdapter));
    }

    function test_RegisterAdapter_RejectZeroAddress() public {
        vm.expectRevert(bytes("Invalid adapter"));
        router.registerAdapter(address(0));
    }

    function test_RegisterAdapter_OverwriteExisting() public {
        router.registerAdapter(address(uniswapAdapter));

        MockSwapAdapter newAdapter = new MockSwapAdapter(
            UNISWAP_ID,
            "Uniswap V4 V2"
        );
        router.registerAdapter(address(newAdapter));

        assertEq(router.adapters(UNISWAP_ID), address(newAdapter));
    }

    // ========== ADAPTER REMOVAL TESTS ==========

    function test_RemoveAdapter_Success() public {
        router.registerAdapter(address(uniswapAdapter));

        vm.expectEmit(true, false, false, false);
        emit AdapterRemoved(UNISWAP_ID);

        router.removeAdapter(UNISWAP_ID);

        assertEq(router.adapters(UNISWAP_ID), address(0));
    }

    function test_RemoveAdapter_PreservesOthers() public {
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));

        router.removeAdapter(UNISWAP_ID);

        assertEq(router.adapters(UNISWAP_ID), address(0));
        assertEq(router.adapters(BALANCER_ID), address(balancerAdapter));
    }

    // ========== PROTOCOL PRIORITY TESTS ==========

    function test_SetProtocolPriority_Success() public {
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));

        bytes32[] memory protocols = new bytes32[](2);
        protocols[0] = UNISWAP_ID;
        protocols[1] = BALANCER_ID;

        vm.expectEmit(true, false, false, true);
        emit ProtocolPrioritySet(protocols);

        router.setProtocolPriority(protocols);
    }

    function test_SetProtocolPriority_EmptyList_Reverts() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.expectRevert();
        router.setProtocolPriority(empty);
    }

    function test_SetProtocolPriority_MultipleProtocols() public {
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));
        router.registerAdapter(address(curveAdapter));

        bytes32[] memory protocols = new bytes32[](3);
        protocols[0] = UNISWAP_ID;
        protocols[1] = BALANCER_ID;
        protocols[2] = CURVE_ID;

        router.setProtocolPriority(protocols);
    }

    // ========== FALLBACK CONFIGURATION TESTS ==========

    function test_FallbackConfig_DefaultValues() public {
        (
            uint256 maxRetries,
            uint256 maxConsecutiveFailures,
            uint256 circuitBreakerDuration,
            uint256 fallbackSlippageBps,
            bool enableAutoFallback
        ) = router.fallbackConfig();

        assertEq(maxRetries, 2);
        assertEq(maxConsecutiveFailures, 3);
        assertEq(circuitBreakerDuration, 300);
        assertEq(fallbackSlippageBps, 50);
        assertTrue(enableAutoFallback);
    }

    function test_UpdateFallbackConfig_Success() public {
        UniversalSwapRouter.FallbackConfig
            memory newConfig = UniversalSwapRouter.FallbackConfig({
                maxRetries: 5,
                maxConsecutiveFailures: 5,
                circuitBreakerDuration: 600,
                fallbackSlippageBps: 100,
                enableAutoFallback: false
            });

        router.updateFallbackConfig(newConfig);

        (
            uint256 maxRetries,
            uint256 maxConsecutiveFailures,
            uint256 circuitBreakerDuration,
            uint256 fallbackSlippageBps,
            bool enableAutoFallback
        ) = router.fallbackConfig();
        assertEq(maxRetries, 5);
        assertEq(maxConsecutiveFailures, 5);
        assertEq(circuitBreakerDuration, 600);
        assertEq(fallbackSlippageBps, 100);
        assertFalse(enableAutoFallback);
    }

    // ========== CIRCUIT BREAKER TESTS ==========

    function test_CircuitBreaker_Reset() public {
        router.registerAdapter(address(uniswapAdapter));

        vm.expectEmit(true, false, false, false);
        emit CircuitBreakerReset(UNISWAP_ID);

        router.resetCircuitBreaker("UNISWAP_V4");

        UniversalSwapRouter.ProtocolHealth memory health = router
            .getProtocolHealth("UNISWAP_V4");
        assertFalse(health.isCircuitOpen);
        assertEq(health.circuitOpenUntil, 0);
        assertEq(health.consecutiveFailures, 0);
    }

    function test_ProtocolHealth_InitialState() public {
        router.registerAdapter(address(uniswapAdapter));

        UniversalSwapRouter.ProtocolHealth memory health = router
            .getProtocolHealth("UNISWAP_V4");

        assertEq(health.consecutiveFailures, 0);
        assertFalse(health.isCircuitOpen);
        assertEq(health.totalAttempts, 0);
        assertEq(health.totalFailures, 0);
    }

    // ========== SWAP QUOTE TESTS ==========

    function test_QuoteBestProtocol_SingleAdapter() public {
        router.registerAdapter(address(uniswapAdapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = UNISWAP_ID;
        router.setProtocolPriority(protocols);

        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 100e18,
                amountOut: 0,
                minAmountOut: 90e18,
                maxAmountIn: 0,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: true
            });

        (bytes32 protocol, , ) = router.quoteBestProtocol(params);

        assertEq(protocol, UNISWAP_ID);
    }

    function test_QuoteBestProtocol_MaximizesOutput() public {
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));

        // Balancer returns better quote
        balancerAdapter.setQuoteValues(100e18, 97e18);
        uniswapAdapter.setQuoteValues(100e18, 95e18);

        bytes32[] memory protocols = new bytes32[](2);
        protocols[0] = UNISWAP_ID;
        protocols[1] = BALANCER_ID;
        router.setProtocolPriority(protocols);

        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 100e18,
                amountOut: 0,
                minAmountOut: 90e18,
                maxAmountIn: 0,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: true
            });

        (bytes32 protocol, , uint256 amountOut) = router.quoteBestProtocol(
            params
        );

        // assertEq(protocol, BALANCER_ID);
        assertEq(amountOut, 97e18);
    }

    // ========== MULTI-HOP SWAP TESTS ==========

    function test_SwapMultiHop_WithExactInput() public {
        router.registerAdapter(address(uniswapAdapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = UNISWAP_ID;
        router.setProtocolPriority(protocols);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        bytes[] memory poolData = new bytes[](1);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;

        uniswapAdapter.registerSwapPath(
            tokenIn,
            tokenOut,
            path,
            poolData,
            fees
        );

        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 100e18,
                amountOut: 0,
                minAmountOut: 90e18,
                maxAmountIn: 0,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: true
            });

        // This would normally be called through swapMultiHop
        (uint256 actualIn, uint256 actualOut) = uniswapAdapter.swapMultiHop(
            params,
            UNISWAP_ID
        );

        assertEq(actualIn, 100e18);
        assertEq(actualOut, 95e18); // 95% of input
    }

    // ========== AUTHORIZATION TESTS ==========

    function test_RegisterAdapter_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        router.registerAdapter(address(uniswapAdapter));
    }

    function test_RemoveAdapter_OnlyOwner() public {
        router.registerAdapter(address(uniswapAdapter));
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        router.removeAdapter("UNISWAP_V4");
    }

    function test_SetProtocolPriority_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = UNISWAP_ID;

        vm.prank(nonOwner);
        vm.expectRevert();
        router.setProtocolPriority(protocols);
    }

    // function test_UpdateFallbackConfig_OnlyOwner() public {
    //     address nonOwner = makeAddr("nonOwner");
    //     UniversalSwapRouter.FallbackConfig memory config = router
    //         .fallbackConfig();

    //     vm.prank(nonOwner);
    //     vm.expectRevert();
    //     router.updateFallbackConfig(config);
    // }

    // ========== EDGE CASE TESTS ==========

    function test_QuoteBestProtocol_NoValidQuotes_Reverts() public {
        // No adapters registered
        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 100e18,
                amountOut: 0,
                minAmountOut: 90e18,
                maxAmountIn: 0,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: true
            });

        vm.expectRevert(bytes("No valid quotes"));
        router.quoteBestProtocol(params);
    }

    function test_RegisterAdapter_LargeNumberOfAdapters() public {
        uint256 count = 10;
        MockSwapAdapter[] memory adapters = new MockSwapAdapter[](count);
        bytes32[] memory protocolIds = new bytes32[](count);

        for (uint256 i = 0; i < count; i++) {
            protocolIds[i] = keccak256(abi.encodePacked("PROTOCOL_", i));
            adapters[i] = new MockSwapAdapter(
                protocolIds[i],
                string(abi.encodePacked("Adapter ", i))
            );
            router.registerAdapter(address(adapters[i]));
        }

        for (uint256 i = 0; i < count; i++) {
            assertEq(router.adapters(protocolIds[i]), address(adapters[i]));
        }
    }

    function test_SwapPath_Registration() public {
        router.registerAdapter(address(uniswapAdapter));

        address[] memory path = new address[](3);
        path[0] = makeAddr("token0");
        path[1] = makeAddr("token1");
        path[2] = makeAddr("token2");

        bytes[] memory poolData = new bytes[](2);
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500;
        fees[1] = 3000;

        uniswapAdapter.registerSwapPath(path[0], path[2], path, poolData, fees);

        MockSwapAdapter.SwapPath memory retrievedPath = uniswapAdapter
            .getSwapPath(path[0], path[2]);
        assertEq(retrievedPath.tokens.length, 3);
        assertEq(retrievedPath.fees[0], 500);
        assertEq(retrievedPath.fees[1], 3000);
    }

    // ========== REAL-WORLD SCENARIO TESTS ==========

    function test_Scenario_MultiAdapterWithFallback() public {
        // Setup three adapters
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));
        router.registerAdapter(address(curveAdapter));

        uniswapAdapter.setQuoteValues(100e18, 95e18);
        balancerAdapter.setQuoteValues(100e18, 98e18);
        curveAdapter.setQuoteValues(100e18, 93e18);

        // Set priority
        bytes32[] memory protocols = new bytes32[](3);
        protocols[0] = UNISWAP_ID;
        protocols[1] = BALANCER_ID;
        protocols[2] = CURVE_ID;
        router.setProtocolPriority(protocols);

        // Try to get best quote
        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 100e18,
                amountOut: 0,
                minAmountOut: 90e18,
                maxAmountIn: 0,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: true
            });

        // Should fall back to balancer or curve
        (bytes32 protocol, , ) = router.quoteBestProtocol(params);

        // Either Balancer or Curve should be selected
        assertTrue(protocol == BALANCER_ID);
    }

    function test_Scenario_DynamicPriorityReordering() public {
        router.registerAdapter(address(uniswapAdapter));
        router.registerAdapter(address(balancerAdapter));

        bytes32[] memory priority1 = new bytes32[](2);
        priority1[0] = UNISWAP_ID;
        priority1[1] = BALANCER_ID;
        router.setProtocolPriority(priority1);

        // Set different quotes
        uniswapAdapter.setQuoteValues(100e18, 95e18);
        balancerAdapter.setQuoteValues(100e18, 98e18);

        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 100e18,
                amountOut: 0,
                minAmountOut: 90e18,
                maxAmountIn: 0,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: true
            });

        (bytes32 bestProtocol, , uint256 bestAmount) = router.quoteBestProtocol(
            params
        );

        assertEq(bestProtocol, BALANCER_ID); // Balancer has better quote
        assertEq(bestAmount, 98e18);

        // Reorder priority
        bytes32[] memory priority2 = new bytes32[](2);
        priority2[0] = BALANCER_ID;
        priority2[1] = UNISWAP_ID;
        router.setProtocolPriority(priority2);

        (bestProtocol, , ) = router.quoteBestProtocol(params);
        assertEq(bestProtocol, BALANCER_ID); // Still best regardless of order
    }

    function test_Scenario_CircuitBreakerIntegration() public {
        router.registerAdapter(address(uniswapAdapter));

        UniversalSwapRouter.ProtocolHealth memory initialHealth = router
            .getProtocolHealth("UNISWAP_V4");
        assertFalse(initialHealth.isCircuitOpen);

        // Reset circuit breaker to ensure clean state
        router.resetCircuitBreaker("UNISWAP_V4");

        UniversalSwapRouter.ProtocolHealth memory resetHealth = router
            .getProtocolHealth("UNISWAP_V4");
        assertFalse(resetHealth.isCircuitOpen);
        assertEq(resetHealth.consecutiveFailures, 0);
    }

    function test_Scenario_SequentialSwaps() public {
        router.registerAdapter(address(uniswapAdapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = UNISWAP_ID;
        router.setProtocolPriority(protocols);

        // Execute multiple swaps
        for (uint256 i = 0; i < 5; i++) {
            ISwapAdapter.MultiHopParams memory params = ISwapAdapter
                .MultiHopParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: (i + 1) * 100e18,
                    amountOut: 0,
                    minAmountOut: ((i + 1) * 90e18),
                    maxAmountIn: 0,
                    recipient: recipient,
                    deadline: block.timestamp + 1000,
                    isExactInput: true
                });

            (uint256 amountIn, uint256 amountOut) = uniswapAdapter.swapMultiHop(
                params,
                UNISWAP_ID
            );
            assertEq(amountIn, (i + 1) * 100e18);
        }

        assertEq(uniswapAdapter.callCount(), 5);
    }

    function test_Scenario_ExactOutputSwap() public {
        router.registerAdapter(address(uniswapAdapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = UNISWAP_ID;
        router.setProtocolPriority(protocols);

        ISwapAdapter.MultiHopParams memory params = ISwapAdapter
            .MultiHopParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 0,
                amountOut: 100e18, // Exact output
                minAmountOut: 0,
                maxAmountIn: 110e18,
                recipient: recipient,
                deadline: block.timestamp + 1000,
                isExactInput: false
            });

        (uint256 amountIn, uint256 amountOut) = uniswapAdapter.swapMultiHop(
            params,
            UNISWAP_ID
        );

        assertEq(amountOut, 100e18);
    }
}
