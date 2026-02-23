// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceOracle {
    // Returns USD price (1 USD = 1e8)
    function getAssetPrice(address asset) external view returns (uint256);
}

/**
 * @title IMockAaveOracle
 * @notice Interface for the mock oracle used in tests.
 * @dev Extends the base Aave price oracle interface and exposes
 *      additional helper functions that are only available on the
 *      testing mock implementation.
 */
interface IMockAaveOracle is IPriceOracle {
    /// @notice Set price for a specific asset
    function setAssetPrice(address asset, uint256 price) external;

    /// @notice Set prices for multiple assets at once
    function setAssetPrices(
        address[] calldata assets,
        uint256[] calldata prices
    ) external;

    /// @notice Set default price returned when an asset price is not configured
    function setDefaultPrice(uint256 price) external;

    /// @notice Control whether getAssetPrice should revert (for failure testing)
    function setShouldRevert(bool _shouldRevert) external;

    /// @notice Check if an asset has a price configured
    function hasAssetPrice(address asset) external view returns (bool);

    /// @notice Update the price and emit an event
    function updatePrice(address asset, uint256 newPrice) external;

    /// @notice Simulate a price crash by percentage (0-100)
    function simulatePriceCrash(address asset, uint256 percentDrop) external;

    /// @notice Simulate a price pump by percentage
    function simulatePricePump(address asset, uint256 percentIncrease) external;

    /// @notice Reset the mock state (default price, revert flag)
    function resetPrices() external;
}
