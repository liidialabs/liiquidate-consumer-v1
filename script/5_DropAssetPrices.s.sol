// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "../test/mocks/MockChainlinkOracle.sol";
import {IMockAaveOracle} from "../test/mocks/interfaces/IMockAaveOracle.sol";
import {IDebtManager} from "../src/liidiaProtocol/IDebtManager.sol";

contract DropAssetPrices is Script {
    MockV3Aggregator priceFeed;
    HelperConfig helperConfig;
    IMockAaveOracle aaveOracle;
    IDebtManager debtManager;

    int256 constant NEW_PRICE = 1600e8; // Drop to $1600
    uint256 private userKey = vm.envUint("PRIVATE_KEY_USER");

    function run() public {
        // deploy helper config
        helperConfig = new HelperConfig();

        // Create contract instance
        priceFeed = MockV3Aggregator(helperConfig.mockChainlinkOracle());
        aaveOracle = IMockAaveOracle(helperConfig.mockAaveV3Oracle());
        debtManager = IDebtManager(helperConfig.debtManagerAddress());

        // Log health factor before price drop
        uint256 hfBefore = debtManager.getHealthFactor(vm.addr(userKey));
        bool isLiquidatableBefore = debtManager.isLiquidatable(vm.addr(userKey));
        console2.log("User Health Factor before price drop: %s", hfBefore);
        console2.log("User is liquidatable before price drop: %s", isLiquidatableBefore);
        console2.log("------------------------------------------------------------");

        vm.startBroadcast(userKey);
        
        // Update price to simulate price drop on chainlink oracle & Aave oracle
        aaveOracle.setAssetPrice(helperConfig.WETH(), uint256(NEW_PRICE));
        priceFeed.updateAnswer(NEW_PRICE);
        // Log
        console2.log("Successfully dropped asset price to $%d!", NEW_PRICE / 1e8);

        vm.stopBroadcast();

        // Log health factor after price drop
        uint256 hfAfter = debtManager.getHealthFactor(vm.addr(userKey));
        bool isLiquidatableAfter = debtManager.isLiquidatable(vm.addr(userKey));
        console2.log("------------------------------------------------------------");
        console2.log("User Health Factor after price drop: %s", hfAfter);
        console2.log("User is liquidatable after price drop: %s", isLiquidatableAfter);

    }
}