// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IFlashLoan } from "./interfaces/flashloans/IFlashLoan.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import { LiquidationData } from "./types/DataTypes.sol";

/// @title FlashLoanRouter
/// @notice Routes flash loan requests to configured providers with fallback support
/// @dev Manages multiple flash loan providers and tries them in priority order
///      until one succeeds. Common providers are AaveV3 and UniswapV4.
contract FlashLoanRouter is Ownable {

    /// @notice Maps provider ID to provider contract address
    mapping(bytes32 => address) public providers;

    /// @notice Tracks total debt covered per asset for accounting
    mapping(address => uint256) private debtCovered;

    /// @notice Tracks which debt assets have been recorded
    mapping(address => bool) private isRecorded;

    /// @notice Stores liquidation data per call count for transparency
    mapping(uint256 => LiquidationData) private liquidationJobs;

    /// @notice Ordered list of provider IDs to try in sequence
    bytes32[] private providerPriority;

    /// @notice List of unique debt assets covered
    address[] private debts;

    /// @notice Counter for total flash loan calls
    uint256 private callCount;

    /// EVENTS ///

    /// @notice Emitted when a new provider is added
    /// @param id The provider identifier
    /// @param provider The provider contract address
    event ProviderAdded(bytes32 id, address provider);

    /// @notice Emitted when a provider is removed
    /// @param id The provider identifier
    event ProviderRemoved(bytes32 id);

    /// @notice Emitted when provider priority order is set
    /// @param providers Array of provider IDs in priority order
    event ProviderPrioritySet(bytes32[] providers);

    /// @notice Emitted when a flash loan is routed to a provider
    /// @param provider The provider ID being tried
    event FlashLoanRoutedOn(bytes32 provider);

    /// @notice Emitted when a flash loan succeeds
    /// @param provider The provider ID that succeeded
    event FlashLoanExecuted(bytes32 provider);

    /// @notice Emitted when a flash loan fails
    /// @param provider The provider ID that failed
    event FlashLoanFailed(bytes32 provider);

    /// ERRORS ///

    /// @notice Thrown when an address parameter is zero
    error InvalidAddress();

    /// @notice Thrown when a provider ID is zero
    error InvalidProtocol();

    /// @notice Thrown when the provider array is empty
    error EmptyProviderArray();

    /// @notice Thrown when the amount is zero
    error InvalidAmount();

    /// @notice Thrown when the data parameter is empty
    error InvalidData();

    /// @notice Thrown when the report/data is invalid
    error InvalidReport();

    /// @notice Initializes the FlashLoanRouter
    constructor() Ownable(msg.sender) {
        callCount = 0;
    }

    /// @notice Adds a new flash loan provider
    /// @param provider The address of the flash loan provider contract
    function addProvider(address provider) external onlyOwner {
        if(provider == address(0)) revert InvalidAddress();
        bytes32 id = IFlashLoan(provider).id();
        providers[id] = provider;
        emit ProviderAdded(id, provider);
    }

    /// @notice Removes a flash loan provider
    /// @param id The provider identifier to remove
    function removeProvider(bytes32 id) external onlyOwner {
        if(id == bytes32(0)) revert InvalidProtocol();
        delete providers[id];
        emit ProviderRemoved(id);
    }

    /// @notice Sets the order in which providers are tried
    /// @dev First provider in array is tried first. If it fails, next is tried, etc.
    /// @param providerIds Ordered array of provider IDs to use as fallback sequence
    /// @notice Set UniswapV4 as first priority due to zero fees
    function setProviderPriority(
        bytes32[] calldata providerIds
    ) external onlyOwner {
        if(providerIds.length == 0) revert EmptyProviderArray();
        providerPriority = providerIds;
        emit ProviderPrioritySet(providerIds);
    }

    /// @notice Executes a flash loan with automatic provider fallback
    /// @dev Tries providers in priority order until one succeeds
    /// @param debtAsset The token to borrow (flash loaned)
    /// @param collateralAsset The token that will be received from liquidation
    /// @param debtToCover Amount of debt to cover (borrowed amount)
    /// @param targetContract Contract to call with flash loaned funds
    /// @param data Calldata to pass to target contract
    /// @return True if flash loan succeeded
    function flashLoan(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        address targetContract,
        bytes calldata data
    ) external returns(bool) {
        if(providerPriority.length == 0) revert EmptyProviderArray();
        if(
            debtAsset == address(0) ||
            targetContract == address(0) ||
            collateralAsset == address(0)
        ) revert InvalidAddress();
        if(debtToCover == 0) revert InvalidAmount();
        if (data.length == 0) revert InvalidReport();

        callCount++;

        if(!isRecorded[debtAsset]) debts.push(debtAsset);
        debtCovered[debtAsset] += debtToCover;

        // ...
        for (uint256 i = 0; i < providerPriority.length; i++) {
            address provider = providers[providerPriority[i]];
            if (provider == address(0)) continue;

            try IFlashLoan(provider).flashLoan(
                debtAsset,
                collateralAsset,
                debtToCover,
                targetContract,
                data
            ) {
                liquidationJobs[callCount] = LiquidationData({
                    debtAsset: debtAsset,
                    collateralAsset: collateralAsset,
                    amount: debtToCover
                });
                emit FlashLoanExecuted(providerPriority[i]);
                return true; // success
            } catch {
                emit FlashLoanRoutedOn(providerPriority[i]);
            }
        }

        revert("All flash loan providers failed!");
    }

    ///////// VIEW //////////

    /// @notice Returns the total number of flash loan calls
    /// @return The call count
    function getCallCount() external view returns(uint256) {
        return callCount;
    }

    /// @notice Returns liquidation data for a specific call
    /// @param _callCount The call count to query
    /// @return data The LiquidationData struct containing asset info and amounts
    function getLiquidationJob(uint256 _callCount) external view returns(LiquidationData memory data) {
        data = liquidationJobs[_callCount];
    }

    /// @notice Returns the current provider priority order
    /// @return list Array of provider IDs in priority order
    function getProviderPriority() external view returns(bytes32[] memory list) {
        list = providerPriority;
    }

    /// @notice Returns list of unique debt assets that have been covered
    /// @return list Array of debt asset addresses
    function getDebtsCovered() external view returns(address[] memory list) {
        list = debts;
    }

    /// @notice Returns total debt covered for a specific asset
    /// @param debt The debt asset address
    /// @return amount Total amount of debt covered for this asset
    function getDebtsCoveredAmount(address debt) external view returns(uint256 amount) {
        amount = debtCovered[debt];
    }

}
