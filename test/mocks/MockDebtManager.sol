// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockDebtManager
 * @notice Mock implementation of IDebtManager for testing lending protocol scenarios
 * @dev Simulates user debt, collateral, health factors, and liquidation mechanics
 */
contract MockDebtManager is Ownable {
    // User account data
    struct UserAccount {
        uint256 totalCollateral; // in USD (1e8 = 1 USD)
        uint256 totalDebt; // in USD (1e8 = 1 USD)
        uint256 healthFactor; // in 1e18
    }

    // Collateral configuration
    struct CollateralConfig {
        uint256 liquidationBonus; // in 1e18 (e.g., 0.05e18 = 5%)
        uint256 liquidationThreshold; // LTV ratio in 1e18
        bool enabled;
    }

    // Debt configuration
    struct DebtConfig {
        uint256 borrowRate; // Annual rate in 1e18
        uint256 maxBorrowAmount; // Maximum total borrow
        bool enabled;
    }

    mapping(address => UserAccount) public userAccounts;
    mapping(address => CollateralConfig) public collateralConfigs;
    mapping(address => DebtConfig) public debtConfigs;
    mapping(address => mapping(address => uint256))
        public userCollateralBalance;
    mapping(address => mapping(address => uint256)) public userDebtBalance;

    // Price oracle
    mapping(address => uint256) public assetPrices; // 1e8 = $1

    // Statistics
    uint256 public totalLiquidations;
    uint256 public totalLiquidationAmount;

    event UserLiquidated(
        address indexed user,
        address indexed collateral,
        uint256 repayAmount,
        uint256 collateralSeized
    );
    event CollateralConfigured(address indexed collateral, uint256 bonus);
    event PriceUpdated(address indexed asset, uint256 price);
    event HealthFactorUpdated(address indexed user, uint256 newHealthFactor);

    constructor() Ownable(msg.sender) {}

    // ========== CONFIGURATION FUNCTIONS ==========

    /**
     * @notice Configures collateral parameters
     * @param collateral The collateral asset
     * @param liquidationBonus Bonus for liquidators (1e18 = 100%)
     * @param liquidationThreshold LTV threshold for liquidation
     */
    function configureCollateral(
        address collateral,
        uint256 liquidationBonus,
        uint256 liquidationThreshold
    ) external onlyOwner {
        require(collateral != address(0), "Invalid collateral");
        require(liquidationBonus <= 0.5e18, "Bonus too high");
        require(liquidationThreshold <= 1e18, "Threshold too high");

        collateralConfigs[collateral] = CollateralConfig({
            liquidationBonus: liquidationBonus,
            liquidationThreshold: liquidationThreshold,
            enabled: true
        });

        emit CollateralConfigured(collateral, liquidationBonus);
    }

    /**
     * @notice Configures debt asset parameters
     * @param debtAsset The debt asset
     * @param borrowRate Annual borrow rate
     * @param maxBorrowAmount Maximum total borrow allowed
     */
    function configureDebtAsset(
        address debtAsset,
        uint256 borrowRate,
        uint256 maxBorrowAmount
    ) external onlyOwner {
        require(debtAsset != address(0), "Invalid debt asset");

        debtConfigs[debtAsset] = DebtConfig({
            borrowRate: borrowRate,
            maxBorrowAmount: maxBorrowAmount,
            enabled: true
        });
    }

    /**
     * @notice Sets the price for an asset
     * @param asset The asset address
     * @param price The price (1e8 = $1)
     */
    function setAssetPrice(address asset, uint256 price) external onlyOwner {
        require(asset != address(0), "Invalid asset");
        require(price > 0, "Price must be positive");

        assetPrices[asset] = price;
        emit PriceUpdated(asset, price);
    }

    // ========== USER ACCOUNT MANAGEMENT ==========

    /**
     * @notice Sets up a user account with initial collateral and debt
     * @param user The user address
     * @param collateral The collateral asset
     * @param collateralAmount Amount of collateral
     * @param debtAsset The debt asset
     * @param debtAmount Amount of debt
     */
    function setupUserAccount(
        address user,
        address collateral,
        uint256 collateralAmount,
        address debtAsset,
        uint256 debtAmount
    ) external onlyOwner {
        require(user != address(0), "Invalid user");

        // Set collateral balance
        userCollateralBalance[user][collateral] = collateralAmount;
        userDebtBalance[user][debtAsset] = debtAmount;

        // Calculate USD values
        uint256 collateralValueUSD = (collateralAmount *
            assetPrices[collateral]) / 1e18;
        uint256 debtValueUSD = (debtAmount * assetPrices[debtAsset]) / 1e18;

        // Calculate health factor
        uint256 healthFactor = calculateHealthFactor(
            collateralValueUSD,
            debtValueUSD,
            collateral
        );

        // Store account data
        userAccounts[user] = UserAccount({
            totalCollateral: collateralValueUSD,
            totalDebt: debtValueUSD,
            healthFactor: healthFactor
        });

        emit HealthFactorUpdated(user, healthFactor);
    }

    /**
     * @notice Updates user collateral and health factor
     * @param user The user address
     * @param collateral The collateral asset
     * @param newAmount New collateral amount
     */
    function updateUserCollateral(
        address user,
        address collateral,
        uint256 newAmount
    ) external onlyOwner {
        require(user != address(0), "Invalid user");

        userCollateralBalance[user][collateral] = newAmount;

        uint256 collateralValueUSD = (newAmount * assetPrices[collateral]) /
            1e18;
        userAccounts[user].totalCollateral = collateralValueUSD;

        // Recalculate health factor
        uint256 healthFactor = calculateHealthFactor(
            collateralValueUSD,
            userAccounts[user].totalDebt,
            collateral
        );
        userAccounts[user].healthFactor = healthFactor;

        emit HealthFactorUpdated(user, healthFactor);
    }

    /**
     * @notice Updates user debt and health factor
     * @param user The user address
     * @param debtAsset The debt asset
     * @param newAmount New debt amount
     */
    function updateUserDebt(
        address user,
        address debtAsset,
        uint256 newAmount
    ) external onlyOwner {
        require(user != address(0), "Invalid user");

        userDebtBalance[user][debtAsset] = newAmount;

        uint256 debtValueUSD = (newAmount * assetPrices[debtAsset]) / 1e18;
        userAccounts[user].totalDebt = debtValueUSD;

        // Recalculate health factor
        uint256 healthFactor = calculateHealthFactor(
            userAccounts[user].totalCollateral,
            debtValueUSD,
            address(0)
        );
        userAccounts[user].healthFactor = healthFactor;

        emit HealthFactorUpdated(user, healthFactor);
    }

    // ========== LIQUIDATION FUNCTIONS ==========

    /**
     * @notice Liquidates a user's position
     * @param user The user to liquidate
     * @param collateral The collateral to seize
     * @param repayAmount Amount to repay in debt asset
     * @param isEth Whether to return as ETH
     */
    function liquidate(
        address user,
        address collateral,
        uint256 repayAmount,
        bool isEth
    ) external {
        require(user != address(0), "Invalid user");
        require(collateral != address(0), "Invalid collateral");
        require(repayAmount > 0, "Repay amount must be positive");

        UserAccount storage account = userAccounts[user];
        require(account.healthFactor < 1e18, "User not liquidatable");

        // Calculate collateral to seize
        uint256 collateralToSeize = getCollateralAmountLiquidate(
            collateral,
            repayAmount
        );

        // Update balances
        userCollateralBalance[user][collateral] -= collateralToSeize;
        account.totalCollateral -=
            (collateralToSeize * assetPrices[collateral]) /
            1e18;
        account.totalDebt -= (repayAmount * assetPrices[collateral]) / 1e18;

        // Recalculate health factor
        account.healthFactor = calculateHealthFactor(
            account.totalCollateral,
            account.totalDebt,
            collateral
        );

        totalLiquidations++;
        totalLiquidationAmount += repayAmount;

        emit UserLiquidated(user, collateral, repayAmount, collateralToSeize);
        emit HealthFactorUpdated(user, account.healthFactor);
    }

    /**
     * @notice Gets the collateral amount to seize for a repayment
     * @param collateral The collateral asset
     * @param repayAmount The amount being repaid
     * @return The collateral amount to seize (including bonus)
     */
    function getCollateralAmountLiquidate(
        address collateral,
        uint256 repayAmount
    ) public view returns (uint256) {
        require(collateral != address(0), "Invalid collateral");

        CollateralConfig memory config = collateralConfigs[collateral];
        require(config.enabled, "Collateral not enabled");

        // repayAmount is in debt asset units, need to convert to collateral units
        // Apply bonus: collateral = repayAmount * (1 + bonus)
        uint256 bonus = (repayAmount * config.liquidationBonus) / 1e18;
        return repayAmount + bonus;
    }

    /**
     * @notice Gets the liquidation bonus for a collateral
     * @param collateral The collateral asset
     * @return The liquidation bonus (1e18 = 100%)
     */
    function getLiquidationBonus(
        address collateral
    ) external view returns (uint256) {
        require(collateral != address(0), "Invalid collateral");
        return collateralConfigs[collateral].liquidationBonus;
    }

    /**
     * @notice Gets user account data
     * @param user The user address
     * @return totalCollateral Total collateral in USD
     * @return totalDebt Total debt in USD
     * @return healthFactor Health factor in 1e18
     */
    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateral,
            uint256 totalDebt,
            uint256 healthFactor
        )
    {
        require(user != address(0), "Invalid user");

        UserAccount memory account = userAccounts[user];
        return (
            account.totalCollateral,
            account.totalDebt,
            account.healthFactor
        );
    }

    /**
     * @notice Gets a user's collateral balance for an asset
     * @param user The user address
     * @param collateral The collateral asset
     * @return The balance
     */
    function getUserCollateralBalance(
        address user,
        address collateral
    ) external view returns (uint256) {
        return userCollateralBalance[user][collateral];
    }

    /**
     * @notice Gets a user's debt balance for an asset
     * @param user The user address
     * @param debtAsset The debt asset
     * @return The balance
     */
    function getUserDebtBalance(
        address user,
        address debtAsset
    ) external view returns (uint256) {
        return userDebtBalance[user][debtAsset];
    }

    // ========== INTERNAL HELPERS ==========

    /**
     * @notice Calculates health factor
     * @param collateralValue Total collateral value in USD
     * @param debtValue Total debt value in USD
     * @param collateral The collateral asset (for configuration lookup)
     * @return Health factor in 1e18 (>= 1e18 is healthy)
     */
    function calculateHealthFactor(
        uint256 collateralValue,
        uint256 debtValue,
        address collateral
    ) internal view returns (uint256) {
        if (debtValue == 0) {
            return type(uint256).max;
        }

        uint256 threshold = collateral != address(0)
            ? collateralConfigs[collateral].liquidationThreshold
            : 0.8e18;

        // HF = (collateral * threshold) / debt
        return (collateralValue * threshold) / debtValue;
    }

    /**
     * @notice Gets statistics about liquidations
     * @return count Total number of liquidations
     * @return totalAmount Total amount liquidated
     */
    function getLiquidationStats()
        external
        view
        returns (uint256 count, uint256 totalAmount)
    {
        return (totalLiquidations, totalLiquidationAmount);
    }

    /**
     * @notice Resets user account (for testing)
     * @param user The user to reset
     */
    function resetUserAccount(address user) external onlyOwner {
        delete userAccounts[user];
    }
}
