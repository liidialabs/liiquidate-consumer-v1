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
    address indexed user,
    address indexed collateralAsset,
    address indexed debtAsset,
    uint256 debtCovered,
    uint256 collateralReceived,
    uint256 profit
);