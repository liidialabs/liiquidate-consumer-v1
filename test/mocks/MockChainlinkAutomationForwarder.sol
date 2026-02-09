// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockChainlinkAutomationForwarder
 * @notice Mock Chainlink Automation Forwarder for testing workflow receivers
 * @dev Simulates the Chainlink Automation forwarder behavior
 */
contract MockChainlinkAutomationForwarder {
    // Workflow metadata
    struct WorkflowMetadata {
        bytes32 workflowId;
        bytes10 workflowName;
        address workflowOwner;
    }

    // Forwarder configuration
    mapping(address => bool) public trustedReceivers;
    mapping(bytes32 => WorkflowMetadata) public workflows;

    // Statistics
    uint256 public totalReports;
    uint256 public successfulReports;
    uint256 public failedReports;

    // Events
    event ReceiverTrusted(address indexed receiver);
    event ReceiverUntrusted(address indexed receiver);
    event WorkflowCreated(
        bytes32 indexed workflowId,
        address indexed owner,
        bytes10 name
    );
    event ReportProcessed(
        bytes32 indexed workflowId,
        address indexed receiver,
        bool success,
        string reason
    );

    constructor() {}

    // ========== RECEIVER MANAGEMENT ==========

    /**
     * @notice Trusts a receiver contract
     * @param receiver The receiver contract address
     */
    function trustReceiver(address receiver) external {
        require(receiver != address(0), "Invalid receiver");
        trustedReceivers[receiver] = true;
        emit ReceiverTrusted(receiver);
    }

    /**
     * @notice Removes trust from a receiver
     * @param receiver The receiver contract address
     */
    function untrustReceiver(address receiver) external {
        require(receiver != address(0), "Invalid receiver");
        trustedReceivers[receiver] = false;
        emit ReceiverUntrusted(receiver);
    }

    /**
     * @notice Checks if a receiver is trusted
     * @param receiver The receiver address
     * @return Whether the receiver is trusted
     */
    function isTrusted(address receiver) external view returns (bool) {
        return trustedReceivers[receiver];
    }

    // ========== WORKFLOW MANAGEMENT ==========

    /**
     * @notice Creates a workflow
     * @param workflowId The workflow ID
     * @param workflowName The workflow name (10 bytes max)
     * @param owner The workflow owner
     */
    function createWorkflow(
        bytes32 workflowId,
        bytes10 workflowName,
        address owner
    ) external {
        require(workflowId != bytes32(0), "Invalid workflow ID");
        require(owner != address(0), "Invalid owner");

        workflows[workflowId] = WorkflowMetadata({
            workflowId: workflowId,
            workflowName: workflowName,
            workflowOwner: owner
        });

        emit WorkflowCreated(workflowId, owner, workflowName);
    }

    /**
     * @notice Gets workflow metadata
     * @param workflowId The workflow ID
     * @return The workflow metadata
     */
    function getWorkflow(
        bytes32 workflowId
    ) external view returns (WorkflowMetadata memory) {
        return workflows[workflowId];
    }

    // ========== REPORT PROCESSING ==========

    /**
     * @notice Sends a report to a receiver (simulates Chainlink forwarder)
     * @param receiver The receiver contract
     * @param workflowId The workflow ID
     * @param workflowName The workflow name
     * @param report The report data
     */
    function sendReport(
        address receiver,
        bytes32 workflowId,
        bytes10 workflowName,
        bytes calldata report
    ) external returns (bool) {
        require(receiver != address(0), "Invalid receiver");
        require(workflowId != bytes32(0), "Invalid workflow ID");

        totalReports++;

        // Encode metadata
        WorkflowMetadata memory metadata = workflows[workflowId];
        bytes memory encodedMetadata = abi.encode(
            workflowId,
            workflowName,
            metadata.workflowOwner
        );

        // Call onReport on receiver
        try this._callReceiver(receiver, encodedMetadata, report) {
            successfulReports++;
            emit ReportProcessed(
                workflowId,
                receiver,
                true,
                "Report processed successfully"
            );
            return true;
        } catch Error(string memory reason) {
            failedReports++;
            emit ReportProcessed(workflowId, receiver, false, reason);
            return false;
        }
    }

    /**
     * @notice Internal function to call receiver onReport
     * @param receiver The receiver contract
     * @param metadata Encoded workflow metadata
     * @param report The report data
     */
    function _callReceiver(
        address receiver,
        bytes memory metadata,
        bytes calldata report
    ) external {
        // This uses delegatecall pattern to simulate forwarder
        (bool success, ) = receiver.call(
            abi.encodeWithSignature("onReport(bytes,bytes)", metadata, report)
        );

        require(success, "Receiver call failed");
    }

    // ========== BATCH OPERATIONS ==========

    /**
     * @notice Sends multiple reports in batch
     * @param receivers Array of receiver addresses
     * @param workflowIds Array of workflow IDs
     * @param reports Array of report data
     * @return successCount Number of successful reports
     */
    function sendBatchReports(
        address[] calldata receivers,
        bytes32[] calldata workflowIds,
        bytes[] calldata reports
    ) external returns (uint256 successCount) {
        require(
            receivers.length == workflowIds.length &&
                workflowIds.length == reports.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < receivers.length; i++) {
            bytes10 workflowName = workflows[workflowIds[i]].workflowName;

            if (
                sendReport(
                    receivers[i],
                    workflowIds[i],
                    workflowName,
                    reports[i]
                )
            ) {
                successCount++;
            }
        }
    }

    // ========== STATISTICS ==========

    /**
     * @notice Gets forwarder statistics
     * @return total Total reports sent
     * @return successful Successful reports
     * @return failed Failed reports
     */
    function getStats()
        external
        view
        returns (uint256 total, uint256 successful, uint256 failed)
    {
        return (totalReports, successfulReports, failedReports);
    }

    /**
     * @notice Gets success rate as basis points
     * @return Success rate (10000 = 100%)
     */
    function getSuccessRate() external view returns (uint256) {
        if (totalReports == 0) return 0;
        return (successfulReports * 10000) / totalReports;
    }

    /**
     * @notice Resets statistics
     */
    function resetStats() external {
        totalReports = 0;
        successfulReports = 0;
        failedReports = 0;
    }

    // ========== TESTING UTILITIES ==========

    /**
     * @notice Simulates a report with validation
     * @param receiver The receiver to test
     * @param metadata The metadata
     * @param report The report data
     * @return Whether the call would succeed
     */
    function validateReport(
        address receiver,
        bytes calldata metadata,
        bytes calldata report
    ) external returns (bool) {
        require(receiver != address(0), "Invalid receiver");

        try this._callReceiver(receiver, metadata, report) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Creates a test report payload
     * @param workflowId The workflow ID
     * @param owner The workflow owner
     * @param reportData The actual report data
     * @return encodedMetadata The encoded metadata
     * @return reportPayload The report payload
     */
    function createTestReport(
        bytes32 workflowId,
        bytes10 workflowName,
        address owner,
        bytes calldata reportData
    )
        external
        pure
        returns (bytes memory encodedMetadata, bytes memory reportPayload)
    {
        encodedMetadata = abi.encode(workflowId, workflowName, owner);
        reportPayload = reportData;
    }
}
