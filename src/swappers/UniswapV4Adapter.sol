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

contract UniswapV4Adapter is Ownable, ISwapAdapter, IUnlockCallback {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;

    bytes32 private constant PROTOCOL_ID = keccak256("UNISWAP_V4");

    uint256 private callCount;

    mapping(bytes32 => ISwapAdapter.SwapPath) private registeredPaths;

    /// ERRORS ///

    error InsufficientSwapOutput();
    error ExcessInputAmount();
    error PoolNotInitialized();
    error TokenMismatch();
    error FeeMismatch();
    error InvalidAddress();
    error PathHasLessTokens();
    error TokenInMismatch();
    error TokenOutMismatch();
    error InsufficientPoolKeys();
    error InsufficientFeesToPoolKeys();
    error InvalidPriceOrLiquidity();
    error NotPoolManager();
    error InsufficientAmountOut(uint256 finalAmountOut, uint256 minAmountOut);

    constructor(address _poolManager) Ownable(msg.sender) {
        require(_poolManager != address(0), "Invalid Address");
        poolManager = IPoolManager(_poolManager);

        callCount = 0;
    }

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

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

    function protocolId() external pure override returns (bytes32) {
        return PROTOCOL_ID;
    }

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
            (token0 == expectedIn && token1 == expectedOut) ||
            (token1 == expectedIn && token0 == expectedOut)
        ) revert TokenMismatch();
        
        // Check fee if provided
        if (path.fees.length > 0) {
            if(poolKey.fee != path.fees[hopIndex]) revert FeeMismatch();
        }
    }

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

    function getSwapPath(
        address tokenIn,
        address tokenOut
    ) public view override returns (ISwapAdapter.SwapPath memory path) {
        bytes32 pathKey = _getPathKey(tokenIn, tokenOut);
        return registeredPaths[pathKey];
    }

    receive() external payable {}

    // Internal helper functions

    function _settle(Currency currency, address from, uint256 amount) internal {
        IERC20(Currency.unwrap(currency)).safeTransferFrom(
            from,
            address(poolManager),
            amount
        );
        poolManager.settle();
    }

    function _take(Currency currency, address to, uint256 amount) internal {
        poolManager.take(currency, to, amount);
    }

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

    function _getPathKey(
        address tokenIn,
        address tokenOut
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIn, tokenOut));
    }

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

    function _onlyPoolManager() internal view {
        if(msg.sender != address(poolManager)) revert NotPoolManager();
    }
}
