// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILiquidationAdapter
 * @author Liidia Team
 * @notice Adapter interface that normalizes liquidation positions from different lending protocols.
 * @dev Implementations MUST provide a normalized representation of account risk, liquidation parameters,
 *      and an execution payload that can be used by a liquidator or router in a protocol-agnostic manner.
 *      Amounts are expressed in token units unless otherwise documented by a concrete adapter implementation.
 */
interface ILiquidationAdapter {
    /// STRUCTS

    /// @notice Risk state of a user account
    /// @dev Normalized risk metrics across different lending protocols
    struct RiskState {
        bool liquidatable;              /// @dev Whether the account can be liquidated
        uint256 riskMetric;            /// @dev Health factor, LLTV breach, or shortfall (protocol-specific)
        uint256 collateralUSD;         /// @dev Total collateral value in USD (1e8 = 1 USD)
        uint256 debtUSD;               /// @dev Total debt value in USD (1e8 = 1 USD)
    }

    /// @notice Liquidation profitability information
    /// @dev Used to determine if liquidation is profitable
    struct LiquidationStatus {
        uint256 maxDebtToCover;        /// @dev Maximum debt that can be covered (in debt asset units)
        uint256 actualReturn;          /// @dev Actual collateral return including bonus
        uint256 expectedReturn;        /// @dev Expected collateral return after slippage
        uint256 expectedProfit;        /// @dev Expected profit after fees and slippage
        uint256 liquidationBonus;      /// @dev Liquidation bonus in basis points (bps)
    }

    /// @notice Execution payload for triggering liquidation
    /// @dev Contains target contract address and calldata for liquidation
    struct ExecutionPayload {
        address target;                /// @dev Contract to call for liquidation
        bytes callData;                /// @dev Calldata for the liquidation call
    }

    /// @notice Returns the protocol identifier
    /// @return Protocol name string (e.g., "AAVE_V3", "COMPOUND", "LIIBORROW_v1")
    function getProtocolName() external view returns (string memory);

    /// @notice Returns this adapter's address
    /// @return Address of this adapter contract
    function getAdapterAddress() external view returns (address);

    /// @notice Gets the risk state for a user
    /// @dev Queries the underlying protocol for account health data
    /// @param user The account address to query
    /// @return rs RiskState containing health metrics
    function getRiskState(
        address user
    ) external returns (RiskState memory);

    /// @notice Gets the liquidation status including amounts and bonus
    /// @dev Calculates maximum debt to cover and expected returns
    /// @param user The account address to query
    /// @param collateralAsset The collateral token address
    /// @return lp LiquidationStatus with amounts and bonus info
    function getLiquidationStatus(
        address user,
        address collateralAsset
    ) external returns (LiquidationStatus memory);

    /// @notice Builds the execution payload for liquidation
    /// @dev Encodes the liquidation call for the target protocol
    /// @param user The account to liquidate
    /// @param debtToCover Amount of debt to repay
    /// @param debtAsset The debt token address
    /// @param collateralAsset The collateral token address
    /// @return payload ExecutionPayload with target and calldata
    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external view returns (ExecutionPayload memory);
}
