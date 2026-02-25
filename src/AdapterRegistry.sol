// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ILiquidationAdapter } from "./interfaces/liquidationAdapter/ILiquidationAdapter.sol";

contract AdapterRegistry is Ownable {

    // protocol-name-in-bytes -> protocol address
    mapping(string => address) private adapters;

    /// EVENTS ///

    event AdapterRegistered(
        string protocol,
        address adapter
    );

    event AdapterRemoved(
        string protocol
    );

    /// ERRORS ///

    error InvalidAddress();
    error InvalidProtocol();
    error AlreadyRegistered();
    error ProtocolNonExistant();

    constructor() Ownable(msg.sender) {}

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

    function removeAdapter(
        string memory protocol
    ) external onlyOwner {
        if(bytes(protocol).length == 0) revert InvalidProtocol();
        if(adapters[protocol] == address(0)) revert ProtocolNonExistant();
        delete adapters[protocol];
        emit AdapterRemoved(protocol);
    }

    function getAdapter(
        string memory protocol
    ) external view returns (address) {
        if(bytes(protocol).length == 0) revert InvalidProtocol();
        return adapters[protocol];
    }
}
