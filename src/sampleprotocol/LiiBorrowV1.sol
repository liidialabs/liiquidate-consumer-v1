// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IDebtManager - Debt management utilities for LiiLend V1
/// @notice Utility interface for computing collateral seizure amounts, liquidation bonuses, and user health
///         metrics used by LiiLend V1 liquidations and adapters.
interface IDebtManager {

    /**
     * @notice Liquidate an undercollateralized user by repaying part of their debt and seizing collateral.
     * @param user The address of the user to liquidate.
     * @param collateral The collateral token to seize.
     * @param repayAmount The amount of USDC to repay on the user's behalf.
     * @param isEth True if seized collateral should be returned as ETH.
     */
    function liquidate(
        address user,
        address collateral,
        uint256 repayAmount,
        bool isEth
    ) external;

    /**
     * @notice Convert a USD repay value into an amount of collateral including liquidation bonus.
     * @param collateral The collateral token address.
     * @param collateralAmount The amount of collateral to receive.
     * @return The amount of collateral to seize for the given repay value.
     */
    function getCollateralAmountLiquidate(
        address collateral,
        uint256 collateralAmount
    ) external view returns (uint256);

    /**
     * @notice Returns the liquidation bonus for a collateral (bonus part only).
     * @param collateral The collateral token address.
     * @return bonus The liquidation bonus (e.g., 0.05e18 for 5%).
     */
    function getLiquidationBonus(
        address collateral
    ) external view returns (uint256 bonus);

    /**
     * @notice Returns a user's account data including total collateral, total debt and health factor.
     * @param user The user's address.
     * @return _totalCollateral Total collateral value in USD (1e8 = 1 USD as per Aave feed scaling).
     * @return _totalDebt Total debt value in USD (1e8 = 1 USD as per Aave feed scaling).
     * @return _hFactor The health factor of the user.
     */
    function getUserAccountData(
        address user
    )
        external
        returns (
            uint256 _totalCollateral,
            uint256 _totalDebt,
            uint256 _hFactor
        );
}
