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

    struct LiquidationStatus {
        uint256 maxDebtToCover; // In USD
        uint256 actualReturn;
        uint256 expectedReturn;
        uint256 expectedProfit;
        uint256 liquidationBonus; // bps
    }

    struct ExecutionPayload {
        address target;
        bytes callData;
    }

    function getProtocolName() external view returns (string memory);

    function getAdapterAddress() external view returns (address);

    function getRiskState(
        address user
    ) external returns (RiskState memory);

    function getLiquidationStatus(
        address user,
        address collateralAsset
    ) external returns (LiquidationStatus memory);

    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external view returns (ExecutionPayload memory);
}
