// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockLendingProtocol
 * @notice Comprehensive mock lending protocol for testing various liquidation scenarios
 * @dev Supports multiple collaterals, debt assets, and realistic protocol mechanics
 */
contract MockLendingProtocol is Ownable {
    // Protocol configuration
    struct ProtocolConfig {
        uint256 collateralFactor; // LTV for borrowing (1e18 = 100%)
        uint256 liquidationIncentive; // Liquidation bonus (1e18 = 100%)
        uint256 closeFactorBps; // Percentage of debt closable in liquidation (10000 = 100%)
        bool enabled;
    }

    // User position data
    struct UserPosition {
        mapping(address => uint256) collaterals; // asset => amount
        mapping(address => uint256) borrows; // asset => amount
        uint256 lastUpdate; // Last block timestamp
    }

    // Market data
    struct MarketData {
        uint256 totalBorrows; // Total borrowed amount
        uint256 totalSupply; // Total supplied amount
        uint256 borrowIndex; // Borrow index (1e18 = 1)
        uint256 supplyIndex; // Supply index (1e18 = 1)
        uint256 borrowRate; // Annual rate (1e18 = 100%)
        uint256 lastUpdate;
    }

    mapping(address => ProtocolConfig) public assetConfigs;
    mapping(address => UserPosition) public userPositions;
    mapping(address => MarketData) public marketData;
    mapping(address => uint256) public assetPrices; // 1e8 = $1

    // Protocol state
    uint256 public totalUsers;
    uint256 public totalLiquidations;

    // Events
    event AssetConfigured(
        address indexed asset,
        uint256 collateralFactor,
        uint256 liquidationIncentive
    );
    event UserDeposited(
        address indexed user,
        address indexed asset,
        uint256 amount
    );
    event UserBorrowed(
        address indexed user,
        address indexed asset,
        uint256 amount
    );
    event UserLiquidated(
        address indexed liquidator,
        address indexed user,
        address indexed collateral,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event PriceUpdated(address indexed asset, uint256 price);

    constructor() Ownable(msg.sender) {}

    // ========== CONFIGURATION ==========

    /**
     * @notice Configures an asset for use in the protocol
     * @param asset The asset address
     * @param collateralFactor LTV for borrowing (1e18 = 100%)
     * @param liquidationIncentive Liquidation bonus
     * @param borrowRate Annual borrow rate
     */
    function configureAsset(
        address asset,
        uint256 collateralFactor,
        uint256 liquidationIncentive,
        uint256 borrowRate
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset");
        require(collateralFactor <= 1e18, "Invalid collateral factor");
        require(liquidationIncentive <= 0.5e18, "Invalid incentive");

        assetConfigs[asset] = ProtocolConfig({
            collateralFactor: collateralFactor,
            liquidationIncentive: liquidationIncentive,
            closeFactorBps: 5000, // 50% default
            enabled: true
        });

        marketData[asset] = MarketData({
            totalBorrows: 0,
            totalSupply: 0,
            borrowIndex: 1e18,
            supplyIndex: 1e18,
            borrowRate: borrowRate,
            lastUpdate: block.timestamp
        });

        emit AssetConfigured(asset, collateralFactor, liquidationIncentive);
    }

    /**
     * @notice Sets the price for an asset
     * @param asset The asset address
     * @param price Price in 1e8 format ($1 = 1e8)
     */
    function setAssetPrice(address asset, uint256 price) external onlyOwner {
        require(asset != address(0), "Invalid asset");
        require(price > 0, "Price must be positive");

        assetPrices[asset] = price;
        emit PriceUpdated(asset, price);
    }

    /**
     * @notice Sets the close factor for liquidations
     * @param asset The asset address
     * @param closeFactorBps Close factor in basis points (10000 = 100%)
     */
    function setCloseFactor(
        address asset,
        uint256 closeFactorBps
    ) external onlyOwner {
        require(closeFactorBps <= 10000, "Invalid close factor");
        assetConfigs[asset].closeFactorBps = closeFactorBps;
    }

    // ========== USER OPERATIONS ==========

    /**
     * @notice Deposits collateral
     * @param asset The collateral asset
     * @param amount The deposit amount
     */
    function deposit(address asset, uint256 amount) external {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Amount must be positive");
        require(assetConfigs[asset].enabled, "Asset not enabled");

        // Accrue interest
        _accrueInterest(asset);

        UserPosition storage position = userPositions[msg.sender];
        if (position.collaterals[asset] == 0 && position.borrows[asset] == 0) {
            totalUsers++;
        }

        position.collaterals[asset] += amount;
        marketData[asset].totalSupply += amount;

        // Transfer tokens (would normally happen via hook)
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        emit UserDeposited(msg.sender, asset, amount);
    }

    /**
     * @notice Withdraws collateral
     * @param asset The collateral asset
     * @param amount The withdrawal amount
     */
    function withdraw(address asset, uint256 amount) external {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Amount must be positive");

        // Accrue interest
        _accrueInterest(asset);

        UserPosition storage position = userPositions[msg.sender];
        require(position.collaterals[asset] >= amount, "Insufficient balance");

        // Check health factor after withdrawal
        position.collaterals[asset] -= amount;
        require(
            _isHealthy(msg.sender),
            "Withdrawal would make account unhealthy"
        );

        marketData[asset].totalSupply -= amount;

        IERC20(asset).transfer(msg.sender, amount);

        emit UserDeposited(msg.sender, asset, 0); // Indicates withdrawal
    }

    /**
     * @notice Borrows an asset
     * @param asset The asset to borrow
     * @param amount The borrow amount
     */
    function borrow(address asset, uint256 amount) external {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Amount must be positive");
        require(assetConfigs[asset].enabled, "Asset not enabled");

        // Accrue interest
        _accrueInterest(asset);

        // Check borrow capacity
        UserPosition storage position = userPositions[msg.sender];
        uint256 borrowCapacity = _getBorrowCapacity(msg.sender);
        uint256 newBorrowValue = (amount * assetPrices[asset]) / 1e8;
        require(
            _getBorrowedValue(msg.sender) + newBorrowValue <= borrowCapacity,
            "Borrow exceeds capacity"
        );

        position.borrows[asset] += amount;
        marketData[asset].totalBorrows += amount;

        IERC20(asset).transfer(msg.sender, amount);

        emit UserBorrowed(msg.sender, asset, amount);
    }

    /**
     * @notice Repays a borrow
     * @param asset The borrowed asset
     * @param amount The repay amount
     */
    function repay(address asset, uint256 amount) external {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Amount must be positive");

        // Accrue interest
        _accrueInterest(asset);

        UserPosition storage position = userPositions[msg.sender];
        require(position.borrows[asset] > 0, "No borrow to repay");

        uint256 repayAmount = amount > position.borrows[asset]
            ? position.borrows[asset]
            : amount;

        position.borrows[asset] -= repayAmount;
        marketData[asset].totalBorrows -= repayAmount;

        IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);
    }

    // ========== LIQUIDATION ==========

    /**
     * @notice Liquidates an undercollateralized user
     * @param user The user to liquidate
     * @param collateral The collateral to seize
     * @param debtAsset The debt asset to repay
     * @param repayAmount The repay amount
     */
    function liquidate(
        address user,
        address collateral,
        address debtAsset,
        uint256 repayAmount
    ) external {
        require(user != address(0), "Invalid user");
        require(collateral != address(0), "Invalid collateral");
        require(debtAsset != address(0), "Invalid debt asset");
        require(repayAmount > 0, "Repay amount must be positive");

        UserPosition storage position = userPositions[user];

        // Check user is liquidatable
        require(!_isHealthy(user), "User is healthy");

        // Accruing interest
        _accrueInterest(collateral);
        _accrueInterest(debtAsset);

        // Check max close factor
        uint256 maxRepay = (position.borrows[debtAsset] *
            assetConfigs[debtAsset].closeFactorBps) / 10000;
        require(repayAmount <= maxRepay, "Repay exceeds close factor");

        // Calculate collateral to seize
        uint256 seizeAmount = _calculateSeizeAmount(
            repayAmount,
            debtAsset,
            collateral
        );
        require(
            position.collaterals[collateral] >= seizeAmount,
            "Insufficient collateral"
        );

        // Update balances
        position.borrows[debtAsset] -= repayAmount;
        position.collaterals[collateral] -= seizeAmount;
        marketData[debtAsset].totalBorrows -= repayAmount;
        marketData[collateral].totalSupply -= seizeAmount;

        // Transfer tokens
        IERC20(debtAsset).transferFrom(msg.sender, address(this), repayAmount);
        IERC20(collateral).transfer(msg.sender, seizeAmount);

        totalLiquidations++;

        emit UserLiquidated(
            msg.sender,
            user,
            collateral,
            repayAmount,
            seizeAmount
        );
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Gets user account liquidity
     * @param user The user address
     * @return collateral Total collateral value in USD
     * @return borrow Total borrow value in USD
     * @return liquidity Available liquidity (collateral - borrow)
     */
    function getAccountLiquidity(
        address user
    )
        external
        view
        returns (uint256 collateral, uint256 borrow, int256 liquidity)
    {
        uint256 collateralValue = _calculateCollateralValue(user);
        uint256 borrowValue = _getBorrowedValue(user);
        int256 availableLiquidity = int256(collateralValue) -
            int256(borrowValue);

        return (collateralValue, borrowValue, availableLiquidity);
    }

    /**
     * @notice Gets user health factor
     * @param user The user address
     * @return health factor in 1e18 (>= 1e18 is healthy)
     */
    function getHealthFactor(address user) external view returns (uint256) {
        uint256 borrowedValue = _getBorrowedValue(user);
        if (borrowedValue == 0) {
            return type(uint256).max;
        }

        uint256 collateralValue = _calculateCollateralValue(user);
        return (collateralValue * 1e18) / borrowedValue;
    }

    /**
     * @notice Checks if user is liquidatable
     * @param user The user address
     * @return Whether the user can be liquidated
     */
    function isLiquidatable(address user) external view returns (bool) {
        return !_isHealthy(user);
    }

    /**
     * @notice Gets user position
     * @param user The user address
     * @param collateral The collateral asset
     * @param debtAsset The debt asset
     * @return collateralAmount User's collateral
     * @return debtAmount User's debt
     */
    function getUserPosition(
        address user,
        address collateral,
        address debtAsset
    ) external view returns (uint256 collateralAmount, uint256 debtAmount) {
        return (
            userPositions[user].collaterals[collateral],
            userPositions[user].borrows[debtAsset]
        );
    }

    /**
     * @notice Gets market data for an asset
     * @param asset The asset address
     * @return config The asset configuration
     * @return market The market data
     */
    function getMarketData(
        address asset
    )
        external
        view
        returns (ProtocolConfig memory config, MarketData memory market)
    {
        return (assetConfigs[asset], marketData[asset]);
    }

    /**
     * @notice Gets protocol statistics
     * @return users Total number of users
     * @return liquidations Total liquidations
     */
    function getProtocolStats()
        external
        view
        returns (uint256 users, uint256 liquidations)
    {
        return (totalUsers, totalLiquidations);
    }

    // ========== INTERNAL HELPERS ==========

    /**
     * @notice Calculates the amount of collateral to seize
     */
    function _calculateSeizeAmount(
        uint256 repayAmount,
        address debtAsset,
        address collateral
    ) internal view returns (uint256) {
        uint256 repayValue = (repayAmount * assetPrices[debtAsset]) / 1e8;
        uint256 incentive = assetConfigs[collateral].liquidationIncentive;
        uint256 seizeValue = (repayValue * (1e18 + incentive)) / 1e18;
        return (seizeValue * 1e8) / assetPrices[collateral];
    }

    /**
     * @notice Calculates total collateral value for a user
     */
    function _calculateCollateralValue(
        address user
    ) internal view returns (uint256) {
        uint256 totalValue = 0;
        UserPosition storage position = userPositions[user];

        // This is a simplified version - in reality would iterate through all assets
        // For testing, would need to track which assets a user has
        return totalValue;
    }

    /**
     * @notice Gets borrow capacity for a user
     */
    function _getBorrowCapacity(address user) internal view returns (uint256) {
        uint256 collateralValue = _calculateCollateralValue(user);
        // This is simplified; in reality would sum across all collaterals with their factors
        return collateralValue;
    }

    /**
     * @notice Gets total borrowed value for a user
     */
    function _getBorrowedValue(address user) internal view returns (uint256) {
        uint256 totalValue = 0;
        UserPosition storage position = userPositions[user];

        // Simplified - would iterate through all debt assets
        return totalValue;
    }

    /**
     * @notice Checks if user is healthy (health factor >= 1e18)
     */
    function _isHealthy(address user) internal view returns (bool) {
        uint256 borrowedValue = _getBorrowedValue(user);
        if (borrowedValue == 0) {
            return true;
        }

        uint256 collateralValue = _calculateCollateralValue(user);
        return (collateralValue * 1e18) / borrowedValue >= 1e18;
    }

    /**
     * @notice Accrues interest for a market
     */
    function _accrueInterest(address asset) internal {
        MarketData storage market = marketData[asset];
        uint256 timeDelta = block.timestamp - market.lastUpdate;

        if (timeDelta > 0 && market.totalBorrows > 0) {
            uint256 interestAccrued = (market.totalBorrows *
                market.borrowRate *
                timeDelta) / (365 days * 1e18);

            market.borrowIndex +=
                (interestAccrued * 1e18) /
                market.totalBorrows;
            market.lastUpdate = block.timestamp;
        }
    }
}
