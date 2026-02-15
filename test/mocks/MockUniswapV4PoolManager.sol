// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolIdLibrary, PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @title IUnlockCallback
 * @notice Interface for contracts that implement unlock callbacks
 */
interface IUnlockCallback {
    function unlockCallback(
        bytes calldata data
    ) external returns (bytes memory);
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
        uint160 sqrtPriceX96; // Current sqrt(price) in Q64.96 format
        int24 tick; // Current tick
        uint128 liquidity; // Current liquidity
        bool initialized; // Whether the pool has been initialized
        uint24 protocolFee; // Protocol fee
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
    mapping(address => PriceData) public priceFeeds; // Mock price oracle

    uint256 private constant POOLS_SLOT = 6;

    // Global state for unlock mechanism
    bool private isUnlocked;
    address private currentUnlocker;
    mapping(address => int256) private currencyDeltas;
    mapping(address => uint256) private syncedBalances;

    // Pool counter for ID generation
    uint256 public poolCounter;

    // Configuration
    uint256 public protocolFeePercentage = 0; // in basis points
    uint256 public maxSwapSlippage = 500; // Default 5%

    // For tracking swaps
    mapping(PoolId => uint256) public swapCount;
    mapping(PoolId => uint256) public totalSwapVolume;

    // Events from Uniswap V4
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

    event Unlock(address indexed caller);
    event Settle(address indexed currency, uint256 amount);
    event Take(address indexed currency, address indexed to, uint256 amount);

    constructor() Ownable(msg.sender) {}

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

    // /**
    //  * @notice Initializes a pool with the given parameters
    //  * @param key The pool key
    //  * @param sqrtPriceX96 The initial sqrt price
    //  * @return tick The initial tick
    //  */
    // function initialize(
    //     PoolKey memory key,
    //     uint160 sqrtPriceX96
    // ) external returns (int24 tick) {
    //     require(sqrtPriceX96 > 0, "Invalid price");

    //     PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
    //     require(!pools[id].initialized, "Pool already initialized");

    //     // Initialize pool
    //     pools[id].sqrtPriceX96 = sqrtPriceX96;
    //     pools[id].tick = calculateTick(sqrtPriceX96);
    //     pools[id].liquidity = 100e18;
    //     pools[id].initialized = true;

    //     tick = pools[id].tick;

    //     emit Initialize(
    //         id,
    //         key.currency0,
    //         key.currency1,
    //         key.fee,
    //         key.tickSpacing,
    //         address(key.hooks),
    //         sqrtPriceX96,
    //         tick
    //     );

    //     // 

    //     bytes32 slot = keccak256(abi.encode(id, POOLS_SLOT));
    //     // Pack: sqrtPriceX96 (160 bits) | tick (24 bits) | protocolFee (24 bits) | lpFee (24 bits)
    //     bytes32 data = bytes32(uint256(sqrtPriceX96));
    //     assembly {
    //         sstore(slot, data)
    //     }

    //     // Store liquidity in the next slot
    //     uint128 initialLiquidity = 100e18;
    //     bytes32 liquiditySlot = bytes32(uint256(slot) + 1);
    //     assembly {
    //         sstore(liquiditySlot, initialLiquidity)
    //     }
    // }

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

        // Initialize pool with liquidity
        pools[id].sqrtPriceX96 = sqrtPriceX96;
        pools[id].tick = calculateTick(sqrtPriceX96);
        pools[id].liquidity = initialLiquidity;
        pools[id].initialized = true;

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

        // 🔑 Store data in the EXACT slots that StateLibrary expects
        _storePoolData(id, sqrtPriceX96, pools[id].tick, initialLiquidity);
        
        return tick;
    }

    /**
    * @notice Internal function to store pool data in correct storage slots
    * @dev This matches the storage layout expected by StateLibrary
    */
    function _storePoolData(
        PoolId id,
        uint160 sqrtPriceX96,
        int24 tick,
        uint128 liquidity
    ) internal {
        // Calculate base slot for this pool
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(id), POOLS_SLOT));
        
        // Slot 0: sqrtPriceX96 + tick + protocolFee + lpFee
        uint256 packed = uint256(sqrtPriceX96);
        packed |= (uint256(uint24(tick)) << 160);
        // Add fees if needed (currently 0)
        
        assembly {
            sstore(stateSlot, packed)
        }
        
        // Slot 1: feeGrowthGlobal0X128 (store 0 for now)
        bytes32 feeGrowth0Slot = bytes32(uint256(stateSlot) + 1);
        assembly {
            sstore(feeGrowth0Slot, 0)
        }
        
        // Slot 2: feeGrowthGlobal1X128 (store 0 for now)
        bytes32 feeGrowth1Slot = bytes32(uint256(stateSlot) + 2);
        assembly {
            sstore(feeGrowth1Slot, 0)
        }
        
        // ✅ Slot 3: liquidity (THIS IS WHERE StateLibrary EXPECTS IT!)
        bytes32 liquiditySlot = bytes32(uint256(stateSlot) + 3);
        assembly {
            sstore(liquiditySlot, liquidity)
        }
    }

    /**
    * @notice Sets liquidity for a pool (for testing purposes)
    * @param key The pool key
    * @param newLiquidity The liquidity amount to set
    */
    function setLiquidity(PoolKey memory key, uint128 newLiquidity) external {
        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        require(pools[id].initialized, "Pool not initialized");
        pools[id].liquidity = newLiquidity;
        
        // Also update the storage slot for extsload compatibility
        bytes32 slot = keccak256(abi.encode(id, POOLS_SLOT));
        bytes32 liquiditySlot = bytes32(uint256(slot) + 1); // Next slot for liquidity
        
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

        // Calculate swap amounts
        (uint256 amountIn, uint256 amountOut) = calculateSwapAmounts(
            pool,
            params.amountSpecified,
            params.zeroForOne
        );

        // Update pool price (simplified)
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

        // CONSTRUCT THE BALANCE DELTA
        int128 amount0;
        int128 amount1;
        
        if (params.zeroForOne) {
            // Swapping token0 for token1
            // amount0 is positive (we're taking from user)
            // amount1 is negative (we're giving to user)
            amount0 = int128(int256(amountIn));
            amount1 = -int128(int256(amountOut));
        } else {
            // Swapping token1 for token0
            // amount0 is negative (we're giving to user)
            // amount1 is positive (we're taking from user)
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
                ? int128(int256(amountOut))
                : -int128(int256(amountIn)),
            pool.sqrtPriceX96,
            pool.liquidity,
            pool.tick,
            key.fee
        );

        // RETURN THE CONSTRUCTED BALANCE DELTA
        swapDelta = toBalanceDelta(amount0, amount1);

        return swapDelta;
    }

    /**
    * @notice Helper to create a BalanceDelta
    * @param amount0 The amount0 delta
    * @param amount1 The amount1 delta
    * @return The BalanceDelta
    */
    function toBalanceDelta(
        int128 amount0,
        int128 amount1
    ) internal pure returns (BalanceDelta) {
        // BalanceDelta packs two int128s into a single int256
        // Upper 128 bits: amount0
        // Lower 128 bits: amount1
        int256 packed = (int256(amount0) << 128) | (int256(uint256(uint128(amount1))));
        return BalanceDelta.wrap(packed);
    }

    /**
     * @notice Borrows currency from the pool (used in flash loans)
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

        // Check balance
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance in pool"
        );

        // Update delta
        currencyDeltas[currencyAddr] -= int256(amount);

        // Transfer
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
        syncedBalances[currencyAddr] = IERC20(currencyAddr).balanceOf(
            address(this)
        );
    }

    /**
     * @notice Settles the amount owed for the currencydelta
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
    function settleFor(
        address recipient
    ) external payable returns (uint256 paid) {
        require(isUnlocked, "Must be unlocked");
        require(recipient != address(0), "Invalid recipient");
        paid = msg.value;
        emit Settle(recipient, paid);
    }

    /**
     * @notice Sets a mock price for an asset
     * @param asset The asset address
     * @param sqrtPriceX96 The sqrt price in Q64.96
     * @param liquidity The liquidity
     * @param fee The fee
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
     * @param asset The asset address
     * @return The price data
     */
    function getPriceData(
        address asset
    ) external view returns (PriceData memory) {
        return priceFeeds[asset];
    }

    /**
     * @notice Gets pool state
     * @param key The pool key
     * @return sqrtPriceX96 Current sqrt price
     * @return tick Current tick
     * @return liquidity Current liquidity
     */
    function getPoolState(
        PoolKey memory key
    )
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
     * @return Whether currently unlocked
     */
    function getUnlockState() external view returns (bool) {
        return isUnlocked;
    }

    /**
     * @notice Gets a currency delta
     * @param currency The currency address
     * @return The delta
     */
    function getCurrencyDelta(address currency) external view returns (int256) {
        return currencyDeltas[currency];
    }

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
        require(s.initialized, "Pool not initialized!");  // ✅ Add check here
        return (s.sqrtPriceX96, s.tick, s.protocolFee, s.protocolFee);
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }
    
    function extsload(bytes32[] calldata slots) 
        external 
        view 
        returns (bytes32[] memory) 
    {
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

    // Internal helper functions

    /**
     * @notice Calculates swap amounts
     * @param pool The pool
     * @param amountSpecified The amount specified
     * @param zeroForOne Trade direction
     */
    // function calculateSwapAmounts(
    //     Pool storage pool,
    //     int256 amountSpecified,
    //     bool zeroForOne
    // ) internal view returns (uint256 amountIn, uint256 amountOut) {
    //     uint256 absAmount = amountSpecified > 0
    //         ? uint256(amountSpecified)
    //         : uint256(-amountSpecified);

    //     // Simplified: 1% slippage
    //     if (amountSpecified < 0) {
    //         // Exact input
    //         amountIn = absAmount;
    //         amountOut = (amountIn * 99) / 100;
    //     } else {
    //         // Exact output
    //         amountOut = absAmount;
    //         amountIn = (amountOut * 101) / 100;
    //     }
    // }

    function calculateSwapAmounts(
        Pool storage pool,
        int256 amountSpecified,
        bool zeroForOne
    ) internal view returns (uint256 amountIn, uint256 amountOut) {
        uint256 absAmount = amountSpecified > 0
            ? uint256(amountSpecified)
            : uint256(-amountSpecified);

        // 🔑 USE REAL UNISWAP MATH
        if (amountSpecified < 0) {
            // Exact input
            amountIn = absAmount;
            amountOut = absAmount * 1400e18 / 1e18;
            
            // // Apply fee (assuming 0.3% = 3000)
            // uint256 amountInWithFee = (amountIn * 997000) / 1000000;
            
            // // Calculate using real Uniswap math
            // uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
            //     pool.sqrtPriceX96,
            //     pool.liquidity,
            //     amountInWithFee,
            //     zeroForOne
            // );
            
            // if (zeroForOne) {
            //     amountOut = SqrtPriceMath.getAmount1Delta(
            //         nextSqrtPrice,
            //         pool.sqrtPriceX96,
            //         pool.liquidity,
            //         false
            //     );
            // } else {
            //     amountOut = SqrtPriceMath.getAmount0Delta(
            //         pool.sqrtPriceX96,
            //         nextSqrtPrice,
            //         pool.liquidity,
            //         false
            //     );
            // }
        } else {
            // Exact output
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
            
            // Add fee back
            amountIn = (amountIn * 1000000) / 997000 + 1;
        }
    }

    /**
     * @notice Calculates tick from sqrt price
     * @param sqrtPriceX96 The sqrt price
     * @return The tick
     */
    function calculateTick(uint160 sqrtPriceX96) internal pure returns (int24) {
        // Simplified: just return a mock tick based on price
        // Real implementation would use more complex math
        return int24(int256(uint256(sqrtPriceX96)) / 1e10);
    }

    /**
     * @notice Helper to get minimum of two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Gets swap statistics for a pool
     * @param key The pool key
     * @return count Number of swaps
     * @return volume Total swap volume
     */
    function getSwapStats(
        PoolKey memory key
    ) external view returns (uint256 count, uint256 volume) {
        PoolId id = PoolId.wrap(keccak256(abi.encode(key)));
        return (swapCount[id], totalSwapVolume[id]);
    }

    /**
     * @notice Sets protocol fee percentage
     * @param newPercentage The new percentage in basis points
     */
    function setProtocolFeePercentage(
        uint256 newPercentage
    ) external onlyOwner {
        require(newPercentage <= 10000, "Invalid percentage");
        protocolFeePercentage = newPercentage;
    }

    /**
     * @notice Allows depositing tokens to the pool as liquidity
     * @param token The token address
     * @param amount The amount to deposit
     */
    function depositLiquidity(address token, uint256 amount) external {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount must be greater than zero");

        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Allows withdrawing tokens from the pool
     * @param token The token address
     * @param amount The amount to withdraw
     */
    function withdrawLiquidity(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount must be greater than zero");

        IERC20(token).transfer(msg.sender, amount);
    }

    /**
     * @notice Gets the balance of a token in the pool
     * @param token The token address
     * @return The balance
     */
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Receives ETH
     */
    receive() external payable {}
}

// Structs for swap parameters (matching Uniswap V4)
struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}
