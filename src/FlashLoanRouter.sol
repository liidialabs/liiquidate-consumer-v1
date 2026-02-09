// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IFlashLoan } from "./interfaces/flashloans/IFlashLoan.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FlashLoanRouter is Ownable {

    //
    bytes32 public constant DEFAULT_PROVIDER_ID = keccak256("AAVE_V3");

    // providerId => provider address
    mapping(bytes32 => address) public providers;

    // asset => ordered provider IDs
    bytes32[] public providerPriority;

    event ProviderAdded(bytes32 id, address provider);
    event ProviderRemoved(bytes32 id);
    event ProviderPrioritySet(bytes32[] providers);
    event FlashLoanRoutedOn(bytes32 providerId);
    event FlashLoanExecuted(bytes32 provider);

    constructor() Ownable(msg.sender) {}

    function addProvider(address provider) external onlyOwner {
        bytes32 id = IFlashLoan(provider).id();
        providers[id] = provider;
        emit ProviderAdded(id, provider);
    }

    function removeProvider(bytes32 id) external onlyOwner {
        delete providers[id];
        emit ProviderRemoved(id);
    }

    function setProviderPriority(
        string[] calldata providerIds
    ) external onlyOwner {
        require(providerIds.length > 0, "empty list");
        
        bytes32[] memory convertedIds = new bytes32[](providerIds.length);
        for (uint256 i = 0; i < providerIds.length; i++) {
            convertedIds[i] = keccak256(abi.encodePacked(providerIds[i]));
        }
        
        providerPriority = convertedIds;
        emit ProviderPrioritySet(convertedIds);
    }

    function flashLoan(
        address debtAsset,
        address collateralAsset
        uint256 debtToCover,
        address targetContract,
        bytes calldata data
    ) external {
        if(providerPriority.length == 0) {
            address provider = providers[DEFAULT_PROVIDER_ID];
            if (provider == address(0)) return;
            IFlashLoan(provider).flashLoan(
                debtAsset,
                collateralAsset
                debtToCover,
                targetContract,
                data
            );
            return;
        }

        for (uint256 i = 0; i < providerPriority.length; i++) {
            address provider = providers[providerPriority[i]];
            if (provider == address(0)) continue;

            try IFlashLoan(provider).flashLoan(
                debtAsset,
                collateralAsset
                debtToCover,
                targetContract,
                data
            ) {
                emit FlashLoanExecuted(providerPriority[i]);
                return; // success
            } catch {
                emit FlashLoanRoutedOn(providerPriority[i]);
            }
        }

        revert("all flash loan providers failed");
    }
}
