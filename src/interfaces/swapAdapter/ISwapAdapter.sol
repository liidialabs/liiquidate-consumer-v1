// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISwapAdapter
/// @notice Universal interface that all DEX swap adapters must implement
/// @dev Provides a normalized interface for executing multi-hop swaps across different DEX protocols
interface ISwapAdapter {
    
    /// @notice Single hop swap parameters
    /// @dev Used for simple token-to-token swaps
    struct SwapParams {
        address tokenIn;           /// @dev Input token address
        address tokenOut;          /// @dev Output token address
        uint256 amountIn;          /// @dev Exact input amount (0 if exactOut)
        uint256 amountOut;         /// @dev Exact output amount (0 if exactIn)
        uint256 minAmountOut;      /// @dev Minimum output for exactIn swaps (slippage protection)
        uint256 maxAmountIn;       /// @dev Maximum input for exactOut swaps (slippage protection)
        address recipient;         /// @dev Receiver of output tokens
        uint256 deadline;          /// @dev Transaction deadline timestamp
        bytes routeData;           /// @dev Protocol-specific route encoding
    }
    
    /// @notice Multi-hop swap path definition
    /// @dev Defines the complete path for multi-hop swaps through multiple pools
    struct SwapPath {
        address[] tokens;          /// @dev Token path [tokenA, tokenB, tokenC]
        bytes[] poolData;          /// @dev Pool identifiers/keys per hop
        uint24[] fees;             /// @dev Fee tiers per hop (optional, can be empty)
    }
    
    /// @notice Complete multi-hop swap parameters
    /// @dev Used for executing multi-hop swaps with slippage protection
    struct MultiHopParams {
        address tokenIn;           /// @dev Input token address
        address tokenOut;          /// @dev Output token address
        uint256 amountIn;          /// @dev Input amount for exactInput swaps
        uint256 amountOut;         /// @dev Output amount for exactOutput swaps
        uint256 minAmountOut;      /// @dev Minimum output for exactInput (slippage protection)
        uint256 maxAmountIn;       /// @dev Maximum input for exactOutput (slippage protection)
        address recipient;         /// @dev Address receiving the output tokens
        uint256 deadline;          /// @dev Transaction deadline timestamp
        bool isExactInput;         /// @dev true = exactInput, false = exactOutput
    }

    /// @notice Emitted when a new swap path is registered
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param path Array of token addresses in the path
    /// @param poolData Array of encoded pool keys
    /// @param fees Array of fee tiers per hop
    event SwapPathRegistered(
        address indexed tokenIn,
        address indexed tokenOut,
        address[] path,
        bytes[] poolData,
        uint24[] fees
    );
    
    /// @notice Executes a multi-hop swap
    /// @dev Swaps tokens through registered paths, supporting both exact input and exact output
    /// @param params The multi-hop swap parameters
    /// @param loanProviderId The flash loan provider ID for routing (enables flash loan integration)
    /// @return amountIn Actual input amount used
    /// @return amountOut Actual output amount received
    function swapMultiHop(
        MultiHopParams calldata params,
        bytes32 loanProviderId
    ) 
        external 
        returns (uint256 amountIn, uint256 amountOut);
    
    /// @notice Quotes a multi-hop swap without executing
    /// @dev Simulates the swap to get expected input/output amounts
    /// @param params The multi-hop swap parameters
    /// @return amountIn Expected input amount
    /// @return amountOut Expected output amount
    function quoteMultiHop(MultiHopParams calldata params) 
        external 
        view 
        returns (uint256 amountIn, uint256 amountOut);
    
    /// @notice Returns the protocol identifier
    /// @return Protocol ID (e.g., keccak256("UNISWAP_V4"), keccak256("BALANCER"))
    function protocolId() external view returns (bytes32);
    
    /// @notice Validates if a swap path is supported
    /// @dev Checks that pools exist and tokens match
    /// @param path The swap path to validate
    /// @return True if path is valid and all pools exist
    function isPathSupported(SwapPath calldata path) 
        external 
        view 
        returns (bool);
    
    /// @notice Registers a new swap path for a token pair
    /// @dev Only callable by owner. Sets up pools and fees for multi-hop swaps.
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param path Array of token addresses in order
    /// @param poolData Array of encoded pool keys for each hop
    /// @param fees Array of fee tiers for each hop
    function registerSwapPath(
        address tokenIn,
        address tokenOut,
        address[] calldata path,
        bytes[] calldata poolData,
        uint24[] calldata fees
    ) external;

    /// @notice Retrieves the registered swap path for a token pair
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @return path The registered SwapPath struct
    function getSwapPath(
        address tokenIn,
        address tokenOut
    ) 
        external 
        view 
        returns (SwapPath memory path);
}