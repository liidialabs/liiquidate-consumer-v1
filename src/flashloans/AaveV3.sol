// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "../interfaces/flashloans/protocols/aave-v3/IPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFlashLoan} from "../interfaces/flashloans/IFlashLoan.sol";
import {UniversalSwapRouter} from "../UniversalSwapRouter.sol";
import {ISwapAdapter} from "../interfaces/swapAdapter/ISwapAdapter.sol";
import {LiquidationParams, LiquidationExecuted} from "../types/DataTypes.sol";

/**
 * @title FlashLiquidator
 * @notice Executes flash loan liquidations with pluggable swap providers
 */
contract AaveV3 is Ownable, IFlashLoan {
    IPool public immutable pool;
    UniversalSwapRouter public immutable swapRouter;

    bytes32 public constant PROVIDER_ID = keccak256("AAVE_V3");

    constructor(
        address _pool, 
        address _swapRouter
    ) {
        require(_pool != address(0) && _swapRouter != address(0), "invalid pool");
        pool = IPool(_pool);
        swapRouter = UniversalSwapRouter(_swapRouter);
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(pool), "not pool manager");
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
        pool.flashLoanSimple({
            receiverAddress: address(this),
            asset: debtAsset,
            amount: debtToCover,
            params: abi.encode(msg.sender, liquidationParams),
            referralCode: 0
        });
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external onlyPoolManager returns (bool) {
        require(initiator == address(this), "invalid initiator");

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
        require(success, "liquidation failed");

        // Get collateral received
        uint256 collateralReceived = IERC20(liquidationParams.collateralAsset)
            .balanceOf(address(this));
        require(collateralReceived > 0, "no collateral received");

        ///////////////// SWAP CALL //////////////////

        // Calculate amount needed to repay
        uint256 totalDebt = amount + fee;

        // Approve the swap router to spend collateral
        IERC20(collateralAsset).approve(address(swapRouter), collateralReceived);

        // Execute the swap
        (, uint256 swappedOut, ) = swapRouter.swapMultiHop(
            liquidationParams.collateralAsset,
            liquidationParams.debtAsset,
            collateralReceived,
            totalDebt
        );

        // Verify the swap was successful
        require(swappedOut >= totalDebt, "Insufficient swap output");

        // Calculate and verify repayment
        uint256 debtAssetBalance = IERC20(liquidationParams.debtAsset)
            .balanceOf(address(this));
        require(debtAssetBalance >= totalDebt, "insufficient repayment");

        // Calculate profit
        uint256 profit = debtAssetBalance - totalDebt;
        require(profit > 0, "not profitable");

        // Approve repayment
        IERC20(liquidationParams.debtAsset).approve(address(pool), totalDebt);

        // Send profit to caller
        IERC20(liquidationParams.debtAsset).transfer(caller, profit);

        // Send any remaining collateral
        uint256 remainingCollateral = IERC20(liquidationParams.collateralAsset)
            .balanceOf(address(this));
        if (remainingCollateral > 0) {
            IERC20(liquidationParams.collateralAsset).transfer(
                caller,
                remainingCollateral
            );
        }

        emit LiquidationExecuted(
            caller,
            liquidationParams.collateralAsset,
            liquidationParams.debtAsset,
            liquidationParams.debtToCover,
            collateralReceived,
            profit
        );

        return true;
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
