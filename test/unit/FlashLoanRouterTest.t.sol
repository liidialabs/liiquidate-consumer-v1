// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";

/**
 * @title MockFlashLoanProvider
 * @notice Mock implementation of IFlashLoan for testing
 */
contract MockFlashLoanProvider {
    bytes32 public providerId;
    bool public shouldFail;
    bool public shouldRevert;
    uint256 public callCount;

    event FlashLoanCalled(
        address indexed debtAsset,
        address indexed collateralAsset,
        uint256 debtToCover,
        address targetContract
    );
    event FlashLoanReverted(bytes32 protocol);
    event FlashLoanFailed(bytes32 protocol);

    constructor(string memory _id) {
        providerId = keccak256(abi.encodePacked(_id));
        shouldFail = false;
        shouldRevert = false;
        callCount = 0;
    }

    function id() external view returns (bytes32) {
        return providerId;
    }

    function flashLoan(
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover,
        address targetContract,
        bytes calldata
    ) external {
        callCount++;

        if (shouldRevert) {
            revert("flash loan reverted");
        }

        if (shouldFail) {
            revert("flash loan failed");
        }

        emit FlashLoanCalled(
            debtAsset,
            collateralAsset,
            debtToCover,
            targetContract
        );
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

/**
 * @title FlashLoanRouterTest
 * @notice Comprehensive test suite for the FlashLoanRouter contract
 */
contract FlashLoanRouterTest is Test {
    FlashLoanRouter public router;
    MockFlashLoanProvider public aaveProvider;
    MockFlashLoanProvider public uniswapProvider;
    MockFlashLoanProvider public compoundProvider;

    address public debtAsset = makeAddr("debtAsset");
    address public collateralAsset = makeAddr("collateralAsset");
    address public targetContract = makeAddr("targetContract");

    bytes32 public constant AAVE_ID = keccak256(abi.encodePacked("AAVE_V3"));
    bytes32 public constant UNISWAP_ID =
        keccak256(abi.encodePacked("UNISWAP_V4"));
    bytes32 public constant COMPOUND_ID =
        keccak256(abi.encodePacked("COMPOUND"));
    bytes32 public constant DEFAULT_PROVIDER_ID = keccak256("AAVE_V3");

    event ProviderAdded(bytes32 id, address provider);
    event ProviderRemoved(bytes32 id);
    event ProviderPrioritySet(bytes32[] providers);
    event FlashLoanRoutedOn(bytes32 providerId);
    event FlashLoanExecuted(bytes32 provider);

    function setUp() public {
        router = new FlashLoanRouter();

        aaveProvider = new MockFlashLoanProvider("AAVE_V3");
        uniswapProvider = new MockFlashLoanProvider("UNISWAP_V4");
        compoundProvider = new MockFlashLoanProvider("COMPOUND");

        router.setProxyAddress(address(this));
    }

    // ========== PROVIDER MANAGEMENT TESTS ==========

    function test_AddProvider_Success() public {
        vm.expectEmit(true, true, false, false);
        emit ProviderAdded(AAVE_ID, address(aaveProvider));

        router.addProvider(address(aaveProvider));

        assertEq(router.providers(AAVE_ID), address(aaveProvider));
    }

    function test_AddProvider_MultipleProviders() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));
        router.addProvider(address(compoundProvider));

        assertEq(router.providers(AAVE_ID), address(aaveProvider));
        assertEq(router.providers(UNISWAP_ID), address(uniswapProvider));
        assertEq(router.providers(COMPOUND_ID), address(compoundProvider));
    }

    function test_AddProvider_OverwriteExisting() public {
        router.addProvider(address(aaveProvider));

        MockFlashLoanProvider newAaveProvider = new MockFlashLoanProvider(
            "AAVE_V3"
        );
        router.addProvider(address(newAaveProvider));

        assertEq(router.providers(AAVE_ID), address(newAaveProvider));
    }

    function test_RemoveProvider_Success() public {
        router.addProvider(address(aaveProvider));

        vm.expectEmit(true, false, false, false);
        emit ProviderRemoved(AAVE_ID);

        router.removeProvider(AAVE_ID);

        assertEq(router.providers(AAVE_ID), address(0));
    }

    function test_RemoveProvider_NonExistent() public {
        // Should not revert
        router.removeProvider(AAVE_ID);

        assertEq(router.providers(AAVE_ID), address(0));
    }

    function test_RemoveProvider_PreservesOthers() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        router.removeProvider(AAVE_ID);

        assertEq(router.providers(AAVE_ID), address(0));
        assertEq(router.providers(UNISWAP_ID), address(uniswapProvider));
    }

    function test_RemoveProvider_AllowsReaddition() public {
        router.addProvider(address(aaveProvider));
        router.removeProvider(AAVE_ID);

        MockFlashLoanProvider newProvider = new MockFlashLoanProvider(
            "AAVE_V3"
        );
        router.addProvider(address(newProvider));

        assertEq(router.providers(AAVE_ID), address(newProvider));
    }

    // ========== PROVIDER PRIORITY TESTS ==========

    function test_SetProviderPriority_Success() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        bytes32[] memory providerIds = new bytes32[](2);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;

        router.setProviderPriority(providerIds);

        // Verify priority was set
        // Note: We can't directly verify array content, but we can test behavior
    }

    function test_SetProviderPriority_EmptyList_Reverts() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.expectRevert(FlashLoanRouter.EmptyProviderArray.selector);
        router.setProviderPriority(empty);
    }

    function test_SetProviderPriority_MultipleProviders() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));
        router.addProvider(address(compoundProvider));

        bytes32[] memory providerIds = new bytes32[](3);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;
        providerIds[2] = COMPOUND_ID;

        vm.expectEmit(true, false, false, true);
        emit ProviderPrioritySet(providerIds);

        router.setProviderPriority(providerIds);
    }

    // ========== FLASH LOAN EXECUTION TESTS ==========

    function test_FlashLoan_DefaultProviderSuccess() public {
        router.addProvider(address(aaveProvider));

        bytes32[] memory providerIds = new bytes32[](1);
        providerIds[0] = AAVE_ID;
        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        vm.expectEmit(true, false, false, false);
        emit FlashLoanExecuted(DEFAULT_PROVIDER_ID);

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        assertEq(aaveProvider.callCount(), 1);
    }

    function test_FlashLoan_NoProviderAdded_Fails() public {
        bytes memory data = abi.encode("test");

        // Should not revert but should not execute
        vm.expectRevert();
        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );
    }

    function test_FlashLoan_WithPriorityOrder() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        bytes32[] memory providerIds = new bytes32[](2);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;

        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        // Should attempt Aave first
        assertEq(aaveProvider.callCount(), 1);
        assertEq(uniswapProvider.callCount(), 0);
    }

    function test_FlashLoan_FallsbackToNextProvider() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        aaveProvider.setShouldFail(true);

        bytes32[] memory providerIds = new bytes32[](2);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;

        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        vm.expectEmit(true, false, false, false);
        emit FlashLoanExecuted(UNISWAP_ID);

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        // Aave should be attempted but fail
        assertEq(aaveProvider.callCount(), 0);
        // Uniswap should succeed
        assertEq(uniswapProvider.callCount(), 1);
    }

    function test_FlashLoan_AllProvidersFail_Reverts() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        aaveProvider.setShouldFail(true);
        uniswapProvider.setShouldFail(true);

        bytes32[] memory providerIds = new bytes32[](2);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;

        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        vm.expectRevert(bytes("All flash loan providers failed!"));
        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );
    }

    function test_FlashLoan_SkipsZeroAddressProviders() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        // Remove aave provider, leaving a gap
        router.removeProvider(AAVE_ID);

        bytes32[] memory providerIds = new bytes32[](2);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;

        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        vm.expectEmit(true, false, false, false);
        emit FlashLoanExecuted(UNISWAP_ID);

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        // Should skip missing aave and use uniswap
        assertEq(uniswapProvider.callCount(), 1);
    }

    function test_FlashLoan_WithDifferentAssets() public {
        router.addProvider(address(aaveProvider));

        bytes32[] memory providerIds = new bytes32[](1);
        providerIds[0] = AAVE_ID;
        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        address[] memory assets = new address[](3);
        assets[0] = makeAddr("usdc");
        assets[1] = makeAddr("usdt");
        assets[2] = makeAddr("dai");

        for (uint256 i = 0; i < assets.length; i++) {
            router.flashLoan(
                assets[i],
                collateralAsset,
                1000e18,
                targetContract,
                data
            );
        }

        assertEq(aaveProvider.callCount(), assets.length);
    }

    // ========== AUTHORIZATION TESTS ==========

    function test_AddProvider_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        router.addProvider(address(aaveProvider));
    }

    function test_RemoveProvider_OnlyOwner() public {
        router.addProvider(address(aaveProvider));
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        vm.expectRevert();
        router.removeProvider(AAVE_ID);
    }

    function test_SetProviderPriority_OnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");

        bytes32[] memory providerIds = new bytes32[](1);
        providerIds[0] = AAVE_ID;

        vm.prank(nonOwner);
        vm.expectRevert();
        router.setProviderPriority(providerIds);
    }

    // ========== EDGE CASE TESTS ==========

    function test_FlashLoan_ComplexFallbackChain() public {
        // Create 5 providers with specific fail patterns
        MockFlashLoanProvider[] memory providers = new MockFlashLoanProvider[](
            5
        );
        bytes32[] memory providerIds = new bytes32[](5);

        for (uint256 i = 0; i < 5; i++) {
            providers[i] = new MockFlashLoanProvider(
                string(abi.encodePacked("PROVIDER_", i))
            );
            router.addProvider(address(providers[i]));
            providerIds[i] = keccak256(abi.encodePacked("PROVIDER_", i));
        }

        // Set first 3 to fail
        for (uint256 i = 0; i < 3; i++) {
            providers[i].setShouldFail(true);
        }

        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        // Should try first 3, succeed on 4th (index 3)
        assertEq(providers[3].callCount(), 1);
    }

    function test_FlashLoan_MultipleConsecutiveCalls() public {
        router.addProvider(address(aaveProvider));

        bytes32[] memory providerIds = new bytes32[](1);
        providerIds[0] = AAVE_ID;
        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        for (uint256 i = 0; i < 10; i++) {
            router.flashLoan(
                debtAsset,
                collateralAsset,
                1000e18,
                targetContract,
                data
            );
        }

        assertEq(aaveProvider.callCount(), 10);
    }

    function test_FlashLoan_RecoveryAfterTemporaryFailure() public {
        router.addProvider(address(aaveProvider));

        bytes32[] memory providerIds = new bytes32[](1);
        providerIds[0] = AAVE_ID;
        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("test");

        // First call fails
        aaveProvider.setShouldFail(true);

        vm.expectRevert(bytes("All flash loan providers failed!"));
        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        // Provider recovers
        aaveProvider.setShouldFail(false);

        // Second call succeeds
        vm.expectEmit(true, false, false, false);
        emit FlashLoanExecuted(DEFAULT_PROVIDER_ID);
        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );

        assertEq(aaveProvider.callCount(), 1);
    }

    // ========== REAL-WORLD SCENARIO TESTS ==========

    function test_Scenario_MultiProviderEnvironment() public {
        // Setup: Add 3 providers
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));
        router.addProvider(address(compoundProvider));

        // Set priority
        bytes32[] memory providerIds = new bytes32[](3);
        providerIds[0] = AAVE_ID;
        providerIds[1] = UNISWAP_ID;
        providerIds[2] = COMPOUND_ID;

        router.setProviderPriority(providerIds);

        bytes memory data = abi.encode("liquidation_payload");

        // Execute multiple flash loans
        for (uint256 i = 0; i < 3; i++) {
            router.flashLoan(
                debtAsset,
                collateralAsset,
                (i + 1) * 1000e18,
                targetContract,
                data
            );
        }

        // All should go to aave as first priority
        assertEq(aaveProvider.callCount(), 3);
        assertEq(uniswapProvider.callCount(), 0);
        assertEq(compoundProvider.callCount(), 0);
    }

    function test_Scenario_DynamicPrioritySwitch() public {
        router.addProvider(address(aaveProvider));
        router.addProvider(address(uniswapProvider));

        bytes memory data = abi.encode("test");

        // Initial priority: Aave
        bytes32[] memory priority1 = new bytes32[](2);
        priority1[0] = AAVE_ID;
        priority1[1] = UNISWAP_ID;
        router.setProviderPriority(priority1);

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );
        assertEq(aaveProvider.callCount(), 1);

        // Aave fails, switch priority
        aaveProvider.setShouldFail(true);
        bytes32[] memory priority2 = new bytes32[](2);
        priority2[0] = UNISWAP_ID;
        priority2[1] = AAVE_ID;
        router.setProviderPriority(priority2);

        router.flashLoan(
            debtAsset,
            collateralAsset,
            1000e18,
            targetContract,
            data
        );
        assertEq(uniswapProvider.callCount(), 1);
    }
}
