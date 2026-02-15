// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReceiverTemplate } from "./interfaces/chainlinkReceiver/ReceiverTemplate.sol";
import { ILiquidationAdapter } from "./interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import { AdapterRegistry } from "./AdapterRegistry.sol";
import { FlashLoanRouter } from "./FlashLoanRouter.sol";

/// @title Liiquidate
/// @notice ...
/// @dev ...
contract Liiquidate is ReceiverTemplate {
    struct LiquidationReport {
        bytes32 protocol;
        address user;
        address collateralAsset;
        address debtAsset;
        uint256 debtToCover;
    }

    AdapterRegistry public immutable registry;
    FlashLoanRouter public immutable flashLoan;

    /// EVENTS ///

    event LiquidationExecuted(
        bytes32 indexed protocol,
        address indexed user,
        address indexed adapter,
        bool success
    );

    /// ERRORS ///

    error InvalidAddress();
    error InvalidReport();
    error InvalidProtocol();
    error InvalidAmount();

    constructor(
        address _registry, 
        address _flashLoan, 
        address _forwarderAddress
    ) ReceiverTemplate(_forwarderAddress) {
        if(
            _registry == address(0) ||
            _flashLoan == address(0) ||
            _forwarderAddress == address(0)
        ) revert InvalidAddress();

        registry = AdapterRegistry(_registry);
        flashLoan = FlashLoanRouter(_flashLoan);
    }

    function _processReport(
        bytes calldata report
    ) internal override {
        if (report.length == 0) revert InvalidReport();

        LiquidationReport[] memory jobs =
            abi.decode(report, (LiquidationReport[]));

        for (uint256 i = 0; i < jobs.length; i++) {
            _executeOne(jobs[i]);
        }
    }

    function _executeOne(
        LiquidationReport memory job
    ) internal {
        // Get adapter address
        address adapterAddr = registry.getAdapter(job.protocol);
        // Check not zero address
        if (adapterAddr == address(0)) {
            emit LiquidationExecuted(
                job.protocol,
                job.user,
                address(0),
                false
            );
            return;
        }
        // Check job data
        if(
            job.user == address(0) ||
            job.collateralAsset == address(0) ||
            job.debtAsset == address(0)
        ) revert InvalidAddress();
        if(job.protocol == bytes32(0)) revert InvalidProtocol();
        if(job.debtToCover == 0) revert InvalidAmount();

        // Instantiate adapter
        ILiquidationAdapter adapter = ILiquidationAdapter(adapterAddr);
        // Fetch target contract and callData
        ILiquidationAdapter.ExecutionPayload memory payload = adapter
            .buildExecutionPayload(
                job.user,
                job.debtToCover,
                job.debtAsset,
                job.collateralAsset
            );

        // Parse to flashloan to 1. Take flashLoan, 2. Liquidate, 3. Swap, 4. Repay
        bool resp = flashLoan.flashLoan(
            job.debtAsset, 
            job.collateralAsset,
            job.debtToCover, 
            payload.target,
            payload.callData
        );

        // Event
        emit LiquidationExecuted(
            job.protocol,
            job.user,
            adapterAddr,
            resp
        );
    }
}
