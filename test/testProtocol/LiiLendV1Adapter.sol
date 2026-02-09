// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ILiquidationAdapter } from "../interfaces/adapter/ILiquidationAdapter.sol";
import { IDebtManager } from "../interfaces/protocols/LiiLendV1.sol";

/// @title LiiLendV1Adapter
/// @notice ...
/// @dev ...
contract LiiLendV1Adapter is ILiquidationAdapter {
    IDebtManager private immutable debtManager;
    uint256 private BASE_PRECISION = 1e18;
    uint256 private PERCENT_PRECISION = 1e4;
    uint256 private CLOSE_FACTOR = 0.5e4;

    constructor(address _debtManager) {
        debtManager = IDebtManager(_debtManager);
    }

    function protocol() external override pure returns (bytes32) {
        return keccak256("LIILEND_V1");
    }

    function name() external override pure returns (string memory) {
        return "LiiLend V1 Adapter";
    }

    function getRiskState(
        address user
    ) external override view returns (RiskState memory rs) {
        (
            uint256 collateralBase,
            uint256 debtBase,
            uint256 healthFactor
        ) = debtManager.getUserAccountData(user);

        rs = RiskState({
            liquidatable: healthFactor < BASE_PRECISION,
            riskMetric: healthFactor,
            collateralUSD: collateralBase,
            debtUSD: debtBase
        });
    }

    function getLiquidationParams(
        address user,
        address collateralAsset,
        address debtAsset
    ) external override view returns (LiquidationParams memory lp) {
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
        liquidationBonus = liquidationBonus * PERCENT_PRECISION / BASE_PRECISION;

        lp = LiquidationParams({
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            maxDebtToCover: maxDebtToCover,
            expectedCollateralOut: 0, // computed off-chain / later step
            liquidationBonus: liquidationBonus
        });
    }

    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external override view returns (ExecutionPayload memory payload) {
        bytes memory callData = abi.encodeWithSelector(
            IDebtManager.liquidate.selector,
            user,
            collateralAsset,
            debtToCover,
            false
        );

        payload = ExecutionPayload({
            target: address(debtManager),
            value: 0,
            callData: callData
        });
    }
}