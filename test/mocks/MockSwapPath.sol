// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockSwapPath
 * @notice Mock utility for testing complex multi-hop swap paths
 * @dev Provides path construction and verification for DEX routing
 */
contract MockSwapPath {
    struct SwapStep {
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 fee; // Pool fee in bps (e.g., 3000 = 0.3%)
    }

    struct SwapPath {
        uint256 id;
        SwapStep[] steps;
        uint256 minOutput;
        address owner;
        bool isActive;
    }

    mapping(uint256 => SwapPath) public paths;
    uint256 public pathCounter;

    // Path templates for common operations
    mapping(bytes32 => uint256) public pathTemplates; // Hash of (tokenIn, tokenOut) => pathId

    event PathCreated(
        uint256 indexed pathId,
        address indexed owner,
        uint256 stepCount
    );
    event PathUpdated(uint256 indexed pathId, uint256 minOutput);
    event PathDeactivated(uint256 indexed pathId);
    event TemplateRegistered(bytes32 indexed hash, uint256 pathId);

    /**
     * @notice Creates a swap path
     * @param steps The swap steps
     * @param minOutput Minimum output amount
     * @return pathId The created path ID
     */
    function createPath(
        SwapStep[] calldata steps,
        uint256 minOutput
    ) external returns (uint256 pathId) {
        require(steps.length > 0, "Must have at least one step");
        require(steps.length <= 10, "Path too long");

        pathId = ++pathCounter;
        SwapPath storage path = paths[pathId];

        path.id = pathId;
        path.minOutput = minOutput;
        path.owner = msg.sender;
        path.isActive = true;

        // Copy steps
        for (uint256 i = 0; i < steps.length; i++) {
            path.steps.push(steps[i]);
        }

        emit PathCreated(pathId, msg.sender, steps.length);
    }

    /**
     * @notice Updates path minimum output
     * @param pathId The path ID
     * @param newMinOutput New minimum output
     */
    function updatePathMinOutput(
        uint256 pathId,
        uint256 newMinOutput
    ) external {
        SwapPath storage path = paths[pathId];
        require(path.owner == msg.sender, "Not owner");
        path.minOutput = newMinOutput;
        emit PathUpdated(pathId, newMinOutput);
    }

    /**
     * @notice Deactivates a path
     * @param pathId The path ID
     */
    function deactivatePath(uint256 pathId) external {
        SwapPath storage path = paths[pathId];
        require(path.owner == msg.sender, "Not owner");
        path.isActive = false;
        emit PathDeactivated(pathId);
    }

    /**
     * @notice Registers path as template
     * @param pathId The path ID
     * @param tokenIn Input token
     * @param tokenOut Output token
     */
    function registerTemplate(
        uint256 pathId,
        address tokenIn,
        address tokenOut
    ) external {
        require(paths[pathId].owner == msg.sender, "Not owner");
        bytes32 hash = keccak256(abi.encodePacked(tokenIn, tokenOut));
        pathTemplates[hash] = pathId;
        emit TemplateRegistered(hash, pathId);
    }

    /**
     * @notice Gets path data
     * @param pathId The path ID
     * @return The swap path
     */
    function getPath(uint256 pathId) external view returns (SwapPath memory) {
        return paths[pathId];
    }

    /**
     * @notice Gets path steps
     * @param pathId The path ID
     * @return The swap steps
     */
    function getPathSteps(
        uint256 pathId
    ) external view returns (SwapStep[] memory) {
        return paths[pathId].steps;
    }

    /**
     * @notice Gets number of hops in path
     * @param pathId The path ID
     * @return The number of hops
     */
    function getPathLength(uint256 pathId) external view returns (uint256) {
        return paths[pathId].steps.length;
    }

    /**
     * @notice Verifies path validity
     * @param pathId The path ID
     * @return Whether path is valid
     */
    function isPathValid(uint256 pathId) external view returns (bool) {
        if (pathId == 0 || pathId > pathCounter) return false;
        if (!paths[pathId].isActive) return false;

        SwapStep[] storage steps = paths[pathId].steps;
        if (steps.length == 0) return false;

        // Verify step continuity
        for (uint256 i = 0; i < steps.length - 1; i++) {
            if (steps[i].tokenOut != steps[i + 1].tokenIn) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Gets expected output path
     * @param pathId The path ID
     * @return tokenIn The input token
     * @return tokenOut The output token
     */
    function getPathTokens(
        uint256 pathId
    ) external view returns (address tokenIn, address tokenOut) {
        SwapStep[] storage steps = paths[pathId].steps;
        require(steps.length > 0, "Empty path");

        tokenIn = steps[0].tokenIn;
        tokenOut = steps[steps.length - 1].tokenOut;
    }

    /**
     * @notice Calculates total fees in path
     * @param pathId The path ID
     * @return totalFee The total fees in bps
     */
    function calculatePathFees(
        uint256 pathId
    ) external view returns (uint256 totalFee) {
        SwapStep[] storage steps = paths[pathId].steps;
        for (uint256 i = 0; i < steps.length; i++) {
            totalFee += steps[i].fee;
        }
    }

    /**
     * @notice Gets reverse path (swaps tokenIn/tokenOut)
     * @param pathId The path ID
     * @return reverseSteps The reversed steps
     */
    function getReversePathSteps(
        uint256 pathId
    ) external view returns (SwapStep[] memory reverseSteps) {
        SwapStep[] storage steps = paths[pathId].steps;
        reverseSteps = new SwapStep[](steps.length);

        for (uint256 i = 0; i < steps.length; i++) {
            uint256 j = steps.length - 1 - i;
            reverseSteps[i] = SwapStep({
                pool: steps[j].pool,
                tokenIn: steps[j].tokenOut,
                tokenOut: steps[j].tokenIn,
                fee: steps[j].fee
            });
        }
    }

    /**
     * @notice Tests if two paths are equivalent
     * @param pathId1 First path
     * @param pathId2 Second path
     * @return Whether paths are same
     */
    function arePathsEquivalent(
        uint256 pathId1,
        uint256 pathId2
    ) external view returns (bool) {
        SwapStep[] storage steps1 = paths[pathId1].steps;
        SwapStep[] storage steps2 = paths[pathId2].steps;

        if (steps1.length != steps2.length) return false;

        for (uint256 i = 0; i < steps1.length; i++) {
            if (
                steps1[i].pool != steps2[i].pool ||
                steps1[i].tokenIn != steps2[i].tokenIn ||
                steps1[i].tokenOut != steps2[i].tokenOut
            ) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Gets template for token pair
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @return pathId The template path ID (0 if not found)
     */
    function getTemplate(
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 pathId) {
        bytes32 hash = keccak256(abi.encodePacked(tokenIn, tokenOut));
        return pathTemplates[hash];
    }

    /**
     * @notice Gets total number of created paths
     * @return The count
     */
    function getPathCount() external view returns (uint256) {
        return pathCounter;
    }
}
