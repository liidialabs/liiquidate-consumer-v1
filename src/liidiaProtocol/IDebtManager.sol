// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** 
 * @title IDebtManager - Debt management utilities for LiiBorrow V1
 * @author Liidia Team
 * @notice Utility interface for computing collateral seizure amounts, liquidation bonuses, and user health
 *         metrics used by LiiLend V1 liquidations and adapters.
*/
interface IDebtManager {

    /**
     * @notice Deposit an ERC20 token as collateral and supply it to Aave on behalf of the protocol.
     * @dev Caller must approve `tokenCollateralAddress` prior to calling.
     * @param tokenCollateralAddress ERC20 token address to deposit.
     * @param amountCollateral Amount of token to deposit.
     */
    function depositCollateralERC20(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external;

    /**
     * @notice Borrow USDC against supplied collateral up to the allowed borrow limit.
     * @param amountToBorrow Amount of USDC to borrow.
     */
    function borrowUsdc(uint256 amountToBorrow) external;

    /**
     * @notice Check if a given user is liquidatable by protocol rules.
     * @param user The address of the user.
     * @return True if liquidatable, false otherwise.
     */
    function isLiquidatable(address user) external returns (bool);

    /**
     * @notice Liquidate an undercollateralized user by repaying part of their debt and seizing collateral.
     * @param user The address of the user to liquidate.
     * @param debtAsset: The asset that was borrowed
     * @param collateralAsset The collateral token to seize.
     * @param repayAmount The amount of USDC to repay on the user's behalf.
     * @param isEth True if seized collateral should be returned as ETH.
     */
    function liquidate(
        address user,
        address debtAsset,
        address collateralAsset,
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
     * @notice Returns the collateral balance of a user for a specific token.
     * @param user The user's address.
     * @param token The collateral token address.
     * @return balance The collateral balance for the user.
     */
    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256);

    /**
     * @notice Returns a user's owed amounts: debt owed to Aave and total debt including protocol cut.
     * @param user The user's address.
     * @return userAaveDebt Debt owed to Aave (USDC).
     * @return userTotalDebt Total debt including protocol cut (USDC).
     */
    function getUserDebt(
        address user
    ) external returns (uint256 userAaveDebt, uint256 userTotalDebt);

    /**
     * @notice Returns the health factor of a user (internal accounting).
     * @param user The user's address.
     * @return healthFactor The user's health factor (wad).
     */
    function getHealthFactor(address user) external returns (uint256);

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
