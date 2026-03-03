// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISwapAdapter} from "./interfaces/swapAdapter/ISwapAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UniversalSwapRouter
 * @notice Routes swaps across multiple DEX protocols with fallback and circuit breaker support
 * @dev Supports multi-hop swaps, automatic protocol fallback, and circuit breakers
 *      for improved reliability when executing liquidation swaps
 */
contract UniversalSwapRouter is Ownable {
    /// @notice Tracks health metrics for each protocol adapter
    /// @dev Used to implement circuit breaker pattern for failing protocols
    struct ProtocolHealth {
        uint256 consecutiveFailures;  /// @dev Number of consecutive failures
        uint256 lastFailureTime;       /// @dev Timestamp of last failure
        uint256 totalAttempts;         /// @dev Total swap attempts
        uint256 totalFailures;         /// @dev Total failures
        bool isCircuitOpen;            /// @dev True = circuit broken, skip protocol
        uint256 circuitOpenUntil;     /// @dev Timestamp when circuit can close
    }

    /// @notice Configuration for fallback behavior
    struct FallbackConfig {
        uint256 maxRetries;                 /// @dev Max retries per protocol
        uint256 maxConsecutiveFailures;     /// @dev Failures before circuit opens
        uint256 circuitBreakerDuration;     /// @dev How long circuit stays open (seconds)
        uint256 fallbackSlippageBps;         /// @dev Extra slippage for fallback (in bps)
        bool enableAutoFallback;             /// @dev Enable automatic fallback
    }

    /// @notice Default Protocol ID as UniswapV4
    bytes32 public constant DEFAULT_PROTOCOL_ID = keccak256("UNISWAP_V4");

    /// @notice Base basis points for slippage calculations (10000 = 100%)
    uint16 private constant BASE_BPS = 1e4;

    /// @notice Maps protocol ID to swap adapter address
    mapping(bytes32 => address) public adapters;

    /// @notice Maps protocol ID to health metrics for circuit breaker
    mapping(bytes32 => ProtocolHealth) public protocolHealth;

    /// @notice Ordered list of protocol IDs for fallback sequence
    bytes32[] public protocolPriority;

    /// @notice List of all registered swap adapters
    address[] public swapAdapters;

    /// @notice Global fallback configuration
    FallbackConfig public fallbackConfig;

    /// @notice Emitted when a swap is attempted
    /// @param protocol The protocol ID used
    /// @param success Whether the swap succeeded
    /// @param reason Description of attempt result
    event SwapAttempted(bytes32 protocol, bool success, string reason);

    /// @notice Emitted when fallback to another protocol occurs
    /// @param fromProtocol The protocol that failed
    /// @param toProtocol The protocol being used as fallback
    /// @param user The user initiating the swap
    event ProtocolFallback(
        bytes32 fromProtocol,
        bytes32 toProtocol,
        address indexed user
    );

    /// @notice Emitted when circuit breaker is triggered
    /// @param protocol The protocol ID
    /// @param openUntil Timestamp when circuit may close
    event CircuitBreakerTriggered(bytes32 protocol, uint256 openUntil);

    /// @notice Emitted when circuit breaker is reset
    /// @param protocol The protocol ID
    event CircuitBreakerReset(bytes32 protocol);

    /// @notice Emitted when an adapter is registered
    /// @param protocol The protocol ID
    /// @param adapter The adapter address
    event AdapterRegistered(bytes32 protocol, address adapter);

    /// @notice Emitted when an adapter is removed
    /// @param protocol The protocol ID
    event AdapterRemoved(bytes32 protocol);

    /// @notice Emitted when a multi-hop swap executes
    /// @param protocol The protocol ID used
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Amount of input token
    /// @param amountOut Amount of output token received
    event MultiHopSwapExecuted(
        bytes32 protocol,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Emitted when trying a specific protocol
    /// @param protocol The protocol ID
    event SwapRoutedOn(bytes32 protocol);

    /// @notice Emitted when the default route fails
    /// @param protocol The protocol ID that was the default
    event DefaultRouteFailed(bytes32 protocol);

    /// @notice Emitted when protocol priority is set
    /// @param providers Array of protocol IDs in priority order
    event ProtocolPrioritySet(bytes32[] providers);

    /// @notice Errors

    /// @notice Thrown when an address parameter is zero
    error InvalidAddress();

    /// @notice Thrown when a protocol ID is zero
    error InvalidProtocol();

    /// @notice Thrown when protocol list is empty
    error EmptyProtocolList();

    /// @notice Thrown when a required config value is zero
    error CannotBeZero();

    /// @notice Thrown when an amount is zero
    error InvalidAmount();

    /// @notice Initializes contract with default fallback configuration
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

    /// @notice Registers a new swap adapter
    /// @dev The adapter's protocolId() is called to determine protocol identifier
    /// @param adapter The address of the swap adapter contract
    function registerAdapter(address adapter) external onlyOwner {
        if(adapter == address(0)) revert InvalidAddress();
        bytes32 protocol = ISwapAdapter(adapter).protocolId();
        adapters[protocol] = adapter;
        swapAdapters.push(adapter);
        emit AdapterRegistered(protocol, adapter);
    }

    /// @notice Removes a swap adapter
    /// @param protocol The protocol ID to remove
    function removeAdapter(bytes32 protocol) external onlyOwner {
        if(protocol == bytes32(0)) revert InvalidProtocol();
        delete adapters[protocol];
        emit AdapterRemoved(protocol);
    }

    /// @notice Sets the priority order for protocol fallback
    /// @param protocols Ordered array of protocol IDs (first = highest priority)
    function setProtocolPriority(
        bytes32[] calldata protocols
    ) external onlyOwner {
        if(protocols.length == 0) revert EmptyProtocolList();
        protocolPriority = protocols;
        emit ProtocolPrioritySet(protocols);
    }

    /// @notice Updates the fallback configuration
    /// @param config New FallbackConfig settings
    function updateFallbackConfig(
        FallbackConfig calldata config
    ) external onlyOwner {
        if(
            config.circuitBreakerDuration == 0 ||
            config.maxConsecutiveFailures == 0 ||
            config.maxRetries == 0 ||
            config.fallbackSlippageBps == 0
        ) revert CannotBeZero();

        fallbackConfig = config;
    }

    /// @notice Executes a multi-hop swap with automatic fallback
    /// @dev Tries protocols in priority order until one succeeds
    /// @param collateralAsset The input token (from liquidation)
    /// @param debtAsset The output token (to repay flash loan)
    /// @param collateralAmount Amount of input token to swap
    /// @param minDebtAssetOut Minimum output required (slippage protection)
    /// @param loanProviderId The flash loan provider ID for routing
    /// @return amountIn Actual amount of input token used
    /// @return amountOut Actual amount of output token received
    /// @return usedProtocol The protocol ID that was used
    function swapMultiHop(
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 minDebtAssetOut,
        bytes32 loanProviderId
    )
        external
        returns (uint256 amountIn, uint256 amountOut, bytes32 usedProtocol)
    {
        // Checks
        if(
            collateralAsset == address(0) ||
            debtAsset == address(0)
        ) revert InvalidAddress();
        if(
            collateralAmount == 0 ||
            minDebtAssetOut == 0
        ) revert InvalidAmount();
        if(loanProviderId == bytes32(0)) revert InvalidProtocol();

        // Build params
        ISwapAdapter.MultiHopParams memory params = _buildMultiHopParams(
            collateralAsset,
            debtAsset,
            collateralAmount,
            minDebtAssetOut
        );

        // get best protocol
        (bytes32 protocol, , ) = quoteBestProtocol(params);
        // Loop through available adapters
        (amountIn, amountOut, usedProtocol) = _executeTryMultiple(protocol, params, loanProviderId);
    }

    /// @notice Manually resets the circuit breaker for a protocol
    /// @param protocol The protocol ID to reset
    function resetCircuitBreaker(bytes32 protocol) external {
        if(protocol == bytes32(0)) revert InvalidProtocol();
        ProtocolHealth storage health = protocolHealth[protocol];
        health.isCircuitOpen = false;
        health.circuitOpenUntil = 0;
        health.consecutiveFailures = 0;
        emit CircuitBreakerReset(protocol);
    }

    /// @notice Gets health metrics for a protocol
    /// @param protocol The protocol ID to query
    /// @return ProtocolHealth struct with current metrics
    function getProtocolHealth(
        bytes32 protocol
    ) external view returns (ProtocolHealth memory) {
        if(protocol == bytes32(0)) revert InvalidProtocol();
        return protocolHealth[protocol];
    }

    // REDO
    /// @notice Quotes the best protocol for a given swap parameters
    /// @dev Simulates quotes from all available protocols and returns the best one
    /// @param params The multi-hop swap parameters
    /// @return bestProtocol The protocol ID with the best quote
    /// @return amountIn The input amount for the best quote
    /// @return amountOut The output amount for the best quote
    function quoteBestProtocol(
        ISwapAdapter.MultiHopParams memory params
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

        require(bestProtocol != bytes32(0), "No valid quotes");
    }

    // REDO
    /// @notice Gets a quote from a specific protocol
    /// @param protocol The protocol ID to query
    /// @param params The multi-hop swap parameters
    /// @return amountIn The input amount quoted
    /// @return amountOut The output amount quoted
    function quoteSpecific(
        bytes32 protocol,
        ISwapAdapter.MultiHopParams calldata params
    ) external view returns (uint256 amountIn, uint256 amountOut) {
        if(protocol == bytes32(0)) revert InvalidProtocol();
        address adapter = adapters[protocol];
        require(adapter != address(0), "Protocol not supported");

        return ISwapAdapter(adapter).quoteMultiHop(params);
    }

    /// @notice Returns all registered swap adapter addresses
    /// @return Array of adapter addresses
    function getSwapAdapters() external view returns (address[] memory) {
        return swapAdapters;
    }

    ///////////// INTERNAL FUNCTIONS ////////////////

    /// @notice Attempts swap across multiple protocols with fallback
    /// @dev Tries protocols in priority order, adjusting slippage for fallbacks
    /// @param _protocol The preferred protocol ID
    /// @param params The swap parameters
    /// @param loanProviderId The flash loan provider ID
    /// @return amountIn Actual input amount used
    /// @return amountOut Actual output amount received
    /// @return usedProtocol The protocol ID that succeeded
    function _executeTryMultiple(
        bytes32 _protocol,
        ISwapAdapter.MultiHopParams memory params,
        bytes32 loanProviderId
    ) internal returns(uint256, uint256, bytes32) {
        if(
            loanProviderId == bytes32(0) ||
            _protocol == bytes32(0)
        ) revert InvalidProtocol();

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
            ISwapAdapter.MultiHopParams memory adjustedParams = params;
            if (i > 0) {
                adjustedParams = _adjustSlippageForFallback(params, i);
            }

            // Attempt swap
            (
                bool success,
                uint256 resultAmountIn,
                uint256 resultAmountOut,
                string memory reason
            ) = _attemptSwap(protocol, adjustedParams, loanProviderId);

            //  Handle response
            if (success) {
                _recordSuccess(protocol);
                emit MultiHopSwapExecuted(
                    protocol,
                    params.tokenIn,
                    params.tokenOut,
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

    /// @notice Attempts a single swap with a protocol
    /// @param protocol The protocol ID to use
    /// @param params The swap parameters
    /// @param loanProviderId The flash loan provider ID
    /// @return success Whether the swap succeeded
    /// @return amountIn Actual input amount used
    /// @return amountOut Actual output amount received
    /// @return reason Description of the result
    function _attemptSwap(
        bytes32 protocol,
        ISwapAdapter.MultiHopParams memory params,
        bytes32 loanProviderId
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

        try ISwapAdapter(adapter).swapMultiHop(params, loanProviderId) returns (
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

    /// @notice Adjusts slippage tolerance for fallback attempts
    /// @dev Increases slippage tolerance with each fallback attempt
    /// @param params Original swap parameters
    /// @param fallbackIndex The index of the fallback (0 = first fallback)
    /// @return adjusted Modified params with increased slippage
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

    /// @notice Checks if circuit breaker is open for a protocol
    /// @dev Automatically closes circuit if current time exceeds circuitOpenUntil
    /// @param protocol The protocol ID to check
    /// @return True if circuit is open (protocol should be skipped)
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

    /// @notice Records a successful swap and resets circuit breaker
    /// @param protocol The protocol ID that succeeded
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

    /// @notice Records a failed swap and potentially triggers circuit breaker
    /// @dev Triggers circuit breaker if consecutive failures exceed threshold
    /// @param protocol The protocol ID that failed
    /// @param reason Description of the failure
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

    /// @notice Builds multi-hop swap parameters with defaults
    /// @dev Sets recipient to caller, deadline to 5 minutes, uses exact input
    /// @param collateralAsset Input token address
    /// @param debtAsset Output token address
    /// @param collateralAmount Amount of input token
    /// @param minDebtAssetOut Minimum output required
    /// @return params Configured MultiHopParams struct
    function _buildMultiHopParams(
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 minDebtAssetOut
    ) internal view returns (ISwapAdapter.MultiHopParams memory params) {
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
