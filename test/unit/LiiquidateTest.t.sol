// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Liiquidate} from "../../src/Liiquidate.sol";
import {AdapterRegistry} from "../../src/AdapterRegistry.sol";
import {FlashLoanRouter} from "../../src/FlashLoanRouter.sol";
import {
    ILiquidationAdapter
} from "../../src/interfaces/liquidationAdapter/ILiquidationAdapter.sol";
import {UniversalSwapRouter} from "../../src/UniversalSwapRouter.sol";
import {LiquidationParams} from "../../src/types/DataTypes.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolIdLibrary, PoolId } from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MIN_SQRT_PRICE} from "../../src/types/Constants.sol";
import {ISwapAdapter} from "../../src/interfaces/swapAdapter/ISwapAdapter.sol";
import {MockDebtManager} from "../mocks/MockDebtManager.sol";
import {MockDebtManagerAdapter} from "../mocks/MockDebtManagerAdapter.sol";
import {MockUniswapV4PoolManager} from "../mocks/MockUniswapV4PoolManager.sol";
import {MockChainlinkAutomationForwarder} from "../mocks/MockChainlinkAutomationForwarder.sol";
import {AaveV3} from "../../src/flashloans/AaveV3.sol";
import {UniswapV4} from "../../src/flashloans/UniswapV4.sol";
import {UniswapV4Adapter} from "../../src/swappers/UniswapV4Adapter.sol";
import {MockAaveV3Pool} from "../mocks/MockAaveV3Pool.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LiiquidateTest
 * @notice Comprehensive test suite for the Liiquidate contract
 */
contract LiiquidateTest is Test {
    using PoolIdLibrary for PoolKey;

    Liiquidate public liiquidate;
    AdapterRegistry public registry;
    FlashLoanRouter public flashRouter;
    UniversalSwapRouter public swapRouter;
    MockDebtManager public debtManager;
    MockDebtManagerAdapter public debtManagerAdapter;
    MockDebtManager public debtManager2;
    MockDebtManagerAdapter public debtManagerAdapter2;
    MockUniswapV4PoolManager public uniPoolManager;
    MockAaveV3Pool public aaveV3Pool;
    AaveV3 public aaveV3;
    UniswapV4 public uniswapV4;
    UniswapV4Adapter public swapAdapter;
    MockERC20 public debtToken;
    MockERC20 public collateralToken;
    MockChainlinkAutomationForwarder public chainLinkForwarder;

    address public user = address(0x1);
    address public user2 = address(0x2);
    address public liquidator = address(0x3);

    address public owner;
    address public workflowOwner;
    bytes32 public workflowId;
    bytes10 public workflowName;

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant POOL_FEE = 3000; // 0.5%
    uint256 constant DEBT_TO_COVER = 700e18;
    uint256 constant DEBT_TO_COVER2 = 700e18;

    event LiquidationExecuted(
        bytes32 indexed protocol,
        address indexed user,
        address indexed adapter,
        bool success
    );

    function setUp() public {
        owner = address(this);

        // Create tokens
        debtToken = new MockERC20("Debt Token", "DEBT", 18);
        collateralToken = new MockERC20("Collateral Token", "COLL", 18);

        ///////// CHAINLINK /////////

        chainLinkForwarder = new MockChainlinkAutomationForwarder();

        workflowId = keccak256("liquidation-workflow");
        workflowName = bytes10(keccak256("LiqBot"));
        workflowOwner = makeAddr("workflowOwner");

        chainLinkForwarder.createWorkflow(workflowId, workflowName, workflowOwner);

        ////////// AAVE V3 POOL ///////////

        aaveV3Pool = new MockAaveV3Pool();
        
        aaveV3Pool.setAssetSupported(address(debtToken), true);
        aaveV3Pool.setAssetReservement(address(debtToken), 1_000_000e18);
        debtToken.mint(address(aaveV3Pool), 1_000_000e18);

        aaveV3Pool.setAssetSupported(address(collateralToken), true);
        aaveV3Pool.setAssetReservement(address(collateralToken), INITIAL_BALANCE);
        collateralToken.mint(address(aaveV3Pool), INITIAL_BALANCE);

        //////// UNISWAP V4 POOL ///////////

        uniPoolManager = new MockUniswapV4PoolManager();

        /////////////// DEBTMANAGER ////////////////

        // Create mock debtManager & debtManagerAdapter
        debtManager = new MockDebtManager();
        debtManagerAdapter = new MockDebtManagerAdapter(
            address(debtManager),
            keccak256("DebtManager1")
        );

        // 
        debtToken.mint(address(debtManager), 1_000_000e18);
        collateralToken.mint(address(debtManager), 1_000_000e18);

        // Configure collateral
        // 10% liquidation bonus, 80% liquidation threshold
        debtManager.configureCollateral(
            address(collateralToken),
            0.1e18,  // 10% bonus for liquidators
            0.8e18   // 80% LTV threshold
        );
        
        // Configure debt asset
        debtManager.configureDebtAsset(
            address(debtToken),
            0.05e18,      // 5% annual rate
            1000000e18    // Max borrow
        );
        
        // Set initial prices
        // WETH = $2000, USDC = $1
        debtManager.setAssetPrice(address(collateralToken), 2000e8);
        debtManager.setAssetPrice(address(debtToken), 1e8);

        // Setup user account
        // User deposits 1 WETH ($2000) as collateral
        // User borrows 1200 USDC ($1200) - this is 60% LTV initially (healthy)
        debtManager.setupUserAccount(
            user,
            address(collateralToken),
            1e18,      // 1 WETH - collateral
            address(debtToken),
            1200e18    // 1200 USDC - debt
        );

        debtManager.setupUserAccount(
            user2,
            address(collateralToken),
            1e18,      // 1 WETH - collateral
            address(debtToken),
            1200e18    // 1200 USDC - debt
        );

        ///////// REGISTRY ////////

        registry = new AdapterRegistry();
        registry.registerAdapter(
            debtManagerAdapter.protocol(), 
            address(debtManagerAdapter)
        );

        ////// SWAP /////////

        // Create swap router
        swapRouter = new UniversalSwapRouter();

        // Create swap adapter
        swapAdapter = new UniswapV4Adapter(
            address(uniPoolManager)
        );

        // register adapter and add to priority queu
        swapRouter.registerAdapter(address(swapAdapter));

        bytes32[] memory protocols = new bytes32[](1);
        protocols[0] = swapAdapter.protocolId();
        swapRouter.setProtocolPriority(protocols);

        _createPoolKeys();

        ////// FLASH LOAN //////////

        // Create uniswap flash loan provide
        uniswapV4 = new UniswapV4(
            address(uniPoolManager),
            address(swapRouter)
        );

        // Create aave flash loan provider
        aaveV3 = new AaveV3(
            address(aaveV3Pool), 
            address(swapRouter)
        );

        // deploy router registry, add providers then set priority
        flashRouter = new FlashLoanRouter();

        flashRouter.addProvider(address(uniswapV4));
        flashRouter.addProvider(address(aaveV3));
        
        bytes32[] memory __protocols = new bytes32[](2);
        __protocols[0] = aaveV3.id();
        __protocols[1] = uniswapV4.id();

        flashRouter.setProviderPriority(__protocols);

        // Setup initial balances
        debtToken.mint(address(uniPoolManager), 1_000_000e18);
        collateralToken.mint(address(uniPoolManager), 1_000_000e18);

        /////// LIIQUIDATE /////////

        liiquidate = new Liiquidate(
            address(registry),
            address(flashRouter),
            address(chainLinkForwarder)
        );
    }

    // ========== HELPER ============

    function _createPoolKeys() internal {
        // 1. Setup token path
        address[] memory path = new address[](2);
        path[0] = address(collateralToken);
        path[1] = address(debtToken);

        // 2. Create PoolKey for the tokenA/tokenB pool
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(collateralToken)),
            currency1: Currency.wrap(address(debtToken)),
            fee: uint24(POOL_FEE),
            tickSpacing: 60,  // Adjust based on your fee tier
            hooks: IHooks(address(0))  // No hooks, or use your hooks address
        });

        // 3. Encode the PoolKey (not the pool manager address)
        bytes[] memory poolData = new bytes[](1);
        poolData[0] = abi.encode(poolKey);

        // 4. Setup fees array
        uint24[] memory fees = new uint24[](1);
        fees[0] = uint24(POOL_FEE);

        // 5. Initialize the pool in the mock (so sqrtPriceX96 != 0)
        uint160 sqrtPriceX96 = 2967187660000000000000000000000;
        uniPoolManager.initialize(
            poolKey,
            sqrtPriceX96,  // Or your desired initial price
            1000e18
        );

        // 6. Register the swap path
        swapAdapter.registerSwapPath(
            address(collateralToken),
            address(debtToken),
            path,
            poolData,
            fees
        );

        // 7. Get and verify the swap path
        ISwapAdapter.SwapPath memory swapPath = swapAdapter.getSwapPath(
            address(collateralToken),
            address(debtToken)
        );

        // Assertions
        assertEq(swapPath.tokens.length, 2, "Should have 2 tokens");
        assertEq(swapPath.poolData.length, 1, "Should have 1 pool");
        assertEq(swapPath.fees.length, 1, "Should have 1 fee");
        assertEq(swapPath.tokens[0], address(collateralToken), "First token should be tokenA");
        assertEq(swapPath.tokens[1], address(debtToken), "Second token should be tokenB");
        
        assertTrue(swapAdapter.isPathSupported(swapPath), "Path should be supported");        
    }

    function _liquidateUserGetPayload(address _user) 
    internal returns(ILiquidationAdapter.ExecutionPayload memory payload) {
        debtManager.setAssetPrice(address(collateralToken), 1400e8);
        debtManager.updateUserCollateral(_user, address(collateralToken), 1e18);

        payload  = debtManagerAdapter.buildExecutionPayload(
            _user, 
            DEBT_TO_COVER, 
            address(debtToken), 
            address(collateralToken)
        );
    }

    // ===========

    function testSuccessfulLiquidationSingle() public {
        ILiquidationAdapter.ExecutionPayload memory payload  = _liquidateUserGetPayload(user);
        
        Liiquidate.LiquidationReport[] memory jobs = 
            new Liiquidate.LiquidationReport[](1);
        
        jobs[0] = Liiquidate.LiquidationReport({
            protocol: debtManagerAdapter.protocol(),
            user: user,
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: DEBT_TO_COVER
        });
        
        bytes memory report = abi.encode(jobs);
        
        vm.expectEmit(true, true, true, false);
        emit LiquidationExecuted(
            jobs[0].protocol,
            jobs[0].user,
            address(debtManagerAdapter),
            true
        );

        uint256 balanceBefore = IERC20(debtToken).balanceOf(address(flashRouter));
        
        bool success = chainLinkForwarder.sendReport(
            address(liiquidate),
            workflowId,
            workflowName,
            report
        );

        uint256 balanceAfter = IERC20(debtToken).balanceOf(address(flashRouter));
        
        assertTrue(success);
        assertEq(balanceBefore, 0);
        assertGt(balanceAfter, 0);
    }

    function testSuccessfulLiquidationMultipleAccounts() public {
        ILiquidationAdapter.ExecutionPayload memory payload  = _liquidateUserGetPayload(user);
        ILiquidationAdapter.ExecutionPayload memory payload2  = _liquidateUserGetPayload(user2);
        
        Liiquidate.LiquidationReport[] memory jobs = 
            new Liiquidate.LiquidationReport[](2);
        
        jobs[0] = Liiquidate.LiquidationReport({
            protocol: debtManagerAdapter.protocol(),
            user: user,
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: DEBT_TO_COVER
        });
        jobs[1] = Liiquidate.LiquidationReport({
            protocol: debtManagerAdapter.protocol(),
            user: user2,
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: DEBT_TO_COVER
        });
        
        bytes memory report = abi.encode(jobs);
        
        vm.expectEmit(true, true, true, false);
        emit LiquidationExecuted(
            jobs[0].protocol,
            jobs[0].user,
            address(debtManagerAdapter),
            true
        );
        
        bool success = chainLinkForwarder.sendReport(
            address(liiquidate),
            workflowId,
            workflowName,
            report
        );
        
        assertTrue(success);
    }

    function testSuccessfulLiquidationMultipleAdapters() public {
        // Another adapter

        // Create mock debtManager & debtManagerAdapter
        debtManager2 = new MockDebtManager();
        debtManagerAdapter2 = new MockDebtManagerAdapter(
            address(debtManager2),
            keccak256("DebtManager2")
        );

        // 
        debtToken.mint(address(debtManager2), 1_000_000e18);
        collateralToken.mint(address(debtManager2), 1_000_000e18);

        // Configure collateral
        // 10% liquidation bonus, 80% liquidation threshold
        debtManager2.configureCollateral(
            address(collateralToken),
            0.1e18,  // 10% bonus for liquidators
            0.8e18   // 80% LTV threshold
        );
        
        // Configure debt asset
        debtManager2.configureDebtAsset(
            address(debtToken),
            0.05e18,      // 5% annual rate
            1000000e18    // Max borrow
        );
        
        // Set initial prices
        debtManager2.setAssetPrice(address(collateralToken), 2000e8);
        debtManager2.setAssetPrice(address(debtToken), 1e8);

        // Setup user account
        debtManager2.setupUserAccount(
            user2,
            address(collateralToken),
            1e18,      // 1 WETH - collateral
            address(debtToken),
            1200e18    // 1200 USDC - debt
        );

        // register
        registry.registerAdapter(
            debtManagerAdapter2.protocol(), 
            address(debtManagerAdapter2)
        );

        // make liquidatable
        debtManager2.setAssetPrice(address(collateralToken), 1400e8);
        debtManager2.updateUserCollateral(user2, address(collateralToken), 1e18);

        ILiquidationAdapter.ExecutionPayload memory _payload  = 
        debtManagerAdapter2.buildExecutionPayload(
            user2, 
            DEBT_TO_COVER, 
            address(debtToken), 
            address(collateralToken)
        );

        // cyrrent adapter

        ILiquidationAdapter.ExecutionPayload memory payload  = _liquidateUserGetPayload(user);
        
        Liiquidate.LiquidationReport[] memory jobs = 
            new Liiquidate.LiquidationReport[](2);
        
        jobs[0] = Liiquidate.LiquidationReport({
            protocol: debtManagerAdapter.protocol(),
            user: user,
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: DEBT_TO_COVER
        });
        jobs[1] = Liiquidate.LiquidationReport({
            protocol: debtManagerAdapter2.protocol(),
            user: user2,
            collateralAsset: address(collateralToken),
            debtAsset: address(debtToken),
            debtToCover: DEBT_TO_COVER
        });
        
        bytes memory report = abi.encode(jobs);
        
        vm.expectEmit(true, true, true, false);
        emit LiquidationExecuted(
            jobs[0].protocol,
            jobs[0].user,
            address(debtManagerAdapter),
            true
        );
        
        bool success = chainLinkForwarder.sendReport(
            address(liiquidate),
            workflowId,
            workflowName,
            report
        );
        
        assertTrue(success);
    }
}
