// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IFlashLoanReceiver
 * @notice Interface for contracts that receive flash loan callbacks
 */
interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/**
 * @title MockAaveV3Pool
 * @notice Mock Aave V3 Pool for testing flash loan functionality
 * @dev Simulates the flash loan behavior of Aave V3, including fees and callbacks
 */
contract MockAaveV3Pool is Ownable {
    // Flash loan fee in basis points (e.g., 5 = 0.05%)
    uint256 public flashLoanFeeBps = 5;

    // Track total flash loan amount and fees
    uint256 public totalFlashLoanAmount;
    uint256 public totalFlashLoanFees;

    // Track successful flash loans
    uint256 public successfulFlashLoans;

    // Track failed flash loans
    uint256 public failedFlashLoans;

    // Configuration for premium calculation
    struct FlashLoanConfig {
        uint256 premiumBps; // Premium in basis points
        bool enableFlashLoans; // Enable/disable flash loans
        bool revertOnReceiveFailure; // Whether to revert if receiver fails
    }

    FlashLoanConfig public config;

    // Supported assets - mapping of asset address to whether it's supported
    mapping(address => bool) public supportedAssets;
    mapping(address => uint256) public assetReservement;

    event FlashLoan(
        address indexed receiver,
        address indexed asset,
        uint256 indexed amount,
        uint256 fee,
        uint16 referralCode
    );

    event FlashLoanFeeUpdated(uint256 oldFee, uint256 newFee);
    event AssetSupported(address indexed asset, bool supported);
    event AssetReservementUpdated(address indexed asset, uint256 amount);
    event PremiumUpdated(uint256 oldPremium, uint256 newPremium);

    constructor() Ownable(msg.sender) {
        config = FlashLoanConfig({
            premiumBps: 5,
            enableFlashLoans: true,
            revertOnReceiveFailure: true
        });
    }

    /**
     * @notice Sets whether flash loans are enabled
     * @param enabled Whether to enable flash loans
     */
    function setFlashLoansEnabled(bool enabled) external onlyOwner {
        config.enableFlashLoans = enabled;
    }

    /**
     * @notice Sets the flash loan fee in basis points
     * @param newFeeBps The new fee in basis points
     */
    function setFlashLoanFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 10000, "Fee cannot exceed 100%");
        uint256 oldFee = flashLoanFeeBps;
        flashLoanFeeBps = newFeeBps;
        config.premiumBps = newFeeBps;
        emit FlashLoanFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @notice Sets premium in basis points
     * @param premiumBps The premium in basis points
     */
    function setPremiumBps(uint256 premiumBps) external onlyOwner {
        require(premiumBps <= 10000, "Premium cannot exceed 100%");
        uint256 oldPremium = config.premiumBps;
        config.premiumBps = premiumBps;
        emit PremiumUpdated(oldPremium, premiumBps);
    }

    /**
     * @notice Adds or removes an asset from supported assets
     * @param asset The asset address
     * @param supported Whether the asset is supported
     */
    function setAssetSupported(
        address asset,
        bool supported
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        supportedAssets[asset] = supported;
        emit AssetSupported(asset, supported);
    }

    /**
     * @notice Sets the reserve balance for an asset
     * @param asset The asset address
     * @param amount The reserve amount
     */
    function setAssetReservement(
        address asset,
        uint256 amount
    ) external onlyOwner {
        assetReservement[asset] = amount;
        emit AssetReservementUpdated(asset, amount);
    }

    /**
     * @notice Allows the pool to deposit funds for flash loan reserves
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     */
    function depositReserve(address asset, uint256 amount) external {
        require(asset != address(0), "Invalid asset address");
        require(amount > 0, "Amount must be greater than zero");

        IERC20 token = IERC20(asset);
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        assetReservement[asset] += amount;
        emit AssetReservementUpdated(asset, assetReservement[asset]);
    }

    /**
     * @notice Initiates a flash loan
     * @param receiverAddress The address that will receive the flash loan
     * @param asset The asset to borrow
     * @param amount The amount to borrow
     * @param params Additional parameters to pass to the receiver
     * @param referralCode Referral code (not used in mock)
     */
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external {
        require(config.enableFlashLoans, "Flash loans are disabled");
        require(receiverAddress != address(0), "Invalid receiver address");
        require(asset != address(0), "Invalid asset address");
        require(amount > 0, "Amount must be greater than zero");
        require(supportedAssets[asset], "Asset is not supported");
        require(
            assetReservement[asset] >= amount,
            "Insufficient reserve balance"
        );

        // Calculate fee
        uint256 fee = (amount * config.premiumBps) / 10000;
        uint256 amountOwed = amount + fee;

        // Get token
        IERC20 token = IERC20(asset);
        
        // ✅ Store balance BEFORE transfer
        uint256 balanceBefore = token.balanceOf(address(this));

        // Transfer to receiver
        require(
            token.transfer(receiverAddress, amount),
            "Transfer to receiver failed"
        );

        // Call executeOperation on receiver
        bool success = _executeOperation(
            receiverAddress,
            asset,
            amount,
            fee,
            msg.sender,
            params
        );
        require(success, "executeOperation returned false");

        // ✅ FIXED: Pull the repayment back from receiver
        require(
            token.transferFrom(receiverAddress, address(this), amountOwed),
            "Flash loan repayment failed"
        );

        // ✅ Verify we got paid
        uint256 balanceAfter = token.balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore + fee,
            "Insufficient repayment received"
        );

        // Update statistics
        totalFlashLoanAmount += amount;
        totalFlashLoanFees += fee;
        successfulFlashLoans++;

        emit FlashLoan(receiverAddress, asset, amount, fee, referralCode);
    }

    /**
     * @notice Internal function to call executeOperation on receiver
     * @param receiver The receiver address
     * @param asset The borrowed asset
     * @param amount The borrowed amount
     * @param fee The flash loan fee
     * @param initiator The original initiator
     * @param params Additional parameters
     * @return success Whether the operation was successful
     */
    function _executeOperation(
        address receiver,
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) internal returns (bool) {
        try
            IFlashLoanReceiver(receiver).executeOperation(
                asset,
                amount,
                fee,
                initiator,
                params
            )
        returns (bool result) {
            return result;
        } catch {
            if (config.revertOnReceiveFailure) {
                revert("executeOperation reverted");
            }
            failedFlashLoans++;
            return false;
        }
    }

    /**
     * @notice Gets the current balance of an asset in the pool
     * @param asset The asset address
     * @return The balance of the asset
     */
    function getBalance(address asset) external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Gets the reserve for an asset
     * @param asset The asset address
     * @return The reserve amount
     */
    function getReserve(address asset) external view returns (uint256) {
        return assetReservement[asset];
    }

    /**
     * @notice Gets the premium (fee) for a flash loan
     * @return The premium in basis points
     */
    function getFlashLoanPremium() external view returns (uint256) {
        return config.premiumBps;
    }

    /**
     * @notice Checks if an asset is supported
     * @param asset The asset address
     * @return True if the asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool) {
        return supportedAssets[asset];
    }

    /**
     * @notice Gets statistics about flash loans
     * @return total Total flash loan amount
     * @return fees Total fees collected
     * @return successful Successful flash loans
     * @return failed Failed flash loans
     */
    function getFlashLoanStats()
        external
        view
        returns (
            uint256 total,
            uint256 fees,
            uint256 successful,
            uint256 failed
        )
    {
        return (
            totalFlashLoanAmount,
            totalFlashLoanFees,
            successfulFlashLoans,
            failedFlashLoans
        );
    }

    /**
     * @notice Withdraws collected fees from flash loans
     * @param asset The asset to withdraw fees from
     * @param to The recipient address
     */
    function withdrawFees(address asset, address to) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(to != address(0), "Invalid recipient address");

        IERC20 token = IERC20(asset);
        uint256 balance = token.balanceOf(address(this));

        require(balance >= assetReservement[asset], "Cannot withdraw reserves");

        uint256 fees = balance - assetReservement[asset];
        require(fees > 0, "No fees to withdraw");

        require(token.transfer(to, fees), "Transfer failed");
    }

    /**
     * @notice Allows direct deposit of tokens to the pool
     * @param token The token address
     * @param amount The amount to deposit
     */
    function depositToken(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than zero");

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        assetReservement[token] += amount;
    }

    /**
     * @notice Allows withdrawal of tokens from the pool (owner only)
     * @param token The token address
     * @param to The recipient
     * @param amount The amount to withdraw
     */
    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than zero");
        require(
            assetReservement[token] >= amount,
            "Insufficient reserve to withdraw"
        );

        assetReservement[token] -= amount;
        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice Resets statistics (for testing purposes)
     */
    function resetStats() external onlyOwner {
        totalFlashLoanAmount = 0;
        totalFlashLoanFees = 0;
        successfulFlashLoans = 0;
        failedFlashLoans = 0;
    }

    /**
     * @notice Receives ETH (if needed for some operations)
     */
    receive() external payable {}
}
