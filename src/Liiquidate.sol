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
        address user;
        address collateralAsset;
        address debtAsset;
        uint256 debtToCover;
        string protocol;
    }

    AdapterRegistry public immutable registry;
    FlashLoanRouter public immutable flashLoan;

    /// EVENTS ///

    event LiquidationExecuted(
        string indexed protocol,
        address indexed user,
        address indexed adapter,
        bool success
    );

    /// ERRORS ///

    error InvalidAddress();
    error InvalidReport();
    error InvalidProtocol();
    error InvalidAmount();
    error EmptyJobArray();
    error AdapterNotFound(string protocol);

    uint256 public callCount;
    bytes public lastRawReport;
    bytes public lastDecodeError;

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
        callCount++;
        lastRawReport = report;
        // check for zero bytes
        if(report.length == 0) revert InvalidReport();
        // decode
        try this.decodeReport(report) returns (LiquidationReport[] memory jobs) {
            if(jobs.length == 0) revert EmptyJobArray();
            for (uint256 i = 0; i < jobs.length; i++) {
                _executeOne(jobs[i]);
            }
        } catch (bytes memory err) {
            lastDecodeError = err;
        }
    }

    function _executeOne(
        LiquidationReport memory job
    ) internal {
        // Get adapter address
        string memory protocolName = job.protocol;
        address adapterAddr = registry.getAdapter(protocolName);

        // Check for zero address
        if(adapterAddr == address(0)) revert AdapterNotFound(job.protocol);
        if(
            job.user == address(0) ||
            job.collateralAsset == address(0) ||
            job.debtAsset == address(0)
        ) revert InvalidAddress();
        if(bytes(job.protocol).length == 0) revert InvalidProtocol();
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

    function decodeReport(bytes calldata report) 
        external 
        pure 
        returns (LiquidationReport[] memory) 
    {
        return abi.decode(report, (LiquidationReport[]));
    }

    function decodeLastReport() 
        external 
        view 
        returns (LiquidationReport[] memory) 
    {
        return abi.decode(lastRawReport, (LiquidationReport[]));
    }

}
