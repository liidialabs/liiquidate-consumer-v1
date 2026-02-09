// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/**
 * @title TestHelpers
 * @notice Common test utilities and helper functions
 */
contract TestHelpers is Test {
    // ========== CONSTANTS ==========

    uint256 internal constant ONE = 1e18;
    uint256 internal constant HUNDRED = 100e18;
    uint256 internal constant THOUSAND = 1000e18;
    uint256 internal constant ONE_MILLION = 1_000_000e18;

    uint8 internal constant DECIMALS_6 = 6; // USDC, USDT
    uint8 internal constant DECIMALS_8 = 8; // Price feeds
    uint8 internal constant DECIMALS_18 = 18; // Most tokens

    // Standard token amounts for testing
    uint256 internal constant MINT_AMOUNT_6 = 1_000_000e6; // 1M with 6 decimals
    uint256 internal constant MINT_AMOUNT_8 = 1_000_000e8;
    uint256 internal constant MINT_AMOUNT_18 = 1_000_000e18;

    // ========== NUMERIC UTILITIES ==========

    /**
     * @notice Scales a number to 18 decimals
     * @param amount The amount to scale
     * @param fromDecimals The source decimal places
     * @return The scaled amount
     */
    function scaleToDecimals(uint256 amount, uint8 fromDecimals)
        internal
        pure
        returns (uint256)
    {
        if (fromDecimals >= 18) {
            return amount / (10 ** (fromDecimals - 18));
        } else {
            return amount * (10 ** (18 - fromDecimals));
        }
    }

    /**
     * @notice Scales a number from 18 decimals
     * @param amount The amount to scale
     * @param toDecimals The target decimal places
     * @return The scaled amount
     */
    function scaleFromDecimals(uint256 amount, uint8 toDecimals)
        internal
        pure
        returns (uint256)
    {
        if (toDecimals >= 18) {
            return amount * (10 ** (toDecimals - 18));
        } else {
            return amount / (10 ** (18 - toDecimals));
        }
    }

    /**
     * @notice Calculates a percentage of a number
     * @param amount The base amount
     * @param percentBps Percentage in basis points (100 = 1%)
     * @return The percentage amount
     */
    function percentOf(uint256 amount, uint256 percentBps)
        internal
        pure
        returns (uint256)
    {
        return (amount * percentBps) / 10000;
    }

    /**
     * @notice Calculates basis points between two numbers
     * @param numerator The numerator
     * @param denominator The denominator
     * @return The basis points (10000 = 1)
     */
    function basisPoints(uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256)
    {
        if (denominator == 0) return 0;
        return (numerator * 10000) / denominator;
    }

    /**
     * @notice Checks if a number is within a tolerance
     * @param actual The actual value
     * @param expected The expected value
     * @param toleranceBps Tolerance in basis points
     * @return Whether actual is within tolerance of expected
     */
    function isWithinTolerance(
        uint256 actual,
        uint256 expected,
        uint256 toleranceBps
    ) internal pure returns (bool) {
        if (expected == 0) return actual == 0;

        uint256 difference = actual > expected
            ? actual - expected
            : expected - actual;
        uint256 allowedDifference = (expected * toleranceBps) / 10000;

        return difference <= allowedDifference;
    }

    // ========== ADDRESS UTILITIES ==========

    /**
     * @notice Creates unique addresses for testing
     * @param seed The seed for generating addresses
     * @param count Number of addresses to generate
     * @return Array of generated addresses
     */
    function generateAddresses(uint256 seed, uint256 count)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory addresses = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            addresses[i] = address(
                uint160(uint256(keccak256(abi.encodePacked(seed, i))))
            );
        }

        return addresses;
    }

    /**
     * @notice Creates a bytes32 hash from a string (for protocol IDs, etc.)
     * @param value The string value
     * @return The bytes32 hash
     */
    function hashString(string memory value)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(value));
    }

    /**
     * @notice Creates a bytes32 hash from a number and type
     * @param label The label (e.g., "PROTOCOL")
     * @param number The number to encode
     * @return The bytes32 hash
     */
    function hashWithNumber(string memory label, uint256 number)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(label, number));
    }

    // ========== ARRAY UTILITIES ==========

    /**
     * @notice Creates an array of addresses
     * @param addrs The addresses to include
     * @return Array of addresses
     */
    function addressArray(address[] memory addrs)
        internal
        pure
        returns (address[] memory)
    {
        return addrs;
    }

    /**
     * @notice Creates an array with a single address
     * @param addr The address
     * @return Array with one address
     */
    function singleAddressArray(address addr)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory arr = new address[](1);
        arr[0] = addr;
        return arr;
    }

    /**
     * @notice Creates an array of bytes32 values
     * @param values The values
     * @return Array of bytes32
     */
    function bytes32Array(bytes32[] memory values)
        internal
        pure
        returns (bytes32[] memory)
    {
        return values;
    }

    /**
     * @notice Creates an array with a single bytes32 value
     * @param value The value
     * @return Array with one bytes32
     */
    function singleBytes32Array(bytes32 value)
        internal
        pure
        returns (bytes32[] memory)
    {
        bytes32[] memory arr = new bytes32[](1);
        arr[0] = value;
        return arr;
    }

    /**
     * @notice Creates an array of uint256 values
     * @param values The values
     * @return Array of uint256
     */
    function uint256Array(uint256[] memory values)
        internal
        pure
        returns (uint256[] memory)
    {
        return values;
    }

    // ========== ASSERTION UTILITIES ==========

    /**
     * @notice Asserts that two uint256 are approximately equal
     * @param actual The actual value
     * @param expected The expected value
     * @param tolerance The tolerance (absolute)
     * @param message The error message
     */
    function assertApproxEq(
        uint256 actual,
        uint256 expected,
        uint256 tolerance,
        string memory message
    ) internal {
        uint256 difference = actual > expected
            ? actual - expected
            : expected - actual;

        assertLe(difference, tolerance, message);
    }

    /**
     * @notice Asserts that a value is between min and max (inclusive)
     * @param value The value to check
     * @param min The minimum value
     * @param max The maximum value
     * @param message The error message
     */
    function assertInRange(
        uint256 value,
        uint256 min,
        uint256 max,
        string memory message
    ) internal {
        assertGe(value, min, message);
        assertLe(value, max, message);
    }

    /**
     * @notice Asserts that two arrays are equal
     * @param actual The actual array
     * @param expected The expected array
     * @param message The error message
     */
    function assertArrayEq(
        address[] memory actual,
        address[] memory expected,
        string memory message
    ) internal {
        assertEq(actual.length, expected.length, message);

        for (uint256 i = 0; i < actual.length; i++) {
            assertEq(actual[i], expected[i], message);
        }
    }

    /**
     * @notice Asserts that bytes32 arrays are equal
     * @param actual The actual array
     * @param expected The expected array
     * @param message The error message
     */
    function assertBytes32ArrayEq(
        bytes32[] memory actual,
        bytes32[] memory expected,
        string memory message
    ) internal {
        assertEq(actual.length, expected.length, message);

        for (uint256 i = 0; i < actual.length; i++) {
            assertEq(actual[i], expected[i], message);
        }
    }

    // ========== TIME UTILITIES ==========

    /**
     * @notice Gets one day in seconds
     * @return 1 day
     */
    function oneDay() internal pure returns (uint256) {
        return 1 days;
    }

    /**
     * @notice Gets one week in seconds
     * @return 1 week
     */
    function oneWeek() internal pure returns (uint256) {
        return 1 weeks;
    }

    /**
     * @notice Gets one year in seconds
     * @return 1 year
     */
    function oneYear() internal pure returns (uint256) {
        return 365 days;
    }

    /**
     * @notice Moves time forward
     * @param seconds The number of seconds to advance
     */
    function moveTimeForward(uint256 seconds) internal {
        vm.warp(block.timestamp + seconds);
    }

    /**
     * @notice Moves time to a specific timestamp
     * @param timestamp The target timestamp
     */
    function moveTimeTo(uint256 timestamp) internal {
        vm.warp(timestamp);
    }

    // ========== PROTOCOL UTILITIES ==========

    /**
     * @notice Creates common protocol IDs as bytes32
     * @return aave Aave V3 protocol ID
     * @return uni Uniswap V4 protocol ID
     * @return compound Compound protocol ID
     */
    function defaultProtocolIds()
        internal
        pure
        returns (
            bytes32 aave,
            bytes32 uni,
            bytes32 compound
        )
    {
        aave = keccak256("AAVE_V3");
        uni = keccak256("UNISWAP_V4");
        compound = keccak256("COMPOUND");
    }

    /**
     * @notice Gets health factor threshold for liquidation
     * @return 1e18 (health factor of 1.0)
     */
    function liquidationThreshold() internal pure returns (uint256) {
        return 1e18;
    }

    /**
     * @notice Gets a safe health factor
     * @return 2e18 (health factor of 2.0)
     */
    function safeHealthFactor() internal pure returns (uint256) {
        return 2e18;
    }

    // ========== LOGGING UTILITIES ==========

    /**
     * @notice Logs a test case name
     * @param testName The name of the test
     */
    function logTest(string memory testName) internal {
        console.log(
            "\n================ TEST: %s ================",
            testName
        );
    }

    /**
     * @notice Logs a section header
     * @param section The section name
     */
    function logSection(string memory section) internal {
        console.log("\n--- %s ---", section);
    }

    /**
     * @notice Logs a key-value pair
     * @param key The key
     * @param value The value
     */
    function logKeyValue(string memory key, uint256 value) internal {
        console.log("%s: %d", key, value);
    }

    /**
     * @notice Logs an address
     * @param label The label
     * @param addr The address
     */
    function logAddress(string memory label, address addr) internal {
        console.log("%s: %s", label, addr);
    }

    /**
     * @notice Logs the gas used
     * @param label The label
     * @param gasUsed The gas amount
     */
    function logGas(string memory label, uint256 gasUsed) internal {
        console.log("%s gas: %d", label, gasUsed);
    }
}
