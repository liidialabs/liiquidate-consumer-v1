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
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {UniversalSwapRouter} from "../UniversalSwapRouter.sol";
import {IFlashLoan} from "../interfaces/flashloans/IFlashLoan.sol";
import {ISwapAdapter} from "../interfaces/swapAdapter/ISwapAdapter.sol";
import {LiquidationParams, LiquidationExecuted} from "../types/DataTypes.sol";

contract UniswapV4 is Ownable, IFlashLoan, IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;

    bytes32 public constant PROVIDER_ID = keccak256("UNISWAP_V4");

    constructor(address _poolManager, address _swapRouter) Ownable(msg.sender) {
        require(
            _pool != address(0) && _swapRouter != address(0),
            "invalid address"
        );
        poolManager = IPoolManager(_poolManager);
        swapRouter = UniversalSwapRouter(_swapRouter);
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
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
        require(
            debtAsset != address(0) &&
                targetContract != address(0) &&
                collateralAsset != address(0),
            "Invalid Address"
        );
        require(debtToCover != 0, "Amount cannot be zero!");

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
            currency: liquidationParams.debtAsset,
            to: address(this),
            amount: liquidationParams.debtToCover
        });

        /////////// LIQUIDATION CALL //////////////

        // Approve and execute liquidation via provided target
        address targetContract = liquidationParams.liquidationTarget;

        // Approve the borrowed asset to the liquidation target (adapter/protocol)
        IERC20(asset).approve(targetContract, amount);

        // Execute liquidation via low-level call to support arbitrary protocols/adapters
        (bool success, ) = targetContract.call(
            liquidationParams.liquidationCalldata
        );
        require(success, "liquidation failed");

        // Get collateral received
        uint256 collateralReceived = IERC20(liquidationParams.collateralAsset)
            .balanceOf(address(this));
        require(collateralReceived > 0, "no collateral received");

        ///////////////// SWAP CALL //////////////////

        // Approve the swap router to spend collateral
        IERC20(collateralAsset).approve(
            address(swapRouter),
            collateralReceived
        );

        // Execute the swap
        (, uint256 swappedOut, ) = swapRouter.swapMultiHop(
            liquidationParams.collateralAsset,
            liquidationParams.debtAsset,
            collateralReceived,
            liquidationParams.debtToCover
        );

        // Verify the swap was successful
        require(
            swappedOut >= liquidationParams.debtToCover,
            "Insufficient swap output"
        );

        // Calculate profit
        uint256 debtAssetBalance = IERC20(liquidationParams.debtAsset)
            .balanceOf(address(this));
        uint256 profit = debtAssetBalance - liquidationParams.debtToCover;
        require(profit > 0, "not profitable");

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

        //////////// REPAY //////////////
        poolManager.sync(currency);

        if (currency == address(0)) {
            poolManager.settle{value: amount}();
        } else {
            IERC20(currency).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }

        /// EVENT ///

        emit LiquidationExecuted(
            caller,
            liquidationParams.collateralAsset,
            liquidationParams.debtAsset,
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
        IERC20(token).transfer(owner(), amount);
    }

    function id() external pure override returns (bytes32) {
        return PROVIDER_ID;
    }

    receive() external payable {}
    
}
