// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/access/Ownable.sol";

// /**
//  * @title MockPriceOracle
//  * @notice Mock price oracle for testing with dynamic price feeds
//  * @dev Simulates Chainlink-style price feeds with support for price manipulation
//  */
// contract MockPriceOracle is Ownable {
//     struct PriceFeed {
//         int256 price; // in 8 decimals (1e8 = $1)
//         uint8 decimals;
//         uint256 updateTime;
//         string description;
//         uint80 roundId;
//     }

//     mapping(address => PriceFeed) public feeds;
//     mapping(address => int256[]) public priceHistory;
//     mapping(address => bool) public isFeedActive;

//     // Price volatility for simulating realistic movements
//     mapping(address => uint256) public volatility; // in basis points

//     event PriceUpdated(
//         address indexed asset,
//         int256 newPrice,
//         uint256 timestamp
//     );
//     event FeedConfigured(
//         address indexed asset,
//         uint8 decimals,
//         string description
//     );
//     event VolatilitySet(address indexed asset, uint256 volatilityBps);

//     constructor() Ownable(msg.sender) {}

//     // ========== CONFIGURATION ==========

//     /**
//      * @notice Configures a price feed for an asset
//      * @param asset The asset address
//      * @param initialPrice The initial price (1e8 = $1)
//      * @param decimals The price feed decimals
//      * @param description Feed description
//      */
//     function configureFeed(
//         address asset,
//         int256 initialPrice,
//         uint8 decimals,
//         string calldata description
//     ) external onlyOwner {
//         require(asset != address(0), "Invalid asset");
//         require(initialPrice > 0, "Price must be positive");
//         require(decimals > 0 && decimals <= 18, "Invalid decimals");

//         feeds[asset] = PriceFeed({
//             price: initialPrice,
//             decimals: decimals,
//             updateTime: block.timestamp,
//             description: description,
//             roundId: 1
//         });

//         isFeedActive[asset] = true;
//         priceHistory[asset].push(initialPrice);
//         volatility[asset] = 100; // Default 1% volatility

//         emit FeedConfigured(asset, decimals, description);
//     }

//     /**
//      * @notice Updates the price for an asset
//      * @param asset The asset address
//      * @param newPrice The new price (1e8 = $1)
//      */
//     function updatePrice(address asset, int256 newPrice) external onlyOwner {
//         require(asset != address(0), "Invalid asset");
//         require(newPrice > 0, "Price must be positive");
//         require(isFeedActive[asset], "Feed not active");

//         PriceFeed storage feed = feeds[asset];
//         feed.price = newPrice;
//         feed.updateTime = block.timestamp;
//         feed.roundId++;

//         priceHistory[asset].push(newPrice);

//         emit PriceUpdated(asset, newPrice, block.timestamp);
//     }

//     /**
//      * @notice Sets volatility for an asset (for simulating price swings)
//      * @param asset The asset address
//      * @param volatilityBps Volatility in basis points (100 = 1%)
//      */
//     function setVolatility(
//         address asset,
//         uint256 volatilityBps
//     ) external onlyOwner {
//         require(asset != address(0), "Invalid asset");
//         require(volatilityBps <= 10000, "Volatility too high");

//         volatility[asset] = volatilityBps;
//         emit VolatilitySet(asset, volatilityBps);
//     }

//     /**
//      * @notice Toggles feed active status
//      * @param asset The asset address
//      * @param active Whether to activate
//      */
//     function setFeedActive(address asset, bool active) external onlyOwner {
//         require(asset != address(0), "Invalid asset");
//         isFeedActive[asset] = active;
//     }

//     // ========== CHAINLINK-LIKE FEED INTERFACE ==========

//     /**
//      * @notice Gets the latest price for an asset (Chainlink style)
//      * @param asset The asset address
//      * @return roundId The round id
//      * @return answer The price
//      * @return startedAt Timestamp started
//      * @return updatedAt Timestamp updated
//      * @return answeredInRound Round answered in
//      */
//     function latestRoundData(
//         address asset
//     )
//         external
//         view
//         returns (
//             uint80 roundId,
//             int256 answer,
//             uint256 startedAt,
//             uint256 updatedAt,
//             uint80 answeredInRound
//         )
//     {
//         require(isFeedActive[asset], "Feed not active");

//         PriceFeed memory feed = feeds[asset];
//         return (
//             feed.roundId,
//             feed.price,
//             feed.updateTime,
//             feed.updateTime,
//             feed.roundId
//         );
//     }

//     /**
//      * @notice Gets price data for an asset
//      * @param asset The asset address
//      * @return price The current price
//      * @return decimals The price decimals
//      * @return updateTime The last update time
//      */
//     function getLatestPrice(
//         address asset
//     ) external view returns (int256 price, uint8 decimals, uint256 updateTime) {
//         require(isFeedActive[asset], "Feed not active");

//         PriceFeed memory feed = feeds[asset];
//         return (feed.price, feed.decimals, feed.updateTime);
//     }

//     /**
//      * @notice Gets price in standard 8 decimals format
//      * @param asset The asset address
//      * @return The price in 1e8 format
//      */
//     function getPrice(address asset) external view returns (int256) {
//         require(isFeedActive[asset], "Feed not active");

//         PriceFeed memory feed = feeds[asset];

//         // Convert to 1e8 if different decimals
//         if (feed.decimals == 8) {
//             return feed.price;
//         } else if (feed.decimals > 8) {
//             return feed.price / int256(10 ** (feed.decimals - 8));
//         } else {
//             return feed.price * int256(10 ** (8 - feed.decimals));
//         }
//     }

//     /**
//      * @notice Gets the description for a feed
//      * @param asset The asset address
//      * @return The feed description
//      */
//     function getDescription(
//         address asset
//     ) external view returns (string memory) {
//         return feeds[asset].description;
//     }

//     /**
//      * @notice Gets decimals for a feed
//      * @param asset The asset address
//      * @return The decimals
//      */
//     function getDecimals(address asset) external view returns (uint8) {
//         return feeds[asset].decimals;
//     }

//     // ========== PRICE HISTORY ==========

//     /**
//      * @notice Gets price history for an asset
//      * @param asset The asset address
//      * @return Array of historical prices
//      */
//     function getPriceHistory(
//         address asset
//     ) external view returns (int256[] memory) {
//         return priceHistory[asset];
//     }

//     /**
//      * @notice Gets price history length
//      * @param asset The asset address
//      * @return The number of price points
//      */
//     function getPriceHistoryLength(
//         address asset
//     ) external view returns (uint256) {
//         return priceHistory[asset].length;
//     }

//     /**
//      * @notice Gets average price over last N updates
//      * @param asset The asset address
//      * @param lookback Number of updates to average
//      * @return The average price
//      */
//     function getAveragePrice(
//         address asset,
//         uint256 lookback
//     ) external view returns (int256) {
//         require(lookback > 0, "Lookback must be positive");

//         int256[] memory history = priceHistory[asset];
//         require(history.length > 0, "No price history");

//         uint256 count = lookback > history.length ? history.length : lookback;
//         int256 sum = 0;

//         for (uint256 i = history.length - count; i < history.length; i++) {
//             sum += history[i];
//         }

//         return sum / int256(count);
//     }

//     /**
//      * @notice Simulates a price spike/drop (useful for liquidation testing)
//      * @param asset The asset address
//      * @param percentageChange Percentage change (100 = 1%, -100 = -1%)
//      */
//     function simulatePriceChange(
//         address asset,
//         int256 percentageChange
//     ) external onlyOwner {
//         require(asset != address(0), "Invalid asset");
//         require(isFeedActive[asset], "Feed not active");

//         PriceFeed storage feed = feeds[asset];
//         int256 change = (feed.price * percentageChange) / 10000;
//         feed.price = feed.price + change;

//         require(feed.price > 0, "Price cannot be negative");

//         feed.updateTime = block.timestamp;
//         feed.roundId++;
//         priceHistory[asset].push(feed.price);

//         emit PriceUpdated(asset, feed.price, block.timestamp);
//     }

//     /**
//      * @notice Clears price history for an asset
//      * @param asset The asset address
//      */
//     function clearHistory(address asset) external onlyOwner {
//         delete priceHistory[asset];
//     }

//     /**
//      * @notice Gets feed status
//      * @param asset The asset address
//      * @return active Whether feed is active
//      * @return hasData Whether feed has price data
//      */
//     function getFeedStatus(
//         address asset
//     ) external view returns (bool active, bool hasData) {
//         return (isFeedActive[asset], priceHistory[asset].length > 0);
//     }
// }
