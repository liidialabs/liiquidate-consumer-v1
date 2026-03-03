// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ILiquidationAdapter } from "./interfaces/liquidationAdapter/ILiquidationAdapter.sol";

/**
 * @title AdapterRegistry
 * @author Liidia Team
 * @notice Registry for mapping protocol names to liquidation adapter addresses
 * @dev Allows owner to register and remove adapters that implement ILiquidationAdapter
 *      Used by Liiquidate to dynamically resolve which adapter to use for each protocol
*/
contract AdapterRegistry is Ownable {

    /// @notice Maps protocol name string to adapter address
    /// @dev Protocol names are stored as strings (e.g., "AAVE_V3", "COMPOUND")
    mapping(string => address) private adapters;

    /// EVENTS ///

    /// @notice Emitted when an adapter is registered
    /// @param protocol The protocol identifier
    /// @param adapter The adapter contract address
    event AdapterRegistered(
        string protocol,
        address adapter
    );

    /// @notice Emitted when an adapter is removed
    /// @param protocol The protocol identifier
    event AdapterRemoved(
        string protocol
    );

    /// ERRORS ///

    /// @notice Thrown when an address parameter is zero
    error InvalidAddress();

    /// @notice Thrown when the protocol string is empty
    error InvalidProtocol();

    /// @notice Thrown when attempting to register an adapter that already exists
    error AlreadyRegistered();

    /// @notice Thrown when attempting to remove a non-existent protocol
    error ProtocolNonExistant();
    

    /// @notice Initializes the AdapterRegistry
    constructor() Ownable(msg.sender) {}

    /// @notice Registers a new liquidation adapter
    /// @dev The adapter's getProtocolName() is called to determine the protocol identifier
    /// @param adapter The address of the ILiquidationAdapter implementation
    function registerAdapter(
        address adapter
    ) external onlyOwner {
        if(adapter == address(0)) revert InvalidAddress();

        ILiquidationAdapter liquidationAdapter = ILiquidationAdapter(adapter);
        string memory protocolName = liquidationAdapter.getProtocolName();

        if(adapters[protocolName] != address(0)) revert AlreadyRegistered();

        adapters[protocolName] = adapter;
        emit AdapterRegistered(protocolName, adapter);
    }

    /// @notice Removes a liquidation adapter
    /// @param protocol The protocol identifier to remove
    function removeAdapter(
        string memory protocol
    ) external onlyOwner {
        if(bytes(protocol).length == 0) revert InvalidProtocol();
        if(adapters[protocol] == address(0)) revert ProtocolNonExistant();
        delete adapters[protocol];
        emit AdapterRemoved(protocol);
    }

    /// @notice Retrieves the adapter address for a given protocol
    /// @param protocol The protocol identifier to look up
    /// @return The adapter contract address, or address(0) if not found
    function getAdapter(
        string memory protocol
    ) external view returns (address) {
        if(bytes(protocol).length == 0) revert InvalidProtocol();
        return adapters[protocol];
    }
}
