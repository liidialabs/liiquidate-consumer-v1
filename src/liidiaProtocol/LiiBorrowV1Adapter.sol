// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ILiquidationAdapter } from "../interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import { IDebtManager } from "./IDebtManager.sol";

/// @title LiiBorrowV1Adapter
/// @notice Adapter for LiiBorrow V1 protocol liquidations
/// @dev Implements ILiquidationAdapter to normalize liquidation positions
///      from LiiBorrow V1 lending protocol
contract LiiBorrowV1Adapter is ILiquidationAdapter {
    /// @notice The LiiBorrow DebtManager contract
    IDebtManager private immutable debtManager;

    /// @notice Base precision for calculations (1e18)
    uint256 private constant BASE_PRECISION = 1e18;

    /// @notice Percent precision (1e4 = 100%)
    uint256 private constant PERCENT_PRECISION = 1e4;

    /// @notice Maximum portion of debt that can be covered (50%)
    uint256 private constant CLOSE_FACTOR = 0.5e4;

    /// @notice Expected drop in value due to fees and slippage (90%)
    uint256 private constant EST_DROP_TO = 0.9e4;
    
    /// @notice Thrown when an address is zero
    error InvalidAddress();

    /// @notice Thrown when amount is zero
    error InvalidAmount();

    /// @notice Initializes the adapter
    /// @param _debtManager Address of the LiiBorrow DebtManager
    constructor(address _debtManager) {
        if(_debtManager == address(0)) revert InvalidAddress();

        debtManager = IDebtManager(_debtManager);
    }

    /// @notice Returns the protocol name
    /// @return "LIIBORROW_v1"
    function getProtocolName() external override pure returns (string memory) {
        return "LIIBORROW_v1";
    }

    /// @notice Returns this adapter's address
    /// @return Address of this adapter
    function getAdapterAddress() external override view returns (address) {
        return address(this);
    }

    /// @notice Gets the risk state for a user
    /// @dev Queries DebtManager for account data and liquidation status
    /// @param user The user address to check
    /// @return rs RiskState containing health metrics
    function getRiskState(
        address user
    ) external override returns (RiskState memory rs) {
        if(user == address(0)) revert InvalidAddress();

        (
            uint256 collateralBase,
            uint256 debtBase,
            uint256 healthFactor
        ) = debtManager.getUserAccountData(user);

        bool isLiquidatable = debtManager.isLiquidatable(user);

        rs = RiskState({
            liquidatable: isLiquidatable,
            riskMetric: healthFactor,
            collateralUSD: collateralBase,
            debtUSD: debtBase
        });
    }

    /// @notice Gets the liquidation status for a user
    /// @dev Calculates maximum debt to cover, expected return, and bonus
    /// @param user The user address to check
    /// @param collateralAsset The collateral asset address
    /// @return lp LiquidationStatus with amounts and bonus info
    function getLiquidationStatus(
        address user,
        address collateralAsset
    ) external override returns (LiquidationStatus memory lp) {
        if(
            user == address(0) ||
            collateralAsset == address(0)
        ) revert InvalidAddress();

        (
            ,
            uint256 debtBase,
            uint256 hf
        ) = debtManager.getUserAccountData(user);

        if (hf >= 1e18 || debtBase == 0) {
            return lp; // return empty params (NO REVERT)
        }

        uint256 maxDebtToCover = (debtBase * CLOSE_FACTOR) / PERCENT_PRECISION;
        uint256 liquidationBonus = debtManager.getLiquidationBonus(collateralAsset);
        liquidationBonus = liquidationBonus * PERCENT_PRECISION / BASE_PRECISION; // convert from 1e18 to dps

        uint256 bonus = maxDebtToCover *  liquidationBonus / PERCENT_PRECISION;
        uint256 maxReturn = maxDebtToCover + bonus;
        uint256 minReturn = maxReturn * EST_DROP_TO / PERCENT_PRECISION; // expect a 90% drop due to fees (flashloan + swap) & slippage

        lp = LiquidationStatus({
            maxDebtToCover: maxDebtToCover,
            actualReturn: maxReturn,
            expectedReturn: minReturn,
            expectedProfit: maxDebtToCover - minReturn,
            liquidationBonus: liquidationBonus
        });
    }

    /// @notice Builds the execution payload for liquidation
    /// @dev Encodes the liquidate function call for the DebtManager
    /// @param user The user to liquidate
    /// @param debtToCover Amount of debt to cover
    /// @param debtAsset The debt asset address
    /// @param collateralAsset The collateral asset address
    /// @return payload ExecutionPayload with target and calldata
    function buildExecutionPayload(
        address user,
        uint256 debtToCover,
        address debtAsset,
        address collateralAsset
    ) external override view returns (ExecutionPayload memory payload) {
        if(
            user == address(0) ||
            collateralAsset == address(0) ||
            debtAsset == address(0)
        ) revert InvalidAddress();
        if(debtToCover == 0) revert InvalidAmount();

        bytes memory callData = abi.encodeWithSelector(
            IDebtManager.liquidate.selector,
            user,
            debtAsset,
            collateralAsset,
            debtToCover,
            false
        );

        payload = ExecutionPayload({
            target: address(debtManager),
            callData: callData
        });
    }
}