// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlashLoan
 * @author Liidia Team
 * @notice Interface for flash loan providers
 * @dev Implementations must provide flash loan functionality for liquidation execution
 */
interface IFlashLoan {
    /// @notice Initiates a flash loan for liquidation
    /// @dev Called by FlashLoanRouter to borrow funds, execute liquidation, and repay
    /// @param debtAsset The token to borrow (flash loaned)
    /// @param collateralAsset The token that will be received from liquidation
    /// @param debtToCover Amount of debt to cover (borrowed amount)
    /// @param targetContract Contract to call with flash loaned funds (liquidation adapter)
    /// @param data Calldata to pass to target contract
    function flashLoan(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        address targetContract,
        bytes calldata data
    ) external;

    /// @notice Returns the unique identifier for this flash loan provider
    /// @return Provider ID (e.g., keccak256("AAVE_V3"), keccak256("UNISWAP_V4"))
    function id() external pure returns (bytes32);
}