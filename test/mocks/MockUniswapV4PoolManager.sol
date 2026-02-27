// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @title IUnlockCallback
 * @notice Interface for contracts that implement unlock callbacks
 */
interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/**
 * @title MockUniswapV4PoolManager
 * @notice Mock Uniswap V4 Pool Manager for testing
 * @dev Simulates core Uniswap V4 functionality: swaps, positions, and the unlock callback mechanism
 */
contract MockUniswapV4PoolManager is Ownable {
    using PoolIdLibrary for PoolKey;

    /// @notice Pool configuration and state
    struct Pool {
        uint160 sqrtPriceX96;   // Current sqrt(price) in Q64.96 format
        int24 tick;              // Current tick
        uint128 liquidity;       // Current liquidity
        bool initialized;        // Whether the pool has been initialized
        uint24 protocolFee;      // Protocol fee
        uint8 token0Decimals;    // Decimals of token0
        uint8 token1Decimals;    // Decimals of token1
    }

    /// @notice Currency balance tracking for unlock mechanism
    struct CurrencyDelta {
        int256 delta0;
        int256 delta1;
    }

    /// @notice Price oracle data
    struct PriceData {
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint24 fee;
    }

    // Pool storage
    mapping(PoolId => Pool) public pools;
    mapping(address => PriceData) public priceFeeds;

    uint256 private constant POOLS_SLOT = 6;

    // Global state for unlock mechanism
    bool private isUnlocked;
    address private currentUnlocker;
    mapping(address => int256) private currencyDeltas;
    mapping(address => uint256) private syncedBalances;

    // Pool counter for ID generation
    uint256 public poolCounter;

    // Configuration
    uint256 public protocolFeePercentage = 0;
    uint256 public maxSwapSlippage = 500;

    // For tracking swaps
    mapping(PoolId => uint256) public swapCount;
    mapping(PoolId => uint256) public totalSwapVolume;

    // Events
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        uint160 sqrtPriceX96,
        int24 tick
    );

    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    event SqrtPriceUpdated(
        PoolId indexed id,
        uint160 oldSqrtPriceX96,
        uint160 newSqrtPriceX96,
        int24 newTick
    );

    event Unlock(address indexed caller);
    event Settle(address indexed currency, uint256 amount);
    event Take(address indexed currency, address indexed to, uint256 amount);

    constructor() Ownable(msg.sender) {}

    // =========================================================================
    // Core unlock mechanism
    // =========================================================================

    /**
     * @notice Main unlock callback mechanism
     * @param data The data to pass to the callback
     * @return The result from the callback
     */
    function unlock(bytes calldata data) external returns (bytes memory) {
        require(!isUnlocked, "Already unlocked");

        isUnlocked = true;
        currentUnlocker = msg.sender;

        bytes memory result = IUnlockCallback(msg.sender).unlockCallback(data);

        require(isUnlocked, "Must stay unlocked");
        isUnlocked = false;

        emit Unlock(msg.sender);
        return result;
    }

    // =========================================================================
    // Pool initialization
    // =========================================================================

    /**
     * @notice Initializes a pool with the given parameters
     * @param key The pool key
     * @param sqrtPriceX96 The initial sqrt price
     * @param initialLiquidity The initial liquidity
     * @return tick The initial tick
     */
    function initialize(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        uint128 initialLiquidity
    ) external returns (int24 tick) {
        require(sqrtPriceX96 > 0, "Invalid price");

        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        require(!pools[id].initialized, "Pool already initialized");

        // Fetch decimals from tokens
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();

        // Initialize pool
        pools[id].sqrtPriceX96   = sqrtPriceX96;
        pools[id].tick            = calculateTick(sqrtPriceX96);
        pools[id].liquidity       = initialLiquidity;
        pools[id].initialized     = true;
        pools[id].token0Decimals  = decimals0;
        pools[id].token1Decimals  = decimals1;

        tick = pools[id].tick;

        emit Initialize(
            id,
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            address(key.hooks),
            sqrtPriceX96,
            tick
        );

        _storePoolData(id, sqrtPriceX96, tick, initialLiquidity);

        return tick;
    }

    // =========================================================================
    // Price update (call this whenever you simulate a price change in tests)
    // =========================================================================

    /**
     * @notice Updates the sqrtPriceX96 for an existing pool
     * @dev Call this in your tests whenever the oracle price changes so the
     *      swap math stays consistent with your liquidation math.
     * @param key The pool key
     * @param newSqrtPriceX96 The new sqrt price in Q64.96 format
     *
     * Example — drop from 2000 to 1600 USDC/WETH:
     *   Original sqrtPriceX96 ≈ 2967187660000000000000000000000  (2000 USDC/WETH)
     *   New      sqrtPriceX96 ≈ 2653120000000000000000000000000  (1600 USDC/WETH)
     *   Derivation: newPrice = oldPrice * sqrt(1600/2000) = oldPrice * sqrt(0.8)
     */
    function setSqrtPrice(PoolKey memory key, uint160 newSqrtPriceX96) external {
        require(newSqrtPriceX96 > 0, "Invalid price");

        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        require(pools[id].initialized, "Pool not initialized");

        Pool storage pool = pools[id];

        uint160 oldSqrtPriceX96 = pool.sqrtPriceX96;
        pool.sqrtPriceX96 = newSqrtPriceX96;
        pool.tick = calculateTick(newSqrtPriceX96);

        // Keep existing liquidity, update price + tick in extsload-compatible slots
        _storePoolData(id, newSqrtPriceX96, pool.tick, pool.liquidity);

        emit SqrtPriceUpdated(id, oldSqrtPriceX96, newSqrtPriceX96, pool.tick);
    }

    // =========================================================================
    // Storage layout helpers (must match StateLibrary slot expectations)
    // =========================================================================

    /**
     * @notice Internal function to store pool data in correct storage slots
     * @dev Matches the storage layout expected by StateLibrary / extsload
     */
    function _storePoolData(
        PoolId id,
        uint160 sqrtPriceX96,
        int24 tick,
        uint128 liquidity
    ) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(id), POOLS_SLOT));

        // Slot 0: sqrtPriceX96 (160 bits) | tick (24 bits) | fees
        uint256 packed = uint256(sqrtPriceX96);
        packed |= (uint256(uint24(tick)) << 160);

        assembly {
            sstore(stateSlot, packed)
        }

        // Slot 1: feeGrowthGlobal0X128
        bytes32 feeGrowth0Slot = bytes32(uint256(stateSlot) + 1);
        assembly {
            sstore(feeGrowth0Slot, 0)
        }

        // Slot 2: feeGrowthGlobal1X128
        bytes32 feeGrowth1Slot = bytes32(uint256(stateSlot) + 2);
        assembly {
            sstore(feeGrowth1Slot, 0)
        }

        // Slot 3: liquidity
        bytes32 liquiditySlot = bytes32(uint256(stateSlot) + 3);
        assembly {
            sstore(liquiditySlot, liquidity)
        }
    }

    // =========================================================================
    // Liquidity management
    // =========================================================================

    /**
     * @notice Sets liquidity for a pool (for testing purposes)
     * @param key The pool key
     * @param newLiquidity The liquidity amount to set
     */
    function setLiquidity(PoolKey memory key, uint128 newLiquidity) external {
        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        require(pools[id].initialized, "Pool not initialized");
        pools[id].liquidity = newLiquidity;

        bytes32 slot = keccak256(abi.encode(id, POOLS_SLOT));
        bytes32 liquiditySlot = bytes32(uint256(slot) + 1);

        assembly {
            sstore(liquiditySlot, newLiquidity)
        }
    }

    /**
     * @notice Gets liquidity for a pool
     * @param id The pool ID
     * @return The liquidity
     */
    function getLiquidity(PoolId id) external view returns (uint128) {
        require(pools[id].initialized, "Pool not initialized");
        return pools[id].liquidity;
    }

    // =========================================================================
    // Swap
    // =========================================================================

    /**
     * @notice Executes a swap in a pool
     * @param key The pool key
     * @param params Swap parameters
     * @param hookData Hook data (unused in mock)
     * @return swapDelta The balance delta
     */
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata hookData
    ) external returns (BalanceDelta swapDelta) {
        require(isUnlocked, "Must be unlocked");
        require(params.amountSpecified != 0, "Amount cannot be zero");

        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        require(pools[id].initialized, "Pool not initialized");

        Pool storage pool = pools[id];

        (uint256 amountIn, uint256 amountOut) = calculateSwapAmounts(
            pool,
            params.amountSpecified,
            params.zeroForOne
        );

        // Update pool price
        uint256 priceChangeRatio = (amountIn * 10000) /
            (pool.liquidity > 0 ? pool.liquidity : 1);

        if (params.zeroForOne) {
            pool.sqrtPriceX96 = uint160(
                (uint256(pool.sqrtPriceX96) *
                    (10000 - uint256(min(priceChangeRatio, 100)))) / 10000
            );
        } else {
            pool.sqrtPriceX96 = uint160(
                (uint256(pool.sqrtPriceX96) *
                    (10000 + uint256(min(priceChangeRatio, 100)))) / 10000
            );
        }

        pool.tick = calculateTick(pool.sqrtPriceX96);

        // Update deltas
        if (params.zeroForOne) {
            currencyDeltas[Currency.unwrap(key.currency0)] -= int256(amountIn);
            currencyDeltas[Currency.unwrap(key.currency1)] += int256(amountOut);
        } else {
            currencyDeltas[Currency.unwrap(key.currency0)] += int256(amountOut);
            currencyDeltas[Currency.unwrap(key.currency1)] -= int256(amountIn);
        }

        swapCount[id]++;
        totalSwapVolume[id] += amountIn;

        int128 amount0;
        int128 amount1;

        if (params.zeroForOne) {
            amount0 = int128(int256(amountIn));
            amount1 = -int128(int256(amountOut));
        } else {
            amount0 = -int128(int256(amountOut));
            amount1 = int128(int256(amountIn));
        }

        emit Swap(
            id,
            msg.sender,
            params.zeroForOne
                ? int128(int256(amountIn))
                : -int128(int256(amountOut)),
            params.zeroForOne
                ? -int128(int256(amountOut))
                : int128(int256(amountIn)),
            pool.sqrtPriceX96,
            pool.liquidity,
            pool.tick,
            key.fee
        );

        swapDelta = toBalanceDelta(amount0, amount1);
        return swapDelta;
    }

    // =========================================================================
    // Settlement / take / sync
    // =========================================================================

    /**
     * @notice Borrows currency from the pool (used in flash loans / swaps)
     * @param currency The currency to borrow
     * @param to The recipient
     * @param amount The amount to borrow
     */
    function take(Currency currency, address to, uint256 amount) external {
        require(isUnlocked, "Must be unlocked");
        require(amount > 0, "Amount cannot be zero");
        require(to != address(0), "Invalid recipient");

        address currencyAddr = Currency.unwrap(currency);
        IERC20 token = IERC20(currencyAddr);

        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance in pool"
        );

        currencyDeltas[currencyAddr] -= int256(amount);

        require(token.transfer(to, amount), "Transfer failed");

        emit Take(currencyAddr, to, amount);
    }

    /**
     * @notice Syncs the pool's balance for the given currency
     * @param currency The currency to sync
     */
    function sync(Currency currency) external {
        require(isUnlocked, "Must be unlocked");
        address currencyAddr = Currency.unwrap(currency);
        syncedBalances[currencyAddr] = IERC20(currencyAddr).balanceOf(address(this));
    }

    /**
     * @notice Settles the amount owed
     * @return paid The amount paid
     */
    function settle() external payable returns (uint256 paid) {
        require(isUnlocked, "Must be unlocked");
        paid = msg.value;
        emit Settle(address(0), paid);
    }

    /**
     * @notice Settles on behalf of a recipient
     * @param recipient The recipient address
     * @return paid The amount paid
     */
    function settleFor(address recipient) external payable returns (uint256 paid) {
        require(isUnlocked, "Must be unlocked");
        require(recipient != address(0), "Invalid recipient");
        paid = msg.value;
        emit Settle(recipient, paid);
    }

    // =========================================================================
    // Price oracle helpers
    // =========================================================================

    /**
     * @notice Sets a mock price for an asset
     */
    function setPriceData(
        address asset,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee
    ) external onlyOwner {
        priceFeeds[asset] = PriceData({
            sqrtPriceX96: sqrtPriceX96,
            liquidity: liquidity,
            fee: fee
        });
    }

    /**
     * @notice Gets the price data for an asset
     */
    function getPriceData(address asset) external view returns (PriceData memory) {
        return priceFeeds[asset];
    }

    // =========================================================================
    // View helpers
    // =========================================================================

    /**
     * @notice Gets pool state
     */
    function getPoolState(PoolKey memory key)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint128 liquidity)
    {
        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        require(pools[id].initialized, "Pool not initialized");
        sqrtPriceX96 = pools[id].sqrtPriceX96;
        tick = pools[id].tick;
        liquidity = pools[id].liquidity;
    }

    /**
     * @notice Gets the current unlock state
     */
    function getUnlockState() external view returns (bool) {
        return isUnlocked;
    }

    /**
     * @notice Gets a currency delta
     */
    function getCurrencyDelta(address currency) external view returns (int256) {
        return currencyDeltas[currency];
    }

    /**
     * @notice Gets slot0 data for a pool
     */
    function getSlot0(PoolId id)
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        )
    {
        Pool storage s = pools[id];
        require(s.initialized, "Pool not initialized");
        return (s.sqrtPriceX96, s.tick, s.protocolFee, s.protocolFee);
    }

    /**
     * @notice Raw storage slot read (for StateLibrary / extsload compatibility)
     */
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    /**
     * @notice Batch raw storage slot read
     */
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        bytes32[] memory values = new bytes32[](slots.length);
        for (uint256 i = 0; i < slots.length; i++) {
            assembly {
                mstore(
                    add(add(values, 32), mul(i, 32)),
                    sload(mload(add(add(slots.offset, 0), mul(i, 32))))
                )
            }
        }
        return values;
    }

    /**
     * @notice Gets swap statistics for a pool
     */
    function getSwapStats(PoolKey memory key)
        external
        view
        returns (uint256 count, uint256 volume)
    {
        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        return (swapCount[id], totalSwapVolume[id]);
    }

    // =========================================================================
    // Liquidity deposit / withdraw
    // =========================================================================

    /**
     * @notice Deposit tokens into the pool as liquidity
     * @dev Make sure to seed BOTH tokens with enough balance to cover swaps
     */
    function depositLiquidity(address token, uint256 amount) external {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraw tokens from the pool (owner only)
     */
    function withdrawLiquidity(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount must be greater than zero");
        IERC20(token).transfer(msg.sender, amount);
    }

    /**
     * @notice Gets the balance of a token held by the pool
     */
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // =========================================================================
    // Admin
    // =========================================================================

    /**
     * @notice Sets protocol fee percentage (basis points)
     */
    function setProtocolFeePercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 10000, "Invalid percentage");
        protocolFeePercentage = newPercentage;
    }

    receive() external payable {}

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /**
     * @notice Calculates swap amounts using real Uniswap SqrtPriceMath,
     *         with automatic decimal scaling between token0 and token1.
     *
     *         For exact-input (amountSpecified < 0):
     *           - Uses SqrtPriceMath.getNextSqrtPriceFromInput to find the new price
     *           - Derives amountOut and scales by the decimal difference
     *
     *         For exact-output (amountSpecified > 0):
     *           - Uses SqrtPriceMath.getNextSqrtPriceFromOutput
     *           - amountOut is already in the correct decimals (caller supplied)
     */
    function calculateSwapAmounts(
        Pool storage pool,
        int256 amountSpecified,
        bool zeroForOne
    ) internal view returns (uint256 amountIn, uint256 amountOut) {
        uint256 absAmount = amountSpecified > 0
            ? uint256(amountSpecified)
            : uint256(-amountSpecified);

        uint8 d0 = pool.token0Decimals;
        uint8 d1 = pool.token1Decimals;

        // if (amountSpecified < 0) {
        //     // ── Exact input ──────────────────────────────────────────────────
        //     amountIn = absAmount;
        //     uint256 amountInWithFee = (amountIn * 997000) / 1000000;

        //     uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
        //         pool.sqrtPriceX96,
        //         pool.liquidity,
        //         amountInWithFee,
        //         zeroForOne
        //     );

        //     if (zeroForOne) {
        //         // Selling token0, receiving token1
        //         amountOut = SqrtPriceMath.getAmount1Delta(
        //             nextSqrtPrice,
        //             pool.sqrtPriceX96,
        //             pool.liquidity,
        //             false
        //         );
        //         // SqrtPriceMath works in token0-normalised units (18 dec equivalent).
        //         // Scale the raw output to match token1's actual decimals.
        //         if (d0 > d1) {
        //             amountOut = amountOut / (10 ** uint256(d0 - d1));
        //         } else if (d1 > d0) {
        //             amountOut = amountOut * (10 ** uint256(d1 - d0));
        //         }
        //     } else {
        //         // Selling token1, receiving token0
        //         amountOut = SqrtPriceMath.getAmount0Delta(
        //             pool.sqrtPriceX96,
        //             nextSqrtPrice,
        //             pool.liquidity,
        //             false
        //         );
        //         // Scale to token0's actual decimals
        //         if (d1 > d0) {
        //             amountOut = amountOut / (10 ** uint256(d1 - d0));
        //         } else if (d0 > d1) {
        //             amountOut = amountOut * (10 ** uint256(d0 - d1));
        //         }
        //     }
        // } else {
        //     // ── Exact output ─────────────────────────────────────────────────
        //     // amountOut is provided by the caller in the correct decimals already
        //     amountOut = absAmount;

        //     uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromOutput(
        //         pool.sqrtPriceX96,
        //         pool.liquidity,
        //         amountOut,
        //         zeroForOne
        //     );

        //     if (zeroForOne) {
        //         amountIn = SqrtPriceMath.getAmount0Delta(
        //             pool.sqrtPriceX96,
        //             nextSqrtPrice,
        //             pool.liquidity,
        //             true
        //         );
        //     } else {
        //         amountIn = SqrtPriceMath.getAmount1Delta(
        //             nextSqrtPrice,
        //             pool.sqrtPriceX96,
        //             pool.liquidity,
        //             true
        //         );
        //     }

        //     // Add fee back
        //     amountIn = (amountIn * 1000000) / 997000 + 1;
        // }

        if (amountSpecified < 0) {
            amountIn = absAmount;

            // Apply 0.3% fee
            uint256 amountInWithFee = (amountIn * 997) / 1000;

            if (zeroForOne) {
                // Selling token0 (WETH, 18dec) → receiving token1 (USDC, 6dec)
                // price = sqrtPriceX96^2 / 2^192, then adjust for decimals
                //
                // amountOut (in token1 units) =
                //   amountIn (token0 units)
                //   * sqrtP^2 / 2^192          ← price ratio in raw units
                //   / 10^(d0 - d1)             ← decimal adjustment
                //
                // To avoid overflow, rearrange:
                //   amountOut = amountIn * sqrtP / 2^96 * sqrtP / 2^96 / 10^(d0-d1)

                uint256 sqrtP = uint256(pool.sqrtPriceX96);
                // Step 1: amountIn * sqrtP / 2^96  (intermediate, stays reasonable)
                uint256 step1 = (amountInWithFee * sqrtP) >> 96;
                // Step 2: step1 * sqrtP / 2^96
                uint256 step2 = (step1 * sqrtP) >> 96;
                // Step 3: adjust for decimal difference
                if (d0 > d1) {
                    amountOut = step2 / (10 ** uint256(d0 - d1));
                } else if (d1 > d0) {
                    amountOut = step2 * (10 ** uint256(d1 - d0));
                } else {
                    amountOut = step2;
                }
            } else {
                // Selling token1 (USDC, 6dec) → receiving token0 (WETH, 18dec)
                // Inverse: amountOut = amountIn * 2^192 / sqrtP^2 * 10^(d0-d1)

                uint256 sqrtP = uint256(pool.sqrtPriceX96);
                // Step 1: amountIn << 96 / sqrtP
                uint256 step1 = (amountInWithFee << 96) / sqrtP;
                // Step 2: step1 << 96 / sqrtP
                uint256 step2 = (step1 << 96) / sqrtP;
                // Step 3: adjust for decimal difference
                if (d0 > d1) {
                    amountOut = step2 * (10 ** uint256(d0 - d1));
                } else if (d1 > d0) {
                    amountOut = step2 / (10 ** uint256(d1 - d0));
                } else {
                    amountOut = step2;
                }
            }
        } else {
            // Exact output — keep existing logic
            amountOut = absAmount;

            uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromOutput(
                pool.sqrtPriceX96,
                pool.liquidity,
                amountOut,
                zeroForOne
            );

            if (zeroForOne) {
                amountIn = SqrtPriceMath.getAmount0Delta(
                    pool.sqrtPriceX96,
                    nextSqrtPrice,
                    pool.liquidity,
                    true
                );
            } else {
                amountIn = SqrtPriceMath.getAmount1Delta(
                    nextSqrtPrice,
                    pool.sqrtPriceX96,
                    pool.liquidity,
                    true
                );
            }

            amountIn = (amountIn * 1000000) / 997000 + 1;
        }
    }

    /**
     * @notice Helper to create a BalanceDelta (upper 128 = amount0, lower 128 = amount1)
     */
    function toBalanceDelta(int128 amount0, int128 amount1)
        internal
        pure
        returns (BalanceDelta)
    {
        int256 packed = (int256(amount0) << 128) | int256(uint256(uint128(amount1)));
        return BalanceDelta.wrap(packed);
    }

    /**
     * @notice Calculates tick from sqrtPriceX96 (simplified)
     */
    function calculateTick(uint160 sqrtPriceX96) internal pure returns (int24) {
        return int24(int256(uint256(sqrtPriceX96)) / 1e10);
    }

    /**
     * @notice Returns the smaller of two uint256 values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

// Structs for swap parameters (matching Uniswap V4)
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}
