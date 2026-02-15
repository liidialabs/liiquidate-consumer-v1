// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MockDebtManager } from "./MockDebtManager.sol";
import { ILiquidationAdapter } from "../../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";

/// @title LiiLendV1Adapter
/// @notice ...
/// @dev ...
contract MockDebtManagerAdapter is ILiquidationAdapter {
    MockDebtManager private immutable debtManager;

    uint256 private constant BASE_PRECISION = 1e18;
    uint256 private constant PERCENT_PRECISION = 1e4;
    uint256 private constant CLOSE_FACTOR = 0.5e4;
    
    // Precomputed: keccak256("LIILEND_V1")
    bytes32 private PROTOCOL_HASH;

    constructor(address _debtManager, bytes32 _protocol) {
        debtManager = MockDebtManager(_debtManager);
        PROTOCOL_HASH = _protocol;
    }

    function protocol() external override view returns (bytes32) {
        return PROTOCOL_HASH;
    }

    function name() external override pure returns (string memory) {
        return "LiiLend V1 Adapter";
    }

    function getRiskState(
        address user
    ) external override returns (RiskState memory rs) {
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
    ) external override returns (LiquidationParams memory lp) {
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
            MockDebtManager.liquidate.selector,
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