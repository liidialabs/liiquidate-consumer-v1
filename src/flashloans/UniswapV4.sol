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

contract UniswapV4 is Ownable, IFlashLoan, IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;
    UniversalSwapRouter public immutable swapRouter;

    bytes32 public constant PROVIDER_ID = keccak256("UNISWAP_V4");

    mapping(address => uint256) private accumProfit;
    mapping(address => bool) private isRecorded;

    address[] debtCovered;
    uint256 public callCount;

    error InvalidAddress();
    error NotPoolManager();
    error NoZeroAmount();
    error LiquidationFailed();
    error NoCollateralSeized();
    error InsufficientSwapOutput();
    error NotProfitable();

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

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

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

    function rescueTokens(
        address token, 
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    function id() external pure override returns (bytes32) {
        return PROVIDER_ID;
    }

    receive() external payable {}

    ///// INTERNAL /////

    function _onlyPoolManager() internal view {
        if(msg.sender != address(poolManager)) revert NotPoolManager();
    }

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

    function getCallCount() external view returns(uint256) {
        return callCount;
    }

    function getDebtsCovered() external view returns(address[] memory list) {
        list = debtCovered;
    }

    function getProfitPerAsset(address asset) external view returns(uint256 amount) {
        amount = accumProfit[asset];
    }
    
}
