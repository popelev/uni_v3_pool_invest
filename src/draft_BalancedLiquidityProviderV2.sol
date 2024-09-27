// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";

import "@uni-v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uni-v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uni-v3-core/contracts/libraries/SqrtPriceMath.sol";
import "@uni-v3-core/contracts/libraries/TickMath.sol";

import "@uni-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uni-v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uni-v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract BalancedLiquidityProvider {
    ISwapRouter public swapRouter;
    INonfungiblePositionManager public positionManager;
    IUniswapV3Factory public factory;

    address public token0;
    address public token1;
    uint24 public poolFee;

    constructor(address _swapRouter, address _positionManager) {
        swapRouter = ISwapRouter(_swapRouter);
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function provideBalancedLiquidity(
        address _pool,
        uint256 X,
        uint256 Y,
        int24 tickLower,
        int24 tickUpper
    ) external {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        factory = IUniswapV3Factory(pool.factory());
        token0 = pool.token0();
        token1 = pool.token1();
        poolFee = pool.fee();

        uint256 balanceBefore0 = IERC20(token0).balanceOf(address(this));
        uint256 balanceBefore1 = IERC20(token1).balanceOf(address(this));

        // Transfer token0 and token1 to this contract
        IERC20(token0).transferFrom(msg.sender, address(this), X);
        IERC20(token1).transferFrom(msg.sender, address(this), Y);

        // Get the current price from the pool
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        console.log("price before swap");
        console.log(
            (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) / (1 << 96)
        );

        // Estimate virtual reserves
        uint128 poolLiquidity = pool.liquidity();
        (uint256 reserve0, uint256 reserve1) = getVirtualReserves(
            sqrtPriceX96,
            poolLiquidity
        );

        // Convert tickLower into sqrtPrice in Q96 format
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(tickLower); // PB = sqrt(PA)
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper); // PB = sqrt(PB)

        // Normalize amounts to a common base
        uint8 decimalsToken0 = IERC20(token0).decimals();
        uint8 decimalsToken1 = IERC20(token1).decimals();

        uint256 normalizedAmountToken0;
        uint256 normalizedAmountToken1;

        // // Normalize the token amounts to the same base by comparing the decimals
        // if (decimalsToken0 > decimalsToken1) {
        //     // Token0 has more decimals than Token1
        //     // Scale Token1 up to match Token0's decimals
        //     normalizedAmountToken0 = X; // No change to Token0 amount
        //     normalizedAmountToken1 =
        //         Y *
        //         (10 ** (decimalsToken0 - decimalsToken1)); // Scale Token1 up
        // } else if (decimalsToken0 < decimalsToken1) {
        //     // Token1 has more decimals than Token0
        //     // Scale Token0 up to match Token1's decimals
        //     normalizedAmountToken0 =
        //         X *
        //         (10 ** (decimalsToken1 - decimalsToken0)); // Scale Token0 up
        //     normalizedAmountToken1 = Y; // No change to Token1 amount
        // } else {
        //     // Both tokens have the same decimals
        normalizedAmountToken0 = X; // No change
        normalizedAmountToken1 = Y; // No change
        // }

        console.log("------liquidity For Token------");

        // console.log(liquidityForToken1);
        uint8 swapDirection = decideSwap(
            normalizedAmountToken0,
            normalizedAmountToken1,
            sqrtPriceX96,
            sqrtPriceLowerX96,
            sqrtPriceUpperX96
        );
        console.log("-----swapDirection-----");
        console.log(swapDirection);
        console.log("-----balace before swap-----");
        console.log(
            IERC20(token0).balanceOf(address(this)) /
                10 ** uint256(decimalsToken0)
        );
        console.log(
            IERC20(token1).balanceOf(address(this)) /
                10 ** uint256(decimalsToken1)
        );

        console.log("-------amountToSwap------");

        uint256 amountToSwap;
        // Determine if we need to swap tokens to balance the liquidity
        if (swapDirection == 1) {
            console.log("-------swap Token0 For Token1 ------");

            // Swap excess token0 for token1 to balance
            amountToSwap = calculateAmountToSwap(
                normalizedAmountToken0,
                normalizedAmountToken1,
                reserve0,
                reserve1,
                sqrtPriceX96,
                sqrtPriceLowerX96,
                sqrtPriceUpperX96,
                true
            );
            if (amountToSwap > 0) {
                swap(token0, token1, amountToSwap);
            }
            console.log(amountToSwap / 10 ** uint256(decimalsToken0));
        } else if (swapDirection == 2) {
            console.log("-------swap Token1 For Token0 ------");

            // Swap excess token1 for token0 to balance
            amountToSwap = calculateAmountToSwap(
                normalizedAmountToken0,
                normalizedAmountToken1,
                reserve0,
                reserve1,
                sqrtPriceX96,
                sqrtPriceLowerX96,
                sqrtPriceUpperX96,
                false
            );

            if (amountToSwap > 0) {
                swap(token1, token0, amountToSwap);
            }
            console.log(amountToSwap / 10 ** uint256(decimalsToken1));
        }
        console.log("------------");
        // Get the current price from the pool
        (uint160 sqrtPriceX962, , , , , , ) = pool.slot0();

        console.log("price before swap");
        console.log(
            (uint256(sqrtPriceX962) * uint256(sqrtPriceX962)) / (1 << 96)
        );

        console.log("-----balace after swap-----");
        console.log(
            IERC20(token0).balanceOf(address(this)) /
                10 ** uint256(decimalsToken0)
        );
        console.log(
            IERC20(token1).balanceOf(address(this)) /
                10 ** uint256(decimalsToken1)
        );

        uint256 balanceAfter0 = IERC20(token0).balanceOf(address(this));
        uint256 balanceAfter1 = IERC20(token1).balanceOf(address(this));

        uint256 readyLiquidity0 = balanceAfter0 - balanceBefore0;
        uint256 readyLiquidity1 = balanceAfter1 - balanceBefore1;

        console.log("-----ready Liquidity-----");
        console.log(readyLiquidity0 / 10 ** uint256(decimalsToken0));
        console.log(readyLiquidity1 / 10 ** uint256(decimalsToken1));

        // Approve the position manager to use tokens
        IERC20(token0).approve(address(positionManager), readyLiquidity0);
        IERC20(token1).approve(address(positionManager), readyLiquidity1);

        // Provide liquidity with the balanced token amounts
        INonfungiblePositionManager.MintParams
            memory mintParams = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: tickLower - (tickLower % 10),
                tickUpper: tickUpper - (tickUpper % 10),
                amount0Desired: readyLiquidity0,
                amount1Desired: readyLiquidity1,
                amount0Min: 0, //((readyLiquidity0 * 95) / 100),
                amount1Min: 0, //((readyLiquidity1 * 95) / 100),
                recipient: msg.sender,
                deadline: block.timestamp + 15 minutes
            });

        console.log("------------PARAMS------------");
        console.log(mintParams.token0);
        console.log(mintParams.token1);
        console.log(mintParams.fee);
        console.log(mintParams.tickLower - (tickLower % 10));
        console.log(mintParams.tickUpper - (tickUpper % 10));
        console.log(mintParams.amount0Desired);
        console.log(mintParams.amount1Desired);
        console.log(mintParams.amount0Min);
        console.log(mintParams.amount1Min);
        console.log(mintParams.recipient);
        console.log(mintParams.deadline);

        // Mint the position (provide liquidity)
        (
            uint256 _tokenId,
            uint128 liquidity,
            uint256 amount0Used,
            uint256 amount1Used
        ) = positionManager.mint(mintParams);

        console.log("----used------");
        console.log(amount0Used / 10 ** uint256(decimalsToken0));
        console.log(amount1Used / 10 ** uint256(decimalsToken1));
        console.log("-----balace after provide-----");
        console.log(
            IERC20(token0).balanceOf(address(this)) /
                10 ** uint256(decimalsToken0)
        );
        console.log(
            IERC20(token1).balanceOf(address(this)) /
                10 ** uint256(decimalsToken1)
        );
    }

    function calculateAmountToSwap(
        uint256 amountToken0, // Amount of token0
        uint256 amountToken1, // Amount of token1
        uint256 reserve0,
        uint256 reserve1,
        uint160 sqrtPriceX96, // Current square root price of the pool (Q96 format)
        uint256 sqrtPriceLowerX96, // Lower sqrt price
        uint256 sqrtPriceUpperX96, // Upper sqrt price
        bool swapFromToken0 // Whether we are swapping from token0 to token1
    ) internal pure returns (uint256 amountToSwap) {
        // Convert the square root prices to actual prices
        uint256 priceCurrent = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) /
            (1 << 96);
        uint256 priceLower = ((uint256(sqrtPriceLowerX96) *
            uint256(sqrtPriceLowerX96)) / (1 << 96));
        uint256 priceUpper = (uint256(sqrtPriceUpperX96) *
            uint256(sqrtPriceUpperX96)) / (1 << 96);

        console.log("-----prices-----");
        console.log(priceCurrent);
        console.log(priceLower);
        console.log(priceUpper);
        console.log("----------");
        bool needTwoTokens = priceUpper > priceCurrent &&
            priceCurrent > priceLower;
        console.log(needTwoTokens);
        console.log("----------");

        if (swapFromToken0) {
            if (needTwoTokens) {
                // Calculate the value of amountToken0 in terms of token1
                uint256 valueOfToken0InToken1 = (amountToken0 * priceCurrent);

                // Calculate the excess value of token0 compared to token1
                if (valueOfToken0InToken1 > amountToken1 * priceUpper) {
                    // Calculate the value difference in token1
                    uint256 valueDifference = valueOfToken0InToken1 -
                        (amountToken1 * priceUpper);

                    // Calculate the amount of token0 needed to be swapped to reduce valueDifference
                    amountToSwap = (valueDifference) / (priceCurrent) / 2;
                }
            } else {
                amountToSwap = amountToken0;
            }
        } else {
            if (needTwoTokens) {
                // Calculate the value of amountToken1 in terms of token0
                uint256 valueOfToken1InToken0 = (amountToken1 * priceLower);

                // Calculate the excess value of token1 compared to token0
                if (valueOfToken1InToken0 > amountToken0 * priceLower) {
                    // Calculate the value difference in token0
                    uint256 valueDifference = valueOfToken1InToken0 -
                        (amountToken0 * priceLower);

                    // Calculate the amount of token1 needed to be swapped to reduce valueDifference
                    amountToSwap = valueDifference / priceCurrent / 2;
                }
            } else {
                amountToSwap = amountToken1;
            }
        }
    }

    // Approve Uniswap Router to spend tokens
    function _approveTokenIfNeeded(address token, uint256 amount) internal {
        if (
            IERC20(token).allowance(address(this), address(swapRouter)) < amount
        ) {
            IERC20(token).approve(address(swapRouter), amount);
        }
    }

    // Swap token for token using Uniswap V3 Router
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountToSwap
    ) internal returns (uint256 amountReceived) {
        // Approve tokenIn for the router
        _approveTokenIfNeeded(tokenIn, amountToSwap);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn, // Input token (token0)
                tokenOut: tokenOut, // Output token (token1)
                fee: poolFee, // Uniswap pool fee tier
                recipient: address(this), // Contract receives the output tokens
                deadline: block.timestamp + 15, // Deadline for the swap (15 seconds from now)
                amountIn: amountToSwap, // Exact amount of tokenIn to swap
                amountOutMinimum: 0, // No minimum output amount (can be set for slippage control)
                sqrtPriceLimitX96: 0 // No price limit (can be set to control price impact)
            });

        // Execute the swap
        amountReceived = swapRouter.exactInputSingle(params);
    }

    function getVirtualReserves(
        uint160 sqrtPriceX96,
        uint128 liquidity
    ) internal pure returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = FullMath.mulDiv(
            liquidity << 96,
            sqrtPriceX96 - TickMath.MIN_SQRT_RATIO,
            sqrtPriceX96
        );
        reserve1 = FullMath.mulDiv(
            liquidity,
            sqrtPriceX96 - TickMath.MIN_SQRT_RATIO,
            1 << 96
        );
    }

    function estimatePriceImpactToken0(
        uint256 amountIn,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256 amountOut, uint256 newPrice) {
        uint256 amountInWithFee = (amountIn * 997) / 1000; // Assuming 0.3% fee
        uint256 numerator = amountInWithFee * reserve1;
        uint256 denominator = reserve0 + amountInWithFee;
        amountOut = numerator / denominator;
        newPrice =
            ((reserve1 - amountOut) * 1e18) /
            (reserve0 + amountInWithFee);
    }

    function estimatePriceImpactToken1(
        uint256 amountIn,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256 amountOut, uint256 newPrice) {
        uint256 amountInWithFee = (amountIn * 997) / 1000; // Assuming 0.3% fee
        uint256 numerator = amountInWithFee * reserve0;
        uint256 denominator = reserve1 + amountInWithFee;
        amountOut = numerator / denominator;
        newPrice =
            ((reserve1 + amountInWithFee) * 1e18) /
            (reserve0 - amountOut);
    }

    function calculateOptimalSwapAmount(
        uint256 amountToken0,
        uint256 amountToken1,
        uint256 reserve0,
        uint256 reserve1,
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96,
        bool swapFromToken0
    ) internal pure returns (uint256 optimalSwapAmount) {
        uint256 swapAmountMin = 0;
        uint256 swapAmountMax = swapFromToken0 ? amountToken0 : amountToken1;
        uint256 swapAmountMid;
        uint256 acceptableDifference = 1e18; // Adjust based on token decimals and desired precision

        while (swapAmountMax - swapAmountMin > acceptableDifference) {
            console.log("-------");
            console.log("swapAmountMax");
            console.log(swapAmountMax);
            console.log("swapAmountMin");
            console.log(swapAmountMin);
            console.log("delta");
            console.log(swapAmountMax - swapAmountMin);

            swapAmountMid = (swapAmountMin + swapAmountMax) / 2;

            console.log("swapAmountMid");
            console.log(swapAmountMid);

            uint256 amountOut;
            uint256 newPrice;

            if (swapFromToken0) {
                (amountOut, newPrice) = estimatePriceImpactToken0(
                    swapAmountMid,
                    reserve0,
                    reserve1
                );
            } else {
                (amountOut, newPrice) = estimatePriceImpactToken1(
                    swapAmountMid,
                    reserve0,
                    reserve1
                );
            }
            console.log("amountOut");
            console.log(amountOut);
            console.log("newPrice");
            console.log(newPrice);

            // Recalculate liquidity contributions using newPrice
            uint160 sqrtPriceAfterSwapX96 = uint160(
                Math.sqrt(newPrice * (1 << 192))
            );

            uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                sqrtPriceAfterSwapX96,
                sqrtPriceUpperX96,
                swapFromToken0
                    ? amountToken0 - swapAmountMid
                    : amountToken0 + amountOut
            );
            console.log("liquidity0");
            console.log(liquidity0);

            uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                sqrtPriceLowerX96,
                sqrtPriceAfterSwapX96,
                swapFromToken0
                    ? amountToken1 + amountOut
                    : amountToken1 - swapAmountMid
            );
            console.log("liquidity1");
            console.log(liquidity1);

            if (liquidity0 > liquidity1) {
                swapAmountMin = swapAmountMid;
            } else {
                swapAmountMax = swapAmountMid;
            }
        }

        optimalSwapAmount = swapAmountMid;
    }

    function calculateChangeInSqrtPriceAfterSwap(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne,
        uint24 feePips
    ) external pure returns (uint160 sqrtPriceNextX96) {
        require(sqrtPriceX96 > 0 && liquidity > 0, "Invalid inputs");

        // Adjust amountIn for fees
        uint256 feeAmount = FullMath.mulDiv(amountIn, feePips, 1e6);
        uint256 amountInLessFee = amountIn - feeAmount;

        // Calculate the next sqrtPriceX96
        sqrtPriceNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtPriceX96,
            liquidity,
            amountInLessFee,
            zeroForOne
        );
    }

    function getRequiredTokenRatio(
        uint256 amountToken0,
        uint256 amountToken1,
        uint160 sqrtPriceX96, // Current price in Q96 format
        uint160 sqrtPriceLowerX96, // Lower price in Q96 format
        uint160 sqrtPriceUpperX96 // Upper price in Q96 format
    ) public pure returns (uint256 requiredToken0, uint256 requiredToken1) {
        console.log("-----getRequiredTokenRatio-----");
        // Check if the current price is above the range
        if (sqrtPriceX96 > sqrtPriceUpperX96) {
            // Out of range, price is above the upper range
            // Only token1 is required, set requiredToken0 to 0
            requiredToken0 = 0;
            requiredToken1 = amountToken1; // You can provide all of token1
        }
        // Check if the current price is below the range
        else if (sqrtPriceX96 < sqrtPriceLowerX96) {
            // Out of range, price is below the lower range
            // Only token0 is required, set requiredToken1 to 0
            requiredToken0 = amountToken0; // You can provide all of token0
            requiredToken1 = 0;
        }
        // If the current price is within the range
        else {
            // Calculate required amounts for a balanced liquidity provision
            uint128 requiredLiquidityForToken0 = LiquidityAmounts
                .getLiquidityForAmount0(
                    sqrtPriceX96,
                    sqrtPriceUpperX96,
                    amountToken0
                );

            console.log(requiredLiquidityForToken0);

            uint128 requiredLiquidityForToken1 = LiquidityAmounts
                .getLiquidityForAmount1(
                    sqrtPriceX96,
                    sqrtPriceUpperX96,
                    amountToken1
                );
            console.log(requiredLiquidityForToken1);

            // Calculate the ideal amount of tokens required to match the liquidity
            requiredToken0 = LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceUpperX96,
                sqrtPriceX96,
                requiredLiquidityForToken1
            );
            console.log("-----Token0-----");
            console.log(amountToken0);
            console.log(requiredToken0);

            requiredToken1 = LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceX96,
                sqrtPriceLowerX96,
                requiredLiquidityForToken0
            );
            console.log("-----Token1-----");
            console.log(amountToken1);
            console.log(requiredToken1);
        }
        return (requiredToken0, requiredToken1);
    }

    // This is the function that uses getRequiredTokenRatio to decide which token to swap
    function decideSwap(
        uint256 amountToken0,
        uint256 amountToken1,
        uint160 sqrtPriceX96,
        uint160 sqrtPriceLowerX96,
        uint160 sqrtPriceUpperX96
    ) public pure returns (uint8) {
        // Get the required token amounts for balanced liquidity
        (
            uint256 requiredToken0,
            uint256 requiredToken1
        ) = getRequiredTokenRatio(
                amountToken0,
                amountToken1,
                sqrtPriceX96,
                sqrtPriceLowerX96,
                sqrtPriceUpperX96
            );

        // Determine which token needs to be swapped
        if (amountToken0 > requiredToken0) {
            return 1; //"Swap Token0 for Token1";
        } else if (amountToken1 > requiredToken1) {
            return 2; //"Swap Token1 for Token2";
        } else {
            return 0; //"Swap not need";
        }
    }
}
