// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReceiverTemplate } from "./interfaces/chainlinkReceiver/ReceiverTemplate.sol";
import { ILiquidationAdapter } from "./interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import { AdapterRegistry } from "./AdapterRegistry.sol";
import { FlashLoanRouter } from "./FlashLoanRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Liiquidate
/// @notice Automated liquidation contract that processes Chainlink automation reports
///         and executes liquidations across multiple lending protocols using flash loans.
/// @dev Inherits from ReceiverTemplate for Chainlink automation integration.
///      Liquidations are executed by fetching adapter addresses from the registry,
///      then routing through the FlashLoanRouter for flash loan execution.
contract Liiquidate is ReceiverTemplate {
    /// @notice Data structure containing all information needed to execute a single liquidation
    /// @dev Used for decoding reports from Chainlink automation
    struct LiquidationReport {
        address user;           /// @dev Address of the user/account to be liquidated
        address collateralAsset; /// @dev Address of the collateral token to receive
        address debtAsset;      /// @dev Address of the debt token to repay
        uint256 debtToCover;   /// @dev Amount of debt to cover (in debt asset units)
        string protocol;        /// @dev Protocol identifier (e.g., "AAVE_V3", "COMPOUND")
    }

    /// @notice Registry contract for looking up liquidation adapters by protocol name
    AdapterRegistry public immutable registry;

    /// @notice Flash loan router for executing liquidations with borrowed funds
    FlashLoanRouter public immutable flashLoan;

    /// @notice USDC token instance for balance checks
    IERC20 usdc;

    /// @notice Counter for total number of reports processed
    /// @return The total count of _processReport calls
    uint256 public callCount;

    /// @notice Raw bytes of the last received report for debugging
    bytes public lastRawReport;

    /// @notice Decoding error from the last report for debugging
    bytes public lastDecodeError;

    /// EVENTS ///

    /// @notice Emitted when a liquidation is successfully executed
    /// @param protocol The protocol identifier
    /// @param user The account that was liquidated
    /// @param adapter The adapter address used for liquidation
    /// @param success Whether the flash loan was repaid successfully
    event LiquidationExecuted(
        string indexed protocol,
        address indexed user,
        address indexed adapter,
        bool success
    );

    /// @notice Emitted when a liquidation attempt fails
    /// @param user The account that failed to be liquidated
    event LiquidationFaied(address indexed user);

    /// ERRORS ///

    /// @notice Thrown when an address parameter is zero
    error InvalidAddress();

    /// @notice Thrown when the report data is invalid or empty
    error InvalidReport();

    /// @notice Thrown when the protocol string is empty
    error InvalidProtocol();

    /// @notice Thrown when the debt amount is zero
    error InvalidAmount();

    /// @notice Thrown when the jobs array is empty
    error EmptyJobArray();

    /// @notice Thrown when no adapter is registered for the given protocol
    /// @param protocol The protocol identifier that was not found
    error AdapterNotFound(string protocol);

    /// @notice Initializes the Liiquidate contract
    /// @param _debtAsset Address of the debt asset (e.g., USDC)
    /// @param _registry Address of the AdapterRegistry contract
    /// @param _flashLoan Address of the FlashLoanRouter contract
    /// @param _forwarderAddress Address of the Chainlink Automation forwarder
    constructor(
        address _debtAsset,
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
        usdc = IERC20(_debtAsset);
    }

    /// @notice Processes the automation report from Chainlink
    /// @dev Called by Chainlink Automation when automated liquidations are needed
    ///      Decodes the report into liquidation jobs and executes each one
    /// @param report The encoded bytes containing array of LiquidationReport structs
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

    /// @notice Simulates processing a report to calculate potential profit
    /// @dev Useful for estimating profitability before actual execution
    /// @param report The encoded bytes containing array of LiquidationReport structs
    /// @return profit The estimated profit from executing the liquidations
    function previewProcessReport(
        bytes calldata report
    ) external returns(uint256 profit) {
        // BEFORE
        uint256 balBefore = usdc.balanceOf(address(flashLoan));

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

        // AFTER
        uint256 balAfter = usdc.balanceOf(address(flashLoan));
        // profit
        profit = balAfter - balBefore;
    }

    /// @notice Executes a single liquidation job
    /// @dev Looks up the adapter from registry, builds execution payload,
    ///      and routes through flash loan router
    /// @param job The LiquidationReport containing liquidation parameters
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
        try flashLoan.flashLoan(
            job.debtAsset, 
            job.collateralAsset,
            job.debtToCover, 
            payload.target,
            payload.callData
        ) returns(bool resp) {
            // Success
            emit LiquidationExecuted(
                job.protocol,
                job.user,
                adapterAddr,
                resp
            );
        } catch {
            // Fail
            emit LiquidationFaied(job.user);
        }
    }

    /// @notice Decodes a liquidation report from bytes to struct array
    /// @dev External function that can be called to decode reports off-chain
    /// @param report The encoded bytes containing array of LiquidationReport structs
    /// @return Array of LiquidationReport structs
    function decodeReport(bytes calldata report) 
        external 
        pure 
        returns (LiquidationReport[] memory) 
    {
        return abi.decode(report, (LiquidationReport[]));
    }

    /// @notice Decodes the last received report from storage
    /// @dev Useful for debugging after _processReport is called
    /// @return Array of LiquidationReport structs from the last report
    function decodeLastReport() 
        external 
        view 
        returns (LiquidationReport[] memory) 
    {
        return abi.decode(lastRawReport, (LiquidationReport[]));
    }

}
