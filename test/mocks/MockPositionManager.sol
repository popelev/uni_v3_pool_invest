// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPositionManager {
    event LiquidityProvided(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event LiquidityIncreased(
        uint128 addedLiquidity,
        uint256 amount0,
        uint256 amount1
    );

    function mint(
        address,
        address,
        uint24,
        int24,
        int24,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256,
        uint256,
        address,
        uint256
    )
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        tokenId = 1; // Example NFT id
        liquidity = uint128((amount0Desired + amount1Desired) / 2); // Simplified liquidity calculation
        amount0 = amount0Desired / 2;
        amount1 = amount1Desired / 2;

        emit LiquidityProvided(tokenId, liquidity, amount0, amount1);
    }

    function increaseLiquidity(
        uint256,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256,
        uint256,
        uint256
    )
        external
        returns (uint128 addedLiquidity, uint256 amount0, uint256 amount1)
    {
        addedLiquidity = uint128(amount0Desired + amount1Desired);
        amount0 = amount0Desired;
        amount1 = amount1Desired;

        emit LiquidityIncreased(addedLiquidity, amount0, amount1);
    }

    function getLiquidity(address) external pure returns (uint128) {
        return 100; // Mock liquidity
    }
}
