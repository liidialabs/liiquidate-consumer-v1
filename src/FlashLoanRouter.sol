// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IFlashLoan } from "./interfaces/flashloans/IFlashLoan.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FlashLoanRouter is Ownable {

    mapping(bytes32 => address) public providers;
    mapping(address => uint256) private debtCovered;
    mapping(address => bool) private isRecorded;

    bytes32[] private providerPriority;
    address[] private debts;
    uint256 private callCount;

    event ProviderAdded(bytes32 id, address provider);
    event ProviderRemoved(bytes32 id);
    event ProviderPrioritySet(bytes32[] providers);
    event FlashLoanRoutedOn(bytes32 provider);
    event FlashLoanExecuted(bytes32 provider);
    event FlashLoanFailed(bytes32 provider);

    constructor() Ownable(msg.sender) {
        callCount = 0;
    }

    function addProvider(address provider) external onlyOwner {
        require(provider != address(0), "Invalid Address");
        bytes32 id = IFlashLoan(provider).id();
        providers[id] = provider;
        emit ProviderAdded(id, provider);
    }

    function removeProvider(bytes32 id) external onlyOwner {
        require(id != bytes32(0), "Invalid Address");
        delete providers[id];
        emit ProviderRemoved(id);
    }

    /// @notice Set UniswapV4 as first priority due to zero fees
    function setProviderPriority(
        bytes32[] calldata providerIds
    ) external onlyOwner {
        require(providerIds.length > 0, "empty list"); 

        providerPriority = providerIds;

        emit ProviderPrioritySet(providerIds);
    }

    function flashLoan(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        address targetContract,
        bytes calldata data
    ) external returns(bool) {
        require(providerPriority.length > 0, "Provider Priority Not Set");

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
                emit FlashLoanExecuted(providerPriority[i]);
                return true; // success
            } catch {
                emit FlashLoanRoutedOn(providerPriority[i]);
            }
        }

        revert("all flash loan providers failed");
    }

    ///////// VIEW //////////

    function getCallCount() external view returns(uint256) {
        return callCount;
    }

    function getProviderPriority() external view returns(bytes32[] memory list) {
        list = providerPriority;
    }

    function getDebtsCovered() external view returns(address[] memory list) {
        list = debts;
    }

    function getDebtsCoveredAmount(address debt) external view returns(uint256 amount) {
        amount = debtCovered[debt];
    }
}
