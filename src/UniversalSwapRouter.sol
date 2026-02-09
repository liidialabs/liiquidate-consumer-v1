// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISwapAdapter} from "./interfaces/swapAdapter/ISwapAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UniversalSwapRouter
 * @notice Routes swaps across multiple DEX protocols
 */
contract UniversalSwapRouter {
    /// @notice Protocol health tracking
    struct ProtocolHealth {
        uint256 consecutiveFailures;
        uint256 lastFailureTime;
        uint256 totalAttempts;
        uint256 totalFailures;
        bool isCircuitOpen; // True = circuit broken, skip protocol
        uint256 circuitOpenUntil; // Timestamp when circuit can close
    }

    /// @notice Fallback configuration
    struct FallbackConfig {
        uint256 maxRetries; // Max retries per protocol
        uint256 maxConsecutiveFailures; // Failures before circuit opens
        uint256 circuitBreakerDuration; // How long circuit stays open
        uint256 fallbackSlippageBps; // Extra slippage for fallback (in bps)
        bool enableAutoFallback; // Enable automatic fallback
    }

    // Default Protocol ID as UniswapV4
    bytes32 public constant DEFAULT_PROTOCOL_ID = keccak256("UNI_V4");
    uint16 private constant BASE_BPS = 1e4;

    /// @notice Registered protocol adapters
    mapping(bytes32 => address) public adapters;
    /// @notice Protocol health metrics
    mapping(bytes32 => ProtocolHealth) public protocolHealth;

    /// @notice Protocol priority for fallbacks
    bytes32[] public protocolPriority;

    /// @notice Global fallback configuration
    FallbackConfig public fallbackConfig;

    /// @notice Events
    event SwapAttempted(bytes32 protocol, bool success, string reason);
    event ProtocolFallback(
        bytes32 fromProtocol,
        bytes32 toProtocol,
        address indexed user
    );
    event CircuitBreakerTriggered(bytes32 protocol, uint256 openUntil);
    event CircuitBreakerReset(bytes32 protocol);
    event AdapterRegistered(bytes32 protocol, address adapter);
    event AdapterRemoved(bytes32 protocol);
    event MultiHopSwapExecuted(
        bytes32 protocol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event SwapRoutedOn(bytes32 protocol);
    event DefaultRouteFailed(bytes32 protocol);
    event ProtocolPrioritySet(bytes32[] providers);

    constructor() Ownable(msg.sender) {
        // Default fallback configuration
        fallbackConfig = FallbackConfig({
            maxRetries: 2,
            maxConsecutiveFailures: 3,
            circuitBreakerDuration: 300, // 5 minutes
            fallbackSlippageBps: 50, // 0.5% extra slippage
            enableAutoFallback: true
        });
    }

    function registerAdapter(address adapter) external onlyOwner {
        require(adapter != address(0), "Invalid adapter");
        bytes32 protocol = ISwapAdapter(adapter).protocolId();
        adapters[protocol] = adapter;
        emit AdapterRegistered(protocol, adapter);
    }

    function removeAdapter(string memory protocol) external onlyOwner {
        delete adapters[keccak256(protocol)];
        emit AdapterRemoved(protocol);
    }

    function setProtocolPriority(
        string[] calldata protocols
    ) external onlyOwner {
        require(protocols.length > 0, "empty list");

        bytes32[] memory convertedProtocols = new bytes32[](protocols.length);
        for (uint256 i = 0; i < protocols.length; i++) {
            convertedProtocols[i] = keccak256(abi.encodePacked(protocols[i]));
        }

        protocolPriority = convertedProtocols;
        emit ProtocolPrioritySet(convertedProtocols);
    }

    function updateFallbackConfig(
        FallbackConfig calldata config
    ) external onlyOwner {
        fallbackConfig = config;
    }

    function swapMultiHop(
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 minDebtAssetOut
    )
        external
        returns (uint256 amountIn, uint256 amountOut, bytes32 usedProtocol)
    {
        ISwapAdapter.MultiHopParams memory params = this._buildMultiHopParams(
            collateralAsset,
            debtAsset,
            collateralAmount,
            minDebtAssetOut
        );

        // get base protocol
        (bytes32 protocol, , ) = quoteBestProtocol(params);
        // go with default if priority is not set
        if (protocolPriority.length == 0) {
            _executeWithDefault(protocol, params);
        }
        // Loop through available adapters
        _executeTryMultiple(protocol, params);
    }

    function resetCircuitBreaker(string memory protocol) external {
        ProtocolHealth storage health = protocolHealth[keccak256(protocol)];
        health.isCircuitOpen = false;
        health.circuitOpenUntil = 0;
        health.consecutiveFailures = 0;
        emit CircuitBreakerReset(keccak256(protocol));
    }

    function getProtocolHealth(
        string memory protocol
    ) external view returns (ProtocolHealth memory) {
        return protocolHealth[keccak256(protocol)];
    }

    // REDO
    function quoteBestProtocol(
        ISwapAdapter.MultiHopParams calldata params
    )
        public
        view
        returns (bytes32 bestProtocol, uint256 amountIn, uint256 amountOut)
    {
        uint256 bestOutput = 0;
        uint256 bestInput = type(uint256).max;

        for (uint256 i = 0; i < protocolPriority.length; i++) {
            bytes32 protocol = protocolPriority[i];

            // Skip unhealthy protocols
            if (_isCircuitOpen(protocol)) {
                continue;
            }

            address adapter = adapters[protocol];
            if (adapter == address(0)) {
                continue;
            }

            try ISwapAdapter(adapter).quoteMultiHop(params) returns (
                uint256 qAmountIn,
                uint256 qAmountOut
            ) {
                // For exact input, maximize output
                if (params.isExactInput && qAmountOut > bestOutput) {
                    bestOutput = qAmountOut;
                    bestProtocol = protocol;
                    amountIn = qAmountIn;
                    amountOut = qAmountOut;
                }
                // For exact output, minimize input
                else if (!params.isExactInput && qAmountIn < bestInput) {
                    bestInput = qAmountIn;
                    bestProtocol = protocol;
                    amountIn = qAmountIn;
                    amountOut = qAmountOut;
                }
            } catch {
                // Skip failed quotes
                continue;
            }
        }

        require(bytes(bestProtocol).length > 0, "No valid quotes");
    }

    // REDO
    function quoteSpecific(
        string memory protocol,
        ISwapAdapter.MultiHopParams calldata params
    ) external view returns (uint256 amountIn, uint256 amountOut) {
        // Fetch adapter
        address adapter = adapters[keccak256(protocol)];
        require(adapter != address(0), "Protocol not supported");

        return ISwapAdapter(adapter).quoteMultiHop(params);
    }

    ///////////// INTERNAL FUNCTIONS ////////////////

    function _executeWithDefault(
        bytes32 _protocol,
        ISwapAdapter.MultiHopParams calldata params
    ) internal {
        // get default adapter
        address adapter = adapters[_protocol];
        // checks
        if (adapter == address(0)) return (0, 0, _protocol);
        if (_isCircuitOpen(_protocol)) return (0, 0, _protocol);

        // call
        try ISwapAdapter(adapter).swapMultiHop(params) returns (
            uint256 _amountIn,
            uint256 _amountOut
        ) {
            emit MultiHopSwapExecuted(
                msg.sender,
                params.tokenIn,
                params.tokenOut,
                _amountIn,
                _amountOut
            );
            return (_amountIn, _amountOut, _protocol);
        } catch {
            emit DefaultRouteFailed(_protocol);
        }
    }

    function _executeTryMultiple(
        bytes32 _protocol,
        ISwapAdapter.MultiHopParams calldata params
    ) internal {

        for (uint256 i = 0; i < protocolPriority.length; i++) {
            bytes32 protocol = protocolPriority[i];

            // prioritize best protocol first
            if (i == 0 && protocol != _protocol) {
                protocol = _protocol;
            }

            // skip best protocol if fallback happened
            if (i != 0 && protocol == _protocol) continue;

            // check if circuit is open
            if (_isCircuitOpen(protocol)) {
                emit SwapAttempted(protocol, false, "Circuit breaker open");
                continue;
            }

            // Adjust slippage for fallback attempts
            ISwapAdapter.MultiHopParams memory adjustedParams;
            if (i > 0) {
                adjustedParams = _adjustSlippageForFallback(params, i);
            }

            // Attempt swap
            (
                bool success,
                uint256 resultAmountIn,
                uint256 resultAmountOut,
                string memory reason
            ) = _attemptSwap(protocol, adjustedParams);

            //  Handle response
            if (success) {
                _recordSuccess(protocol);
                emit MultiHopSwapExecuted(
                    protocol,
                    params.path.tokens[0],
                    params.path.tokens[params.path.tokens.length - 1],
                    resultAmountIn,
                    resultAmountOut
                );
                return (resultAmountIn, resultAmountOut, protocol);
            } else {
                _recordFailure(protocol, reason);

                // Emit fallback event if trying next protocol
                if (i < protocolPriority.length - 1) {
                    emit ProtocolFallback(
                        protocol,
                        protocolPriority[i + 1],
                        msg.sender
                    );
                }
            }
        }

        revert("All protocols failed");
    }

    function _attemptSwap(
        bytes32 protocol,
        ISwapAdapter.MultiHopParams memory params
    )
        internal
        returns (
            bool success,
            uint256 amountIn,
            uint256 amountOut,
            string memory reason
        )
    {
        // Get adapter
        address adapter = adapters[protocol];
        if (adapter == address(0)) {
            return (false, 0, 0, "Adapter not found");
        }

        // Record attempt
        protocolHealth[protocol].totalAttempts++;

        emit SwapAttempted(protocol, false, "Attempting");

        try ISwapAdapter(adapter).swapMultiHop(params) returns (
            uint256 resultAmountIn,
            uint256 resultAmountOut
        ) {
            emit SwapAttempted(protocol, true, "Success");
            return (true, resultAmountIn, resultAmountOut, "");
        } catch Error(string memory err) {
            return (false, 0, 0, err);
        } catch (bytes memory) {
            return (false, 0, 0, "Unknown error");
        }
    }

    function _adjustSlippageForFallback(
        ISwapAdapter.MultiHopParams memory params,
        uint256 fallbackIndex
    ) internal view returns (ISwapAdapter.MultiHopParams memory) {
        ISwapAdapter.MultiHopParams memory adjusted = params;

        // Increase slippage tolerance for each fallback attempt
        uint256 extraSlippageBps = fallbackConfig.fallbackSlippageBps *
            fallbackIndex;

        if (params.isExactInput) {
            // Reduce minimum output by extra slippage
            adjusted.minAmountOut =
                (params.minAmountOut * (BASE_BPS - extraSlippageBps)) /
                BASE_BPS;
        } else {
            // Increase maximum input by extra slippage
            adjusted.maxAmountIn =
                (params.maxAmountIn * (BASE_BPS + extraSlippageBps)) /
                BASE_BPS;
        }

        return adjusted;
    }

    function _isCircuitOpen(bytes32 protocol) internal view returns (bool) {
        ProtocolHealth storage health = protocolHealth[protocol];

        if (!health.isCircuitOpen) {
            return false;
        }

        // Check if circuit breaker should auto-reset
        if (block.timestamp >= health.circuitOpenUntil) {
            return false;
        }

        return true;
    }

    function _recordSuccess(bytes32 protocol) internal {
        ProtocolHealth storage health = protocolHealth[protocol];
        health.consecutiveFailures = 0;

        // Auto-reset circuit breaker on success
        if (health.isCircuitOpen) {
            health.isCircuitOpen = false;
            health.circuitOpenUntil = 0;
            emit CircuitBreakerReset(protocol);
        }
    }

    function _recordFailure(bytes32 protocol, string memory reason) internal {
        ProtocolHealth storage health = protocolHealth[protocol];
        health.consecutiveFailures++;
        health.totalFailures++;
        health.lastFailureTime = block.timestamp;

        emit SwapAttempted(protocol, false, reason);

        // Trigger circuit breaker if threshold reached
        if (
            health.consecutiveFailures >=
            fallbackConfig.maxConsecutiveFailures &&
            !health.isCircuitOpen
        ) {
            health.isCircuitOpen = true;
            health.circuitOpenUntil =
                block.timestamp +
                fallbackConfig.circuitBreakerDuration;

            emit CircuitBreakerTriggered(protocol, health.circuitOpenUntil);
        }
    }

    function _buildMultiHopParams(
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 minDebtAssetOut
    ) internal pure returns (ISwapAdapter.MultiHopParams memory params) {
        params = ISwapAdapter.MultiHopParams({
            tokenIn: collateralAsset,
            tokenOut: debtAsset,
            amountIn: collateralAmount,
            amountOut: 0, // Not used for exactInput
            minAmountOut: minDebtAssetOut, // Slippage protection
            maxAmountIn: type(uint256).max, // Not used for exactInput
            recipient: msg.sender, // Tokens received here
            deadline: block.timestamp + 300, // 5 minute deadline
            isExactInput: true // Exact input swap
        });
    }
}
