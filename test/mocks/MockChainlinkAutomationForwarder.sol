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

    function trustReceiver(address receiver) external {
        require(receiver != address(0), "Invalid receiver");
        trustedReceivers[receiver] = true;
        emit ReceiverTrusted(receiver);
    }

    function untrustReceiver(address receiver) external {
        require(receiver != address(0), "Invalid receiver");
        trustedReceivers[receiver] = false;
        emit ReceiverUntrusted(receiver);
    }

    function isTrusted(address receiver) external view returns (bool) {
        return trustedReceivers[receiver];
    }

    // ========== WORKFLOW MANAGEMENT ==========

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
    ) public returns (bool) {
        require(receiver != address(0), "Invalid receiver");
        require(workflowId != bytes32(0), "Invalid workflow ID");

        totalReports++;

        // Get workflow metadata
        WorkflowMetadata memory metadata = workflows[workflowId];
        
        // ✅ FIXED: Use abi.encodePacked instead of abi.encode
        bytes memory encodedMetadata = abi.encodePacked(
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
        } catch {
            failedReports++;
            emit ReportProcessed(workflowId, receiver, false, "Unknown error");
            return false;
        }
    }

    /**
     * @notice Internal function to call receiver onReport
     */
    function _callReceiver(
        address receiver,
        bytes memory metadata,
        bytes calldata report
    ) external {
        // Only allow calls from this contract
        require(msg.sender == address(this), "Only self-calls allowed");
        
        (bool success, bytes memory returnData) = receiver.call(
            abi.encodeWithSignature("onReport(bytes,bytes)", metadata, report)
        );

        if (!success) {
            // Bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
            revert("Receiver call failed");
        }
    }

    // ========== BATCH OPERATIONS ==========

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

    function getStats()
        external
        view
        returns (uint256 total, uint256 successful, uint256 failed)
    {
        return (totalReports, successfulReports, failedReports);
    }

    function getSuccessRate() external view returns (uint256) {
        if (totalReports == 0) return 0;
        return (successfulReports * 10000) / totalReports;
    }

    function resetStats() external {
        totalReports = 0;
        successfulReports = 0;
        failedReports = 0;
    }

    // ========== TESTING UTILITIES ==========

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
     * ✅ FIXED: Use abi.encodePacked
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
        // ✅ FIXED: Use abi.encodePacked
        encodedMetadata = abi.encodePacked(workflowId, workflowName, owner);
        reportPayload = reportData;
    }
}