// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFlashLoan {
    /// @notice ...
    function flashLoan(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        address targetContract,
        bytes calldata data
    ) external;

    function id() external pure returns (bytes32);
}