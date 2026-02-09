// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ILiquidationAdapter } from "./interfaces/adapter/ILiquidationAdapter.sol";

contract AdapterRegistry is Ownable {

    // protocol-name-in-bytes -> protocol address
    mapping(bytes32 => address) private adapters;

    event AdapterRegistered(
        bytes32 protocol,
        address adapter
    );

    event AdapterRemoved(
        bytes32 protocol
    );

    constructor() Ownable(msg.sender) {}

    function registerAdapter(
        bytes32 protocol,
        address adapter
    ) external onlyOwner {
        require(adapter != address(0), "invalid adapter");
        adapters[protocol] = adapter;

        emit AdapterRegistered(protocol, adapter);
    }

    function removeAdapter(
        bytes32 protocol
    ) external onlyOwner {
        delete adapters[protocol];
        emit AdapterRemoved(protocol);
    }

    function getAdapter(
        bytes32 protocol
    ) external view returns (address) {
        return adapters[protocol];
    }
}
