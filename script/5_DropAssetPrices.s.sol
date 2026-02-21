// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockChainlinkOracle.sol";

contract DropAssetPrices is Script {
    MockV3Aggregator priceFeed;
    HelperConfig helperConfig;

    address private priceFeedAddress = address(1); // Replace with actual DebtManager address
    int256 constant NEW_PRICE = 1000e8; // Replace with price that we can simulate

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();
        (
            ,,,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        // Create contract instance
        priceFeed = MockV3Aggregator(priceFeedAddress);
        // Update price to simulate price drop
        priceFeed.updateAnswer(NEW_PRICE);
        // Log
        console2.log("Successfully dropped asset price to $%d!", NEW_PRICE / 1e8);

        vm.stopBroadcast();

    }
}