// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPool {

    // STRUCTS
    
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }

    /// @notice Supply
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw
    function withdraw(address asset, uint256 amount, address to) external returns(uint256 withdrawn);

    /// @notice Borrow
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    /// @notice Repay borrowed assets
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external returns (uint256 repaid);

    /// @notice Liquidate user
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /// @notice Get flash loan
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;

    /// @notice Get user account data
    function getUserAccountData(address user) external view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    
    /// @notice Get user reserve data
    function getReserveData(address asset) external view returns (ReserveData memory);
}

/**
 * @title IMockAaveV3Pool
 * @notice Interface for the mock Aave V3 pool used in testing.
 * @dev Extends the real `IPool` interface and exposes setters and
 *      helpers that are only available on the mock implementation.
 */
interface IMockAaveV3Pool is IPool {
    // --- setup functions ---
    function setUserAccountData(
        address user,
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) external;

    function setReserveData(address asset, ReserveData memory data) external;
    function setATokenAddress(address asset, address aToken) external;
    function setUserCollateral(
        address user,
        address asset,
        uint256 amount
    ) external;
    function setUserDebt(address user, address asset, uint256 amount) external;

    // --- revert / behavior controls ---
    function setShouldRevertOnSupply(bool _shouldRevert) external;
    function setShouldRevertOnWithdraw(bool _shouldRevert) external;
    function setShouldRevertOnBorrow(bool _shouldRevert) external;
    function setShouldRevertOnRepay(bool _shouldRevert) external;
    function setShouldRevertOnLiquidation(bool _shouldRevert) external;
    function setFlashLoanFee(uint256 _fee) external;

    // --- helpers ---
    function getUserCollateral(
        address user,
        address asset
    ) external view returns (uint256);
    function getUserDebt(
        address user,
        address asset
    ) external view returns (uint256);
    function fundPool(address asset, uint256 amount) external;
}
