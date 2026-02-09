// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ILiquidationAdapter
/// @notice Adapter interface that normalizes liquidation positions from different lending protocols.
/// @dev Implementations MUST provide a normalized representation of account risk, liquidation parameters,
///      and an execution payload that can be used by a liquidator or router in a protocol-agnostic manner.
///      Amounts are expressed in token units unless otherwise documented by a concrete adapter implementation.
interface ILiquidationAdapter {
    /// STRUCTS

    /// @notice Normalized risk snapshot for a user account
    /// @dev Interpretation of `riskMetric` is adapter-specific; its value should be comparable across accounts for the same adapter.
    /// Fields:
    /// - liquidatable: whether the account is currently eligible for liquidation
    /// - riskMetric: normalized metric representing how close the account is to liquidation (implementation-defined)
    /// - collateralUSD: aggregated collateral value denominated in USD (normalized)
    /// - debtUSD: aggregated debt value denominated in USD (normalized)
    struct RiskState {
        bool liquidatable;
        uint256 riskMetric; // HF, LLTV breach, shortfall (normalized)
        uint256 collateralUSD;
        uint256 debtUSD;
    }

    /// @notice Parameters required to perform a liquidation for a specific collateral/debt pair
    /// Fields:
    /// - collateralAsset: the collateral token address that will be seized
    /// - debtAsset: the debt token address that will be repaid/covered
    /// - maxDebtToCover: maximum amount of debt (in debt token units) advisable to cover in this liquidation
    /// - expectedCollateralOut: expected amount of collateral receivable when covering `maxDebtToCover`
    /// - liquidationBonus: incentive expressed in basis points (bps) above liquidated collateral value
    struct LiquidationParams {
        address collateralAsset;
        address debtAsset;
        uint256 maxDebtToCover;
        uint256 expectedCollateralOut;
        uint256 liquidationBonus; // bps
    }

    /// @notice Encodes a single on-chain call required to execute a liquidation
    /// Fields:
    /// - target: contract address to call
    /// - value: ETH value to send with the call
    /// - callData: ABI-encoded calldata for the call
    struct ExecutionPayload {
        address target;
        bytes callData;
    }

    /// FUNCTION SIGNATURES

    /// @notice Returns the protocol kind this adapter implements
    /// @return ProtocolKind enum value identifying the protocol implementation
    function protocol() external pure returns (bytes32);

    /// @notice Returns a short human-readable name for the adapter
    /// @return name string that describes the adapter (e.g., "LiilendV1Adapter")
    function name() external pure returns (string memory);

    /// @notice RISK EVALUATION

    /// @notice Returns a normalized risk snapshot for `user`
    /// @param user The account to evaluate
    /// @return RiskState normalized snapshot describing liquidation eligibility and exposure
    function getRiskState(
        address user
    ) external view returns (RiskState memory);

    /// @notice Returns the liquidation parameters for `user` for the specified collateral/debt pair
    /// @param user The user account under consideration
    /// @param collateralAsset The collateral token address to be seized
    /// @param debtAsset The debt token address to be repaid
    /// @return LiquidationParams parameters that inform how a liquidation should be executed
    function getLiquidationParams(
        address user,
        address collateralAsset,
        address debtAsset
    ) external view returns (LiquidationParams memory);

    /// @notice EXECUTION

    /// @notice Builds an execution payload that, when executed, performs a liquidation for `user`.
    /// @param user The account being liquidated
    /// @param debtToCover The amount of debt to cover (in debt token units)
    /// @param receiveCollateralToken If true, the caller prefers to receive raw collateral tokens; otherwise some adapters may return proceeds in another form
    /// @return ExecutionPayload ABI-encodable single-call payload that can be executed to perform the liquidation
    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external view returns (ExecutionPayload memory);
}
