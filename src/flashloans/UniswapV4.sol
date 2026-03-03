// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IUnlockCallback
} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {UniversalSwapRouter} from "../UniversalSwapRouter.sol";
import {IFlashLoan} from "../interfaces/flashloans/IFlashLoan.sol";
import {LiquidationParams, LiquidationExecuted} from "../types/DataTypes.sol";

/// @title UniswapV4FlashLoan
/// @notice Uniswap V4 flash loan provider for liquidation execution
/// @dev Implements IFlashLoan using Uniswap V4's unlock mechanism.
///      Provides zero-fee flash loans by utilizing Uniswap's architecture.
contract UniswapV4 is Ownable, IFlashLoan, IUnlockCallback {
    using SafeERC20 for IERC20;

    /// @notice The Uniswap V4 PoolManager
    IPoolManager public immutable poolManager;

    /// @notice The UniversalSwapRouter for swapping collateral
    UniversalSwapRouter public immutable swapRouter;

    /// @notice Unique identifier for this provider
    bytes32 public constant PROVIDER_ID = keccak256("UNISWAP_V4");

    /// @notice Accumulates profit per debt asset
    mapping(address => uint256) private accumProfit;

    /// @notice Tracks which debt assets have been recorded
    mapping(address => bool) private isRecorded;

    /// @notice List of unique debt assets covered
    address[] debtCovered;

    /// @notice Counter for total flash loan calls
    uint256 public callCount;

    /// @notice Thrown when an address parameter is zero
    error InvalidAddress();

    /// @notice Thrown when caller is not the PoolManager
    error NotPoolManager();

    /// @notice Thrown when amount is zero
    error NoZeroAmount();

    /// @notice Thrown when liquidation call fails
    error LiquidationFailed();

    /// @notice Thrown when no collateral is received from liquidation
    error NoCollateralSeized();

    /// @notice Thrown when swapped output is insufficient
    error InsufficientSwapOutput();

    /// @notice Thrown when no profit is generated
    error NotProfitable();

    /// @notice Initializes the UniswapV4 flash loan provider
    /// @param _poolManager Address of Uniswap V4 PoolManager
    /// @param _swapRouter Address of UniversalSwapRouter
    constructor(
        address _poolManager, 
        address _swapRouter
    ) Ownable(msg.sender) {
        if(
            _poolManager == address(0) || 
            _swapRouter == address(0)
        ) revert InvalidAddress();

        poolManager = IPoolManager(_poolManager);
        swapRouter = UniversalSwapRouter(_swapRouter);

        callCount = 0;
    }

    /// @notice Modifier to ensure only PoolManager can call certain functions
    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    /// @notice Initiates a flash loan for liquidation via Uniswap V4 unlock
    /// @dev Called by FlashLoanRouter to start the flash loan flow
    /// @param debtAsset The token to borrow
    /// @param collateralAsset The collateral token to receive
    /// @param debtToCover Amount of debt to cover (borrowed)
    /// @param targetContract Liquidation adapter to call
    /// @param data Calldata for liquidation adapter
    function flashLoan(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        address targetContract,
        bytes calldata data
    ) external override {
        // checks
        if(
            debtAsset == address(0) ||
            targetContract == address(0) ||
            collateralAsset == address(0)
        ) revert InvalidAddress();
        if(debtToCover == 0) revert NoZeroAmount();

        callCount++;

        // build LiquidationParams
        LiquidationParams memory liquidationParams = LiquidationParams({
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            debtToCover: debtToCover,
            liquidationTarget: targetContract,
            liquidationCalldata: data,
            minAmountOut: 0
        });

        // Initiate flashloan process
        poolManager.unlock(abi.encode(msg.sender, liquidationParams));
    }

    /// @notice Uniswap V4 callback for flash loan execution
    /// @dev Executes: 1) Take flash loan, 2) Liquidate, 3) Swap, 4) Repay, 5) Send profit
    /// @param data Encoded LiquidationParams
    /// @return Empty bytes (no return data needed)
    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        (address caller, LiquidationParams memory liquidationParams) = abi
            .decode(data, (address, LiquidationParams));

        //////////// BORROW //////////////

        poolManager.take({
            currency: Currency.wrap(liquidationParams.debtAsset),
            to: address(this),
            amount: liquidationParams.debtToCover
        });

        /////////// LIQUIDATION CALL //////////////

        // Approve and execute liquidation via provided target
        address targetContract = liquidationParams.liquidationTarget;

        // Approve the borrowed asset to the liquidation target (adapter/protocol)
        IERC20(liquidationParams.debtAsset).approve(targetContract, liquidationParams.debtToCover);

        // Execute liquidation via low-level call to support arbitrary protocols/adapters
        (bool success, ) = targetContract.call(
            liquidationParams.liquidationCalldata
        );
        if(!success) revert LiquidationFailed();

        // Get collateral received
        uint256 collateralReceived = IERC20(liquidationParams.collateralAsset)
            .balanceOf(address(this));
        if(collateralReceived == 0) revert NoCollateralSeized();

        ///////////////// SWAP CALL //////////////////

        // Approve the swap adpaters to spend collateral
        _approveSwapAdapters(liquidationParams.collateralAsset);

        // Execute the swap
        (, uint256 swappedOut, ) = swapRouter.swapMultiHop(
            liquidationParams.collateralAsset,
            liquidationParams.debtAsset,
            collateralReceived,
            liquidationParams.debtToCover,
            PROVIDER_ID
        );

        // Verify the swap was successful
        if(swappedOut <= liquidationParams.debtToCover) revert InsufficientSwapOutput();

        //////////// REPAY //////////////

        poolManager.sync(Currency.wrap(liquidationParams.debtAsset));

        if (liquidationParams.debtAsset == address(0)) {
            poolManager.settle{value: liquidationParams.debtToCover}();
        } else {
            IERC20(liquidationParams.debtAsset).safeTransfer(address(poolManager), liquidationParams.debtToCover);
            poolManager.settle();
        }

        //////// PROFIT ////////

        // Calculate profit
        uint256 profit = IERC20(liquidationParams.debtAsset)
            .balanceOf(address(this));
        if(profit == 0) revert NotProfitable();

        // record
        if(!isRecorded[liquidationParams.debtAsset]) debtCovered.push(liquidationParams.debtAsset);
        accumProfit[liquidationParams.debtAsset] += profit;

        // Send profit to caller
        IERC20(liquidationParams.debtAsset).safeTransfer(caller, profit);

        // Send any remaining collateral
        uint256 remainingCollateral = IERC20(liquidationParams.collateralAsset)
            .balanceOf(address(this));
        if (remainingCollateral > 0) {
            IERC20(liquidationParams.collateralAsset).safeTransfer(
                caller,
                remainingCollateral
            );
        }

        /// EVENT ///

        emit LiquidationExecuted(
            "UNISWAP_V4",
            liquidationParams.liquidationTarget,
            caller,
            liquidationParams.debtAsset,
            liquidationParams.collateralAsset,
            liquidationParams.debtToCover,
            collateralReceived,
            profit
        );

        return "";
    }

    /// @notice Rescues stranded tokens from the contract
    /// @dev Only callable by owner
    /// @param token The token address to rescue
    /// @param amount The amount to rescue
    function rescueTokens(
        address token, 
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Returns the provider identifier
    /// @return The bytes32 provider ID
    function id() external pure override returns (bytes32) {
        return PROVIDER_ID;
    }

    /// @notice Accepts ETH deposits
    receive() external payable {}

    ///// INTERNAL /////

    /// @notice Verifies caller is the PoolManager
    function _onlyPoolManager() internal view {
        if(msg.sender != address(poolManager)) revert NotPoolManager();
    }

    /// @notice Approves swap adapters to spend a token
    /// @param token The token to approve
    function _approveSwapAdapters(address token) internal {
        uint256 max = type(uint256).max;
        address[] memory swapAdapters = swapRouter.getSwapAdapters();

        for(uint8 i = 0; i < swapAdapters.length; i++) {
            address adapter = swapAdapters[i];
            if (IERC20(token).allowance(address(this), adapter) < max) {
                IERC20(token).approve(adapter, max);
            }
        }
    }

    ////// VIEW //////

    /// @notice Returns total number of flash loan calls
    /// @return The call count
    function getCallCount() external view returns(uint256) {
        return callCount;
    }

    /// @notice Returns list of unique debt assets covered
    /// @return list Array of debt asset addresses
    function getDebtsCovered() external view returns(address[] memory list) {
        list = debtCovered;
    }

    /// @notice Returns accumulated profit for a specific asset
    /// @param asset The debt asset address
    /// @return amount Total profit in that asset
    function getProfitPerAsset(address asset) external view returns(uint256 amount) {
        amount = accumProfit[asset];
    }
    
}
