// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct LiquidationParams {
    address collateralAsset;
    address debtAsset;
    uint256 debtToCover;

    address liquidationTarget;
    bytes liquidationCalldata;

    uint256 minAmountOut;   // slippage protection
}

event LiquidationExecuted(
    string flashLoanProvider,
    address indexed targetContract,
    address indexed user,
    address indexed debtAsset,
    address collateralAsset,
    uint256 debtCovered,
    uint256 collateralReceived,
    uint256 profit
);