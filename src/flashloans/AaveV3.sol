// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "../interfaces/flashloans/protocols/aave-v3/IPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFlashLoan} from "../interfaces/flashloans/IFlashLoan.sol";
import {UniversalSwapRouter} from "../UniversalSwapRouter.sol";
import {LiquidationParams, LiquidationExecuted} from "../types/DataTypes.sol";

/**
 * @title AaveV3FlashLoan
 * @notice Aave V3 flash loan provider for liquidation execution
 * @dev Implements IFlashLoan to provide flash loans via Aave V3 pool.
 *      After receiving flash loan, executes liquidation, swaps collateral,
 *      repays the flash loan, and sends profit to caller.
 */
contract AaveV3 is Ownable, IFlashLoan {
    using SafeERC20 for IERC20;

    /// @notice The Aave V3 Pool contract
    IPool public immutable pool;

    /// @notice The UniversalSwapRouter for swapping collateral
    UniversalSwapRouter public immutable swapRouter;

    /// @notice Unique identifier for this provider
    bytes32 public constant PROVIDER_ID = keccak256("AAVE_V3");

    /// @notice Accumulates profit per debt asset
    mapping(address => uint256) private accumProfit;

    /// @notice Tracks which debt assets have been recorded
    mapping(address => bool) private isRecorded;

    /// @notice List of unique debt assets covered
    address[] debtCovered;

    /// @notice Counter for total flash loan calls
    uint256 public callCount;

    // ERRORS

    /// @notice Thrown when an address parameter is zero
    error InvalidAddress();

    /// @notice Thrown when caller is not the Aave Pool
    error NotPoolManager();

    /// @notice Thrown when amount is zero
    error NoZeroAmount();

    /// @notice Thrown when initiator is invalid
    error InvalidInitiator();

    /// @notice Thrown when liquidation call fails
    error LiquidationFailed();

    /// @notice Thrown when no collateral is received from liquidation
    error NoCollateralSeized();

    /// @notice Thrown when swapped output is insufficient to repay loan
    error InsufficientSwapOutput();

    /// @notice Thrown when unable to repay the flash loan
    error CannotRepayLoan();

    /// @notice Thrown when liquidation is not profitable
    error NotProfitable();

    /// @notice Initializes the AaveV3 flash loan provider
    /// @param _pool Address of Aave V3 Pool
    /// @param _swapRouter Address of UniversalSwapRouter
    constructor(
        address _pool, 
        address _swapRouter
    ) Ownable(msg.sender) {
        if(
            _pool == address(0) || 
            _swapRouter == address(0)
        ) revert InvalidAddress();
        
        pool = IPool(_pool);
        swapRouter = UniversalSwapRouter(_swapRouter);

        callCount = 0;
    }

    /// @notice Modifier to ensure only Aave Pool can call certain functions
    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    /// @notice Initiates a flash loan for liquidation
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
        pool.flashLoanSimple({
            receiverAddress: address(this),
            asset: debtAsset,
            amount: debtToCover,
            params: abi.encode(msg.sender, liquidationParams),
            referralCode: 0
        });
    }

    /// @notice Aave V3 callback for flash loan execution
    /// @dev Executes: 1) Liquidate position, 2) Swap collateral, 3) Repay flash loan, 4) Send profit
    /// @param asset The borrowed asset address
    /// @param amount The amount borrowed
    /// @param fee The flash loan fee
    /// @param initiator The caller of the flash loan (this contract)
    /// @param params Encoded LiquidationParams
    /// @return true if execution succeeds
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external onlyPoolManager returns (bool) {
        if(initiator != address(this)) revert InvalidInitiator();

        (address caller, LiquidationParams memory liquidationParams) = abi
            .decode(params, (address, LiquidationParams));

        /////////// LIQUIDATION CALL //////////////

        // Approve and execute liquidation via provided target
        address targetContract = liquidationParams.liquidationTarget;

        // Approve the borrowed asset to the liquidation target (adapter/protocol)
        IERC20(asset).approve(targetContract, amount);

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

        // Calculate amount needed to repay
        uint256 totalDebt = amount + fee;

        // Approve the swap router to spend collateral
        _approveSwapAdapters(liquidationParams.collateralAsset);

        // Execute the swap
        (, uint256 swappedOut, ) = swapRouter.swapMultiHop(
            liquidationParams.collateralAsset,
            liquidationParams.debtAsset,
            collateralReceived,
            totalDebt,
            PROVIDER_ID
        );

        // Verify the swap was successful
        if(swappedOut <= totalDebt) revert InsufficientSwapOutput();

        // Calculate and verify repayment
        uint256 debtAssetBalance = IERC20(liquidationParams.debtAsset)
            .balanceOf(address(this));
        if(debtAssetBalance < totalDebt) revert CannotRepayLoan();

        // Calculate profit
        uint256 profit = debtAssetBalance - totalDebt;
        if(profit == 0) revert NotProfitable();

        // record
        if(!isRecorded[liquidationParams.debtAsset]) debtCovered.push(liquidationParams.debtAsset);
        accumProfit[liquidationParams.debtAsset] += profit;

        // Approve repayment
        IERC20(liquidationParams.debtAsset).approve(address(pool), totalDebt);

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

        emit LiquidationExecuted(
            "AAVE_V3",
            liquidationParams.liquidationTarget,
            caller,
            liquidationParams.debtAsset,
            liquidationParams.collateralAsset,
            liquidationParams.debtToCover,
            collateralReceived,
            profit
        );

        return true;
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

    //// INTERNAL ////

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

    /// @notice Verifies caller is the Aave Pool
    function _onlyPoolManager() internal view {
        if(msg.sender != address(pool)) revert NotPoolManager();
    }

    //// VIEW ////

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
