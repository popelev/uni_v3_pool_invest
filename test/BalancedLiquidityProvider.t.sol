// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/BalancedLiquidityProvider.sol";
import "@uni-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./mocks/MockPositionManager.sol";

// PLEASE CHECK README FILE FOR START TESTS
//TODO: Improve logic of tests. Add slippedge for provided tokens

contract LiquidityProviderTest is Test {
    // POOL         |   ADDRESS                                     | RESULT|   COMMENT
    //--------------+-----------------------------------------------+-------+----------------------------
    // DAI/USDC     |   0x97e7d56A0408570bA1a7852De36350f7713906ec  | PASS  |
    // WBTC/USDC    |   0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35  | FAIL  |   FAIL REASON: ???
    // FRAX/USDC    |   0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52  | PASS  |
    // WBTC/cbBTC   |   0x0da6253560822973185297d5f32fF8fA38243Afe  | PASS  |
    // WBTC/WETH    |   0xCBCdF9626bC03E24f779434178A73a0B4bad62eD  | FAIL  |   FAIL REASON: ???
    // USDC/USDT    |   0x3416cF6C708Da44DB2624D63ea0AAef7113527C6  | FAIL  |   FAIL REASON: USDT not complite ERC20 ?
    // WETH/USDC    |   0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640  | PASS  |
    // LINK/WETH    |   0xa6Cc3C2531FdaA6Ae1A3CA84c2855806728693e8  | FAIL  |   FAIL REASON: ???
    //amphrLRT/wstETH|  0xBC048791147D8f89EF87F95b330b494cE3faFaD6  | FAIL  |   FAIL REASON: ???

    address pool = 0x97e7d56A0408570bA1a7852De36350f7713906ec;
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address manager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    BalancedLiquidityProvider public liquidityProvider;

    IERC20 public token0;
    IERC20 public token1;
    MockPositionManager public positionManager = MockPositionManager(manager);

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address public owner = address(this);
    address public user = address(0x123);
    uint256 mainnetFork;

    event LiquidityProvided();

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        // recive tokens
        token0 = IERC20(IUniswapV3Pool(pool).token0());
        token1 = IERC20(IUniswapV3Pool(pool).token1());

        // Mint some tokens for the owner to use
        deal(address(token0), user, 10000 ether);
        deal(address(token1), user, 10000 ether);

        // Deploy LiquidityProvider contract
        liquidityProvider = new BalancedLiquidityProvider(
            swapRouter,
            address(positionManager)
        );
    }

    function testProvideBalancedLiquidityBalancedTokens() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        vm.expectEmit(false, false, false, false);
        emit LiquidityProvided();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            100 * 10 ** decimals0,
            100 * 10 ** decimals1,
            currentTick - 100,
            currentTick + 100
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testProvideBalancedLiquidityToken0Excess() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            300 * 10 ** decimals0,
            100 * 10 ** decimals1,
            currentTick - 100,
            currentTick + 100
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testProvideBalancedLiquidityToken1Excess() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            100 * 10 ** decimals0,
            400 * 10 ** decimals1,
            currentTick - 100,
            currentTick + 100
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        // Additional assertions based on mock pool state
        vm.stopPrank();
    }

    function testProvideBalancedLiquidityWithoutToken0() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            0 * 10 ** decimals0,
            200 * 10 ** decimals1,
            currentTick - 100,
            currentTick + 100
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        vm.stopPrank();
    }
    function testProvideBalancedLiquidityWithoutToken1() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            200 * 10 ** decimals0,
            0 * 10 ** decimals1,
            currentTick - 100,
            currentTick + 100
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testProvideBalancedLiquidityBothTicksLower() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            100 * 10 ** decimals0,
            400 * 10 ** decimals1,
            currentTick - 2000,
            currentTick - 1000
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        vm.stopPrank();
    }

    function testProvideBalancedLiquidityBothTicksUpper() public {
        // User approves liquidity provider to use their tokens
        vm.startPrank(user);
        token0.approve(address(liquidityProvider), 50000 ether);
        token1.approve(address(liquidityProvider), 50000 ether);

        uint8 decimals0 = token0.decimals();
        uint8 decimals1 = token1.decimals();

        (, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();

        // Provide liquidity with balanced token amounts
        liquidityProvider.provideBalancedLiquidity(
            pool,
            100 * 10 ** decimals0,
            400 * 10 ** decimals1,
            currentTick + 1000,
            currentTick + 2000
        );

        // assertEq(token0.balanceOf(user), 0);
        // assertEq(token1.balanceOf(user), 0);

        vm.stopPrank();
    }
}
