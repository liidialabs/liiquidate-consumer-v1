// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISwapAdapter
 * @notice Universal interface that all DEX adapters must implement
 */
interface ISwapAdapter {
    
    /// @notice Swap parameters that work across all protocols
    struct SwapParams {
        address tokenIn;           // Input token address
        address tokenOut;          // Output token address
        uint256 amountIn;          // Exact input amount (0 if exactOut)
        uint256 amountOut;         // Exact output amount (0 if exactIn)
        uint256 minAmountOut;      // Minimum output for exactIn swaps
        uint256 maxAmountIn;       // Maximum input for exactOut swaps
        address recipient;         // Receiver of output tokens
        uint256 deadline;          // Transaction deadline
        bytes routeData;           // Protocol-specific route encoding
    }
    
    /// @notice Multi-hop swap path definition
    struct SwapPath {
        address[] tokens;          // Token path [tokenA, tokenB, tokenC]
        bytes[] poolData;          // Pool identifiers per hop
        uint24[] fees;             // Fee tiers per hop (optional)
    }
    
    /// @notice Complete multi-hop swap parameters
    struct MultiHopParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;          // For exactInput swaps
        uint256 amountOut;         // For exactOutput swaps
        uint256 minAmountOut;      // Slippage protection (exactIn)
        uint256 maxAmountIn;       // Slippage protection (exactOut)
        address recipient;
        uint256 deadline;
        bool isExactInput;         // true = exactIn, false = exactOut
    }

    /// @notice Event when a swap path is registered
    event SwapPathRegistered(
        address indexed tokenIn,
        address indexed tokenOut,
        address[] path,
        bytes[] poolData,
        uint24[] fees
    );
    
    /// @notice Execute a multi-hop swap
    /// @param params The swap parameters
    /// @return amountIn Actual input amount used
    /// @return amountOut Actual output amount received
    function swapMultiHop(
        MultiHopParams calldata params,
        bytes32 loanProviderId
    ) 
        external 
        returns (uint256 amountIn, uint256 amountOut);
    
    /// @notice Quote a multi-hop swap (view function)
    /// @param params The swap parameters
    /// @return amountIn Expected input amount
    /// @return amountOut Expected output amount
    function quoteMultiHop(MultiHopParams calldata params) 
        external 
        view 
        returns (uint256 amountIn, uint256 amountOut);
    
    /// @notice Get the protocol identifier
    /// @return Protocol name (e.g., "UniswapV3", "Balancer")
    function protocolId() external view returns (bytes32);
    
    /// @notice Check if a path is supported by this adapter
    /// @param path The swap path to check
    /// @return Whether the path is valid
    function isPathSupported(SwapPath calldata path) 
        external 
        view 
        returns (bool);
    
    function registerSwapPath(
        address tokenIn,
        address tokenOut,
        address[] calldata path,
        bytes[] calldata poolData,
        uint24[] calldata fees
    ) external;

    function getSwapPath(
        address tokenIn,
        address tokenOut
    ) 
        external 
        view 
        returns (SwapPath memory path);
    

}