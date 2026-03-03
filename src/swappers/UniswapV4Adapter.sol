// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    IUnlockCallback
} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import {ISwapAdapter} from "../interfaces/swapAdapter/ISwapAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MAX_SQRT_PRICE, MIN_SQRT_PRICE} from "../types/Constants.sol";

/// @title UniswapV4Adapter
/// @notice Uniswap V4 swap adapter implementing ISwapAdapter
/// @dev Handles multi-hop swaps across Uniswap V4 pools with flash loan support
contract UniswapV4Adapter is Ownable, ISwapAdapter, IUnlockCallback {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    /// @notice The Uniswap V4 PoolManager contract
    IPoolManager public immutable poolManager;

    /// @notice Provider identifier for this adapter
    bytes32 private constant PROTOCOL_ID = keccak256("UNISWAP_V4");

    /// @notice Counter for total swap calls
    uint256 private callCount;

    /// @notice Maps token pair to registered swap path
    mapping(bytes32 => ISwapAdapter.SwapPath) private registeredPaths;

    /// ERRORS ///

    /// @notice Thrown when swap output is below minimum
    error InsufficientSwapOutput();

    /// @notice Thrown when input exceeds expected amount
    error ExcessInputAmount();

    /// @notice Thrown when pool is not initialized
    error PoolNotInitialized();

    /// @notice Thrown when tokens don't match pool tokens
    error TokenMismatch();

    /// @notice Thrown when fee tiers don't match
    error FeeMismatch();

    /// @notice Thrown when address is zero
    error InvalidAddress();

    /// @notice Thrown when path has fewer than 2 tokens
    error PathHasLessTokens();

    /// @notice Thrown when input token doesn't match path start
    error TokenInMismatch();

    /// @notice Thrown when output token doesn't match path end
    error TokenOutMismatch();

    /// @notice Thrown when pool data length doesn't match tokens - 1
    error InsufficientPoolKeys();

    /// @notice Thrown when fees array length doesn't match pool data
    error InsufficientFeesToPoolKeys();

    /// @notice Thrown when price or liquidity is zero
    error InvalidPriceOrLiquidity();

    /// @notice Thrown when caller is not PoolManager
    error NotPoolManager();

    /// @notice Thrown when output is below minimum after swap
    /// @param finalAmountOut Actual output received
    /// @param minAmountOut Minimum output required
    error InsufficientAmountOut(uint256 finalAmountOut, uint256 minAmountOut);

    /// @notice Initializes the adapter
    /// @param _poolManager Address of Uniswap V4 PoolManager
    constructor(address _poolManager) Ownable(msg.sender) {
        require(_poolManager != address(0), "Invalid Address");
        poolManager = IPoolManager(_poolManager);

        callCount = 0;
    }

    /// @notice Modifier to ensure only PoolManager can call
    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    /// @notice Executes a multi-hop swap
    /// @dev Supports both exact input and exact output swaps
    /// @param params The multi-hop swap parameters
    /// @param loanProviderId The flash loan provider ID for routing
    /// @return amountIn Actual input amount used
    /// @return amountOut Actual output amount received
    function swapMultiHop(
        MultiHopParams calldata params,
        bytes32 loanProviderId
    ) external override returns (uint256 amountIn, uint256 amountOut) {
        callCount++;
        
        // Fetch SwapPath based on type of swap protocol to use
        ISwapAdapter.SwapPath memory swapPath = getSwapPath(
            params.tokenIn,
            params.tokenOut
        );

        // check if poolManager is unlocked
        bool isUnlocked = loanProviderId == PROTOCOL_ID;

        if(isUnlocked) {
            (amountIn, amountOut) = _executeSwap(params, swapPath);
        } else {
            // Execute through PoolManager's unlock callback
            bytes memory result = poolManager.unlock(abi.encode(params, swapPath));
            (amountIn, amountOut) = abi.decode(result, (uint256, uint256));
        }

        // Validate slippage
        if (params.isExactInput) {
            if(amountOut <= params.minAmountOut) revert InsufficientSwapOutput();
        } else {
            if(amountIn > params.maxAmountIn) revert ExcessInputAmount();
        }
    }

    /// @notice Uniswap V4 callback for executing swaps during unlock
    /// @dev Called by PoolManager when this contract initiates unlock
    /// @param data Encoded params and swap path
    /// @return Encoded amountIn and amountOut
    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        // decode data
        (MultiHopParams memory params, SwapPath memory path) = abi.decode(
            data,
            (MultiHopParams, SwapPath)
        );

        // execute swap
        (uint256 amountIn, uint256 amountOut) =  _executeSwap(params, path);

        return abi.encode(amountIn, amountOut);
    }

    /// @notice Quotes a multi-hop swap (view function)
    /// @dev Simulates swap without executing to get expected output
    /// @param params The multi-hop swap parameters
    /// @return amountIn Expected input amount
    /// @return amountOut Expected output amount
    function quoteMultiHop(
        MultiHopParams calldata params
    ) external view override returns (uint256 amountIn, uint256 amountOut) {
        SwapPath memory path = getSwapPath(
            params.tokenIn, 
            params.tokenOut
        );

        uint256 currentAmount = params.isExactInput
            ? params.amountIn
            : params.amountOut;

        Currency currentCurrency = Currency.wrap(params.tokenIn);

        for (uint256 i = 0; i < path.poolData.length; i++) {
            PoolKey memory poolKey = abi.decode(
                path.poolData[i],
                (PoolKey)
            );

            // Get current pool state
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(
                poolKey.toId()
            );

            // Get liquidity for accurate quoting
            uint128 liquidity = poolManager.getLiquidity(poolKey.toId());

            bool zeroForOne = Currency.unwrap(currentCurrency) ==
                Currency.unwrap(poolKey.currency0);

            // Calculate the output amount for this hop
            if (params.isExactInput) {
                currentAmount = _quoteExactInputSingle(
                    currentAmount,
                    sqrtPriceX96,
                    liquidity,
                    zeroForOne,
                    poolKey.fee
                );
            } else {
                currentAmount = _quoteExactOutputSingle(
                    currentAmount,
                    sqrtPriceX96,
                    liquidity,
                    zeroForOne,
                    poolKey.fee
                );
            }

            currentCurrency = zeroForOne
                ? poolKey.currency1
                : poolKey.currency0;
        }

        return
            params.isExactInput
                ? (params.amountIn, currentAmount)
                : (currentAmount, params.amountOut);
    }

    /// @notice Returns the protocol identifier
    /// @return PROTOCOL_ID (keccak256("UNISWAP_V4"))
    function protocolId() external pure override returns (bytes32) {
        return PROTOCOL_ID;
    }

    /// @notice Validates if a swap path is supported
    /// @dev Checks array lengths and validates each hop
    /// @param path The swap path to validate
    /// @return True if path is valid and supported
    function isPathSupported(
        SwapPath calldata path
    ) external view override returns (bool) {
        // Validate array lengths
        if (path.tokens.length < 2 || 
            path.poolData.length != path.tokens.length - 1) {
            return false;
        }
        
        if (path.fees.length > 0 && path.fees.length != path.poolData.length) {
            return false;
        }
        
        // Check each pool
        for (uint256 i = 0; i < path.poolData.length; i++) {
            if (!_isHopValid(path, i)) {
                return false;
            }
        }
        
        return true;
    }

    /// @notice Validates a specific hop in the swap path
    /// @dev Checks pool exists and tokens match
    /// @param path The swap path
    /// @param hopIndex The index of the hop to validate
    function _validateHop(
        SwapPath calldata path,
        uint256 hopIndex
    ) external view {
        PoolKey memory poolKey = abi.decode(path.poolData[hopIndex], (PoolKey));
        
        // Check pool exists
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());
        if(sqrtPriceX96 == 0) revert PoolNotInitialized();
        
        // Check tokens match
        address token0 = Currency.unwrap(poolKey.currency0);
        address token1 = Currency.unwrap(poolKey.currency1);
        address expectedIn = path.tokens[hopIndex];
        address expectedOut = path.tokens[hopIndex + 1];
        
        if(
            token0 != expectedIn || token1 != expectedOut
        ) revert TokenMismatch();
        
        // Check fee if provided
        if (path.fees.length > 0) {
            if(poolKey.fee != path.fees[hopIndex]) revert FeeMismatch();
        }
    }

    /// @notice Registers a new swap path for a token pair
    /// @dev Only callable by owner
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param path Array of token addresses in order
    /// @param poolData Array of encoded PoolKeys for each hop
    /// @param fees Array of fee tiers for each hop
    function registerSwapPath(
        address tokenIn,
        address tokenOut,
        address[] calldata path,
        bytes[] calldata poolData,
        uint24[] calldata fees
    ) external override onlyOwner {
        if(
            tokenIn == address(0) ||
            tokenOut == address(0)
        ) revert InvalidAddress();
        if(path.length < 2) revert PathHasLessTokens();
        if(path[0] != tokenIn) revert TokenInMismatch();
        if(path[path.length - 1] != tokenOut) revert TokenOutMismatch();
        if(poolData.length != path.length - 1) revert InsufficientPoolKeys();
        if(fees.length != path.length - 1) revert InsufficientFeesToPoolKeys();

        bytes32 pathKey = _getPathKey(tokenIn, tokenOut);
        registeredPaths[pathKey] = ISwapAdapter.SwapPath({
            tokens: path,
            poolData: poolData,
            fees: fees
        });

        emit ISwapAdapter.SwapPathRegistered(
            tokenIn,
            tokenOut,
            path,
            poolData,
            fees
        );
    }

    /// @notice Retrieves the registered swap path for a token pair
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @return path The registered SwapPath struct
    function getSwapPath(
        address tokenIn,
        address tokenOut
    ) public view override returns (ISwapAdapter.SwapPath memory path) {
        bytes32 pathKey = _getPathKey(tokenIn, tokenOut);
        return registeredPaths[pathKey];
    }

    receive() external payable {}

    // Internal helper functions

    /// @notice Settles a currency with the PoolManager
    /// @param currency The currency to settle
    /// @param from Address providing the tokens
    /// @param amount Amount to settle
    function _settle(Currency currency, address from, uint256 amount) internal {
        IERC20(Currency.unwrap(currency)).safeTransferFrom(
            from,
            address(poolManager),
            amount
        );
        poolManager.settle();
    }

    /// @notice Takes tokens from the PoolManager
    /// @param currency The currency to take
    /// @param to Address to receive tokens
    /// @param amount Amount to take
    function _take(Currency currency, address to, uint256 amount) internal {
        poolManager.take(currency, to, amount);
    }

    /// @notice Quotes exact input single hop swap
    /// @param amountIn Amount of input token
    /// @param sqrtPriceX96 Current sqrt price
    /// @param liquidity Pool liquidity
    /// @param zeroForOne Swap direction flag
    /// @param fee Pool fee tier
    /// @return amountOut Expected output amount
    function _quoteExactInputSingle(
        uint256 amountIn,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        bool zeroForOne,
        uint24 fee
    ) internal pure returns (uint256 amountOut) {
        if (sqrtPriceX96 == 0 || liquidity == 0) revert InvalidPriceOrLiquidity();
        // Apply fee to input amount
        uint256 amountInWithFee = (amountIn * (1000000 - fee)) / 1000000;

        // Calculate next sqrt price after consuming the input amount
        uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtPriceX96,
            liquidity,
            amountInWithFee,
            zeroForOne
        );

        // Calculate the amount out from the price change
        if (zeroForOne) {
            amountOut = SqrtPriceMath.getAmount1Delta(
                nextSqrtPrice,
                sqrtPriceX96,
                liquidity,
                false
            );
        } else {
            amountOut = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                nextSqrtPrice,
                liquidity,
                false
            );
        }
    }

    /// @notice Quotes exact output single hop swap
    /// @param amountOut Desired output amount
    /// @param sqrtPriceX96 Current sqrt price
    /// @param liquidity Pool liquidity
    /// @param zeroForOne Swap direction flag
    /// @param fee Pool fee tier
    /// @return amountIn Required input amount
    function _quoteExactOutputSingle(
        uint256 amountOut,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        bool zeroForOne,
        uint24 fee
    ) internal pure returns (uint256 amountIn) {
        if (sqrtPriceX96 == 0 || liquidity == 0) revert InvalidPriceOrLiquidity();
        // Calculate next sqrt price needed to output the desired amount
        uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromOutput(
            sqrtPriceX96,
            liquidity,
            amountOut,
            zeroForOne
        );

        // Calculate the amount in needed from the price change
        if (zeroForOne) {
            amountIn = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                nextSqrtPrice,
                liquidity,
                true
            );
        } else {
            amountIn = SqrtPriceMath.getAmount1Delta(
                nextSqrtPrice,
                sqrtPriceX96,
                liquidity,
                true
            );
        }

        // Add fee back to the input amount
        amountIn = (amountIn * 1000000) / (1000000 - fee) + 1;
    }

    /// @notice Generates a key for storing/looking up swap paths
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @return Key for path mapping
    function _getPathKey(
        address tokenIn,
        address tokenOut
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

    /// @notice Checks if a hop is valid (pool exists and tokens match)
    /// @param path The swap path
    /// @param hopIndex Index of the hop to check
    /// @return True if hop is valid
    function _isHopValid(
        SwapPath calldata path,
        uint256 hopIndex
    ) internal view returns (bool) {
        try this._validateHop(path, hopIndex) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Executes the multi-hop swap
    /// @dev Iterates through each pool in the path and executes swaps
    /// @param params The swap parameters
    /// @param path The registered swap path
    /// @return amountIn Actual input amount used
    /// @return amountOut Actual output amount received
    function _executeSwap(
        MultiHopParams memory params,
        SwapPath memory path
    ) internal returns(uint256, uint256) {
        uint256 currentAmount = params.isExactInput
            ? params.amountIn
            : params.amountOut;

        Currency currentCurrency = Currency.wrap(params.tokenIn);

        // Execute each hop
        for (uint256 i = 0; i < path.poolData.length; i++) {
            PoolKey memory poolKey = abi.decode(path.poolData[i], (PoolKey));

            // zeroForOne is a boolean flag that indicates the swap direction in the pool:
            //  true: Trade currency0 → currency1 (selling currency0)
            //  false: Trade currency1 → currency0 (selling currency1)
            bool zeroForOne = Currency.unwrap(currentCurrency) ==
                Currency.unwrap(poolKey.currency0);

            // Determine amount based on swap direction
            // amountSpecified < 0 = amount in
            // amountSpecified > 0 = amount out
            int256 specifiedAmount;
            if (params.isExactInput) {
                // Exact input: negative amount (selling)
                specifiedAmount = -int256(currentAmount);
            } else {
                // Exact output: positive amount (buying)
                // For last hop, use final amount; else use max
                if (i == path.poolData.length - 1) {
                    specifiedAmount = int256(currentAmount);
                } else {
                    specifiedAmount = type(int256).max; // Max intermediate
                }
            }

            BalanceDelta delta = poolManager.swap(
                poolKey,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: specifiedAmount,
                    sqrtPriceLimitX96: zeroForOne
                        ? MIN_SQRT_PRICE + 1
                        : MAX_SQRT_PRICE - 1
                }),
                "" // No hook data
            );

            // Update for next iteration
            int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
            currentAmount = uint256(uint128(-outputAmount));
            currentCurrency = zeroForOne
                ? poolKey.currency1
                : poolKey.currency0;
        }

        // Take final output
        uint256 finalAmountOut = params.isExactInput
            ? currentAmount
            : params.amountOut;

        if (finalAmountOut <= params.minAmountOut) {
            revert InsufficientAmountOut(finalAmountOut, params.minAmountOut);
        }

        // Take debt
        _take(currentCurrency, params.recipient, finalAmountOut);

        // Sync
        poolManager.sync(Currency.wrap(params.tokenIn));

        // Settle initial debt
        uint256 finalAmountIn = params.isExactInput
            ? params.amountIn
            : currentAmount;
        _settle(Currency.wrap(params.tokenIn), params.recipient, finalAmountIn);

        return (finalAmountIn, finalAmountOut);
    }

    /// @notice Verifies caller is the PoolManager
    function _onlyPoolManager() internal view {
        if(msg.sender != address(poolManager)) revert NotPoolManager();
    }
}
