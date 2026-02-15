// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// /**
//  * @title MockCompoundProtocol
//  * @notice Mock Compound-like lending protocol for testing alternative protocol integrations
//  * @dev Different design from Aave/LiiLend to test adapter flexibility
//  */
// contract MockCompoundProtocol is Ownable {
//     // Market data
//     struct Market {
//         uint256 totalCash; // Total underlying
//         uint256 totalBorrows; // Total outstanding borrow
//         uint256 totalSupply; // Total cTokens
//         uint256 exchangeRate; // Tokens per underlying (1e18 = 1:1)
//         bool isListed; // Whether market is active
//     }

//     // User account data
//     struct Account {
//         mapping(address => uint256) balances; // cToken balances
//         mapping(address => uint256) borrowBalances; // Borrow balances
//         bool inMarket; // Whether account has entered
//     }

//     mapping(address => Market) public markets;
//     mapping(address => Account) public accounts;
//     mapping(address => uint256) public assetPrices; // 1e8 = $1

//     // Liquidation parameters
//     uint256 public closeFactor = 5000; // 50% in bps
//     uint256 public liquidationIncentive = 1e18 + 0.08e18; // 1.08x

//     // Statistics
//     uint256 public totalUsers;
//     uint256 public totalLiquidations;

//     event MarketListed(address indexed cToken, address indexed underlying);
//     event Supply(
//         address indexed cToken,
//         address indexed supplier,
//         uint256 amount
//     );
//     event Borrow(
//         address indexed cToken,
//         address indexed borrower,
//         uint256 amount
//     );
//     event Liquidation(
//         address indexed liquidator,
//         address indexed borrower,
//         address indexed cTokenCollateral,
//         uint256 repayAmount
//     );

//     constructor() Ownable(msg.sender) {}

//     // ========== MARKET SETUP ==========

//     /**
//      * @notice Lists a new market
//      * @param cToken The cToken (contract) address
//      * @param underlying The underlying token
//      * @param initialPrice Initial token price (1e8 = $1)
//      */
//     function listMarket(
//         address cToken,
//         address underlying,
//         uint256 initialPrice
//     ) external onlyOwner {
//         require(cToken != address(0), "Invalid cToken");
//         require(underlying != address(0), "Invalid underlying");

//         markets[cToken] = Market({
//             totalCash: 0,
//             totalBorrows: 0,
//             totalSupply: 0,
//             exchangeRate: 1e18,
//             isListed: true
//         });

//         assetPrices[underlying] = initialPrice;

//         emit MarketListed(cToken, underlying);
//     }

//     /**
//      * @notice Sets asset price
//      * @param asset The asset address
//      * @param price The price (1e8 = $1)
//      */
//     function setPriceOracle(address asset, uint256 price) external onlyOwner {
//         require(asset != address(0), "Invalid asset");
//         require(price > 0, "Price must be positive");
//         assetPrices[asset] = price;
//     }

//     /**
//      * @notice Sets close factor for liquidations
//      * @param newCloseFactor New close factor (5000 = 50%)
//      */
//     function setCloseFactor(uint256 newCloseFactor) external onlyOwner {
//         require(newCloseFactor <= 10000, "Invalid close factor");
//         closeFactor = newCloseFactor;
//     }

//     /**
//      * @notice Sets liquidation incentive
//      * @param newIncentive New incentive (1.08e18 = 8% bonus)
//      */
//     function setLiquidationIncentive(uint256 newIncentive) external onlyOwner {
//         require(newIncentive >= 1e18, "Incentive must be >= 1");
//         liquidationIncentive = newIncentive;
//     }

//     // ========== SUPPLY & BORROW ==========

//     /**
//      * @notice Supplies to a market
//      * @param cToken The cToken address
//      * @param underlying The underlying token
//      * @param amount The supply amount
//      */
//     function supply(
//         address cToken,
//         address underlying,
//         uint256 amount
//     ) external {
//         require(markets[cToken].isListed, "Market not listed");
//         require(amount > 0, "Amount must be positive");

//         Account storage account = accounts[msg.sender];
//         Market storage market = markets[cToken];

//         // Mint cTokens
//         uint256 mintAmount = (amount * 1e18) / market.exchangeRate;

//         account.balances[cToken] += mintAmount;
//         market.totalSupply += mintAmount;
//         market.totalCash += amount;

//         if (!account.inMarket) {
//             account.inMarket = true;
//             totalUsers++;
//         }

//         // Transfer underlying
//         IERC20(underlying).transferFrom(msg.sender, address(this), amount);

//         emit Supply(cToken, msg.sender, amount);
//     }

//     /**
//      * @notice Borrows from a market
//      * @param cToken The cToken address
//      * @param amount The borrow amount
//      */
//     function borrow(address cToken, uint256 amount) external {
//         require(markets[cToken].isListed, "Market not listed");
//         require(amount > 0, "Amount must be positive");

//         Account storage account = accounts[msg.sender];
//         Market storage market = markets[cToken];

//         // Check borrow limit (simplified)
//         uint256 borrowLimit = _getCollateralValue(msg.sender);
//         uint256 currentBorrows = _getBorrowValue(msg.sender);
//         uint256 additionalBorrow = (amount * assetPrices[cToken]) / 1e8;

//         require(
//             currentBorrows + additionalBorrow <= borrowLimit,
//             "Borrow limit exceeded"
//         );

//         require(market.totalCash >= amount, "Insufficient cash");

//         account.borrowBalances[cToken] += amount;
//         market.totalBorrows += amount;
//         market.totalCash -= amount;

//         // Transfer underlying
//         IERC20(cToken).transfer(msg.sender, amount);

//         emit Borrow(cToken, msg.sender, amount);
//     }

//     /**
//      * @notice Repays a borrow
//      * @param cToken The cToken address
//      * @param amount The repay amount
//      */
//     function repay(address cToken, uint256 amount) external {
//         require(amount > 0, "Amount must be positive");

//         Account storage account = accounts[msg.sender];
//         Market storage market = markets[cToken];

//         require(account.borrowBalances[cToken] > 0, "No borrow");

//         uint256 repayAmount = amount > account.borrowBalances[cToken]
//             ? account.borrowBalances[cToken]
//             : amount;

//         account.borrowBalances[cToken] -= repayAmount;
//         market.totalBorrows -= repayAmount;
//         market.totalCash += repayAmount;

//         // Transfer from user
//         IERC20(cToken).transferFrom(msg.sender, address(this), repayAmount);
//     }

//     /**
//      * @notice Redeems cTokens
//      * @param cToken The cToken address
//      * @param redeemAmount The number of cTokens to redeem
//      */
//     function redeem(address cToken, uint256 redeemAmount) external {
//         require(redeemAmount > 0, "Amount must be positive");

//         Account storage account = accounts[msg.sender];
//         Market storage market = markets[cToken];

//         require(
//             account.balances[cToken] >= redeemAmount,
//             "Insufficient balance"
//         );

//         // Calculate underlying amount
//         uint256 underlyingAmount = (redeemAmount * market.exchangeRate) / 1e18;

//         require(market.totalCash >= underlyingAmount, "Insufficient cash");

//         account.balances[cToken] -= redeemAmount;
//         market.totalSupply -= redeemAmount;
//         market.totalCash -= underlyingAmount;

//         // Check health after withdrawal
//         require(
//             _isAccountHealthy(msg.sender),
//             "Redeem would make account unhealthy"
//         );

//         // Transfer underlying
//         IERC20(cToken).transfer(msg.sender, underlyingAmount);
//     }

//     // ========== LIQUIDATION ==========

//     /**
//      * @notice Liquidates an account
//      * @param borrower The borrower to liquidate
//      * @param repayAmount Amount to repay
//      * @param cTokenCollateral The collateral to seize
//      */
//     function liquidateBorrow(
//         address borrower,
//         uint256 repayAmount,
//         address cTokenCollateral
//     ) external {
//         require(borrower != address(0), "Invalid borrower");
//         require(repayAmount > 0, "Repay amount must be positive");

//         // Check account is unhealthy
//         require(!_isAccountHealthy(borrower), "Account is healthy");

//         Account storage borrowerAccount = accounts[borrower];

//         // Simplified liquidation logic
//         uint256 seizeAmount = _calculateSeizeAmount(
//             repayAmount,
//             cTokenCollateral
//         );

//         borrowerAccount.borrowBalances[cTokenCollateral] -= repayAmount;
//         borrowerAccount.balances[cTokenCollateral] -= seizeAmount;

//         // Transfer collateral to liquidator
//         IERC20(cTokenCollateral).transfer(msg.sender, seizeAmount);

//         totalLiquidations++;

//         emit Liquidation(msg.sender, borrower, cTokenCollateral, repayAmount);
//     }

//     // ========== VIEW FUNCTIONS ==========

//     /**
//      * @notice Gets account liquidity
//      * @param account The account address
//      * @return collateralValue Total collateral value
//      * @return borrowValue Total borrow value
//      */
//     function getAccountLiquidity(
//         address account
//     ) external view returns (uint256 collateralValue, uint256 borrowValue) {
//         collateralValue = _getCollateralValue(account);
//         borrowValue = _getBorrowValue(account);
//     }

//     /**
//      * @notice Gets user balance in a market
//      * @param cToken The cToken address
//      * @param user The user address
//      * @return The cToken balance
//      */
//     function balanceOfUnderlying(
//         address cToken,
//         address user
//     ) external view returns (uint256) {
//         uint256 balance = accounts[user].balances[cToken];
//         return (balance * markets[cToken].exchangeRate) / 1e18;
//     }

//     /**
//      * @notice Gets market data
//      * @param cToken The cToken address
//      * @return The market data
//      */
//     function getMarket(address cToken) external view returns (Market memory) {
//         return markets[cToken];
//     }

//     /**
//      * @notice Gets if account is in market
//      * @param account The account address
//      * @return Whether in market
//      */
//     function isAccountInMarket(address account) external view returns (bool) {
//         return accounts[account].inMarket;
//     }

//     // ========== INTERNAL HELPERS ==========

//     function _getCollateralValue(
//         address account
//     ) internal view returns (uint256) {
//         // Simplified: would iterate through all markets user is in
//         return 0;
//     }

//     function _getBorrowValue(address account) internal view returns (uint256) {
//         // Simplified: would sum all borrow amounts
//         return 0;
//     }

//     function _isAccountHealthy(address account) internal view returns (bool) {
//         uint256 collateral = _getCollateralValue(account);
//         uint256 borrows = _getBorrowValue(account);

//         if (borrows == 0) return true;
//         return collateral >= borrows;
//     }

//     function _calculateSeizeAmount(
//         address cToken,
//         uint256 repayAmount
//     ) internal view returns (uint256) {
//         // Simplified calculation
//         return (repayAmount * liquidationIncentive) / 1e18;
//     }

//     function _calculateSeizeAmount(
//         uint256 repayAmount,
//         address cTokenCollateral
//     ) internal view returns (uint256) {
//         return (repayAmount * liquidationIncentive) / 1e18;
//     }
// }
