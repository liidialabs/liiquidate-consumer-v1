// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ILiquidationAdapter
/// @notice Adapter interface that normalizes liquidation positions from different lending protocols.
/// @dev Implementations MUST provide a normalized representation of account risk, liquidation parameters,
///      and an execution payload that can be used by a liquidator or router in a protocol-agnostic manner.
///      Amounts are expressed in token units unless otherwise documented by a concrete adapter implementation.
interface ILiquidationAdapter {
    /// STRUCTS

    struct RiskState {
        bool liquidatable;
        uint256 riskMetric; // HF, LLTV breach, shortfall (normalized)
        uint256 collateralUSD;
        uint256 debtUSD;
    }

    struct LiquidationParams {
        address collateralAsset;
        address debtAsset;
        uint256 maxDebtToCover;
        uint256 expectedCollateralOut;
        uint256 liquidationBonus; // bps
    }

    struct ExecutionPayload {
        address target;
        bytes callData;
    }

    function protocol() external returns (bytes32);

    function name() external pure returns (string memory);

    function getRiskState(
        address user
    ) external returns (RiskState memory);

    function getLiquidationParams(
        address user,
        address collateralAsset,
        address debtAsset
    ) external returns (LiquidationParams memory);

    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external view returns (ExecutionPayload memory);
}
