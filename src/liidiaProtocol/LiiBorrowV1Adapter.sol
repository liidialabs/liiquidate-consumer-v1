// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ILiquidationAdapter } from "../interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import { IDebtManager } from "./IDebtManager.sol";

/// @title LiiLendV1Adapter
/// @notice ...
/// @dev ...
contract LiiBorrowV1Adapter is ILiquidationAdapter {
    IDebtManager private immutable debtManager;

    uint256 private constant BASE_PRECISION = 1e18;
    uint256 private constant PERCENT_PRECISION = 1e4; // 100%
    uint256 private constant CLOSE_FACTOR = 0.5e4; // 50%
    uint256 private constant EST_DROP_TO = 0.9e4; // 90%
    
    error InvalidAddress();
    error InvalidAmount();

    constructor(address _debtManager) {
        if(_debtManager == address(0)) revert InvalidAddress();

        debtManager = IDebtManager(_debtManager);
    }

    function getProtocolName() external override pure returns (string memory) {
        return "LIIBORROW_v1";
    }

    function getAdapterAddress() external override view returns (address) {
        return address(this);
    }

    function getRiskState(
        address user
    ) external override returns (RiskState memory rs) {
        if(user == address(0)) revert InvalidAddress();

        (
            uint256 collateralBase,
            uint256 debtBase,
            uint256 healthFactor
        ) = debtManager.getUserAccountData(user);

        bool isLiquidatable = debtManager.isLiquidatable(user);

        rs = RiskState({
            liquidatable: isLiquidatable,
            riskMetric: healthFactor,
            collateralUSD: collateralBase,
            debtUSD: debtBase
        });
    }

    function getLiquidationStatus(
        address user,
        address collateralAsset
    ) external override returns (LiquidationStatus memory lp) {
        if(
            user == address(0) ||
            collateralAsset == address(0)
        ) revert InvalidAddress();

        (
            ,
            uint256 debtBase,
            uint256 hf
        ) = debtManager.getUserAccountData(user);

        if (hf >= 1e18 || debtBase == 0) {
            return lp; // return empty params (NO REVERT)
        }

        uint256 maxDebtToCover = (debtBase * CLOSE_FACTOR) / PERCENT_PRECISION;
        uint256 liquidationBonus = debtManager.getLiquidationBonus(collateralAsset);
        liquidationBonus = liquidationBonus * PERCENT_PRECISION / BASE_PRECISION; // convert from 1e18 to dps

        uint256 bonus = maxDebtToCover *  liquidationBonus / PERCENT_PRECISION;
        uint256 maxReturn = maxDebtToCover + bonus;
        uint256 minReturn = maxReturn * EST_DROP_TO / PERCENT_PRECISION; // expect a 90% drop due to fees (flashloan + swap) & slippage

        lp = LiquidationStatus({
            maxDebtToCover: maxDebtToCover,
            actualReturn: maxReturn,
            expectedReturn: minReturn,
            expectedProfit: minReturn - maxDebtToCover,
            liquidationBonus: liquidationBonus
        });
    }

    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external override view returns (ExecutionPayload memory payload) {
        if(
            user == address(0) ||
            collateralAsset == address(0) ||
            debtAsset == address(0)
        ) revert InvalidAddress();
        if(debtToCover == 0) revert InvalidAmount();

        bytes memory callData = abi.encodeWithSelector(
            IDebtManager.liquidate.selector,
            user,
            debtAsset,
            collateralAsset,
            debtToCover,
            false
        );

        payload = ExecutionPayload({
            target: address(debtManager),
            callData: callData
        });
    }
}