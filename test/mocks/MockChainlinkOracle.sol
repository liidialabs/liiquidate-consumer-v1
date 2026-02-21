// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockV3Aggregator
 * @notice A mock Chainlink AggregatorV3Interface for testing purposes.
 *         Mimics the real Chainlink price feed including AnswerUpdated events.
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract MockV3Aggregator is AggregatorV3Interface {
    // -----------------------------------------------------------------------
    // Events — matches the real Chainlink AggregatorV3 events
    // -----------------------------------------------------------------------

    /// @notice Emitted whenever the answer is updated (mirrors Chainlink's event)
    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    /// @notice Emitted when a new round is started
    event NewRound(
        uint256 indexed roundId,
        address indexed startedBy,
        uint256 startedAt
    );

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    uint8 private _decimals;
    string private _description;
    uint256 private _version;

    uint80 private _latestRoundId;

    struct RoundData {
        int256  answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80  answeredInRound;
    }

    mapping(uint80 => RoundData) private _rounds;

    address public owner;

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "MockV3Aggregator: caller is not owner");
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /**
     * @param decimals_    Number of decimals the price feed uses (e.g. 8 for USD pairs)
     * @param initialAnswer The initial price to seed the feed with
     * @param description_ Human-readable description, e.g. "ETH / USD"
     */
    constructor(
        uint8   decimals_,
        int256  initialAnswer,
        string memory description_
    ) {
        owner        = msg.sender;
        _decimals    = decimals_;
        _description = description_;
        _version     = 4; // Chainlink aggregator v3 reports version 4

        _updateAnswer(initialAnswer);
    }

    // -----------------------------------------------------------------------
    // Admin — set prices
    // -----------------------------------------------------------------------

    /**
     * @notice Update the latest price answer and start a new round.
     * @param answer New price (scaled by `decimals`)
     */
    function updateAnswer(int256 answer) external {
        _updateAnswer(answer);
    }

    /**
     * @notice Update the answer with full round data control (useful for edge-case tests).
     * @param roundId         Round ID to set
     * @param answer          Price answer
     * @param startedAt       Timestamp round started
     * @param updatedAt       Timestamp answer was updated
     * @param answeredInRound Round in which the answer was computed
     */
    function updateRoundData(
        uint80  roundId,
        int256  answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80  answeredInRound
    ) external onlyOwner {
        _latestRoundId = roundId;

        _rounds[roundId] = RoundData({
            answer:          answer,
            startedAt:       startedAt,
            updatedAt:       updatedAt,
            answeredInRound: answeredInRound
        });

        emit AnswerUpdated(answer, roundId, updatedAt);
    }

    /**
     * @notice Transfer ownership of the mock (useful in multi-contract test setups).
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MockV3Aggregator: zero address");
        owner = newOwner;
    }

    // -----------------------------------------------------------------------
    // AggregatorV3Interface — view functions
    // -----------------------------------------------------------------------

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        return _getRoundData(_latestRoundId);
    }

    function getRoundData(uint80 roundId_)
        external
        view
        override
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        require(
            _rounds[roundId_].updatedAt != 0,
            "MockV3Aggregator: round not found"
        );
        return _getRoundData(roundId_);
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    function _updateAnswer(int256 answer) internal {
        _latestRoundId++;

        uint256 ts = block.timestamp;

        _rounds[_latestRoundId] = RoundData({
            answer:          answer,
            startedAt:       ts,
            updatedAt:       ts,
            answeredInRound: _latestRoundId
        });

        emit NewRound(_latestRoundId, msg.sender, ts);
        emit AnswerUpdated(answer, _latestRoundId, ts);
    }

    function _getRoundData(uint80 roundId_)
        internal
        view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        )
    {
        RoundData storage r = _rounds[roundId_];
        return (
            roundId_,
            r.answer,
            r.startedAt,
            r.updatedAt,
            r.answeredInRound
        );
    }
}
