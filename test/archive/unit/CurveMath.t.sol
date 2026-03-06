// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract CurveMathTest is TestHelpers {
    function test_PriceStartsAtZero() public {
        _createTestCategory();
        uint256 price = market.getCurrentPrice(1);
        assertEq(price, 0);
    }

    function test_PriceIncreasesWithSupply() public {
        _createTestCategory();

        // Spread bets to avoid pool-full
        _buyAs(alice, 1, 100_000);
        _buyAs(alice, 2, 100_000);
        uint256 price1 = market.getCurrentPrice(1);

        _buyAs(bob, 1, 100_000);
        _buyAs(bob, 2, 100_000);
        uint256 price2 = market.getCurrentPrice(1);

        assertGt(price1, 0);
        assertGt(price2, price1);
    }

    function test_PriceApproachesCeiling() public {
        _createTestCategory();

        // Large buys spread across pools to avoid pool-full
        _fundUser(alice, 2000e6);
        _buyAs(alice, 1, 500e6);
        _buyAs(alice, 2, 500e6);

        uint256 price = market.getCurrentPrice(1);

        // Price should be positive and bounded by ceiling
        assertGt(price, 0);
        assertLe(price, market.CEILING());
    }

    function test_PriceBelowCeiling() public {
        _createTestCategory();

        _fundUser(alice, 2000e6);
        _buyAs(alice, 1, 500e6);
        _buyAs(alice, 2, 500e6);

        uint256 price = market.getCurrentPrice(1);
        assertLe(price, market.CEILING());
    }

    function test_CalculateBuyCost_ZeroTokens() public {
        _createTestCategory();
        uint256 cost = market.calculateBuyCost(1, 0);
        assertEq(cost, 0);
    }

    function test_CalculateTokensForAmount_Zero() public {
        _createTestCategory();
        uint256 tokens = market.calculateTokensForAmount(1, 0);
        assertEq(tokens, 0);
    }

    function test_CalculateTokensForAmount_Consistency() public {
        _createTestCategory();

        uint256 tokens = market.calculateTokensForAmount(1, 1e6);
        assertGt(tokens, 0);

        uint256 cost = market.calculateBuyCost(1, tokens);
        // Cost is normalized (1e18 precision), should be close to 1e18
        assertLe(cost, 1e18);
        assertGt(cost, 99e16);
    }

    function test_SimulateBuy() public {
        _createTestCategory();

        _buyAs(alice, 1, 1e6);
        _buyAs(bob, 2, 500_000);

        (uint256 tokens, uint256 avgPrice, uint256 expectedRedemption, ) =
            market.simulateBuy(1, 500_000);

        assertGt(tokens, 0);
        assertGt(avgPrice, 0);
        assertGt(expectedRedemption, 0);
    }

    function test_SimulateBuy_Zero() public {
        _createTestCategory();

        (uint256 tokens, uint256 avgPrice, uint256 expectedRedemption, int256 profitIfWins) =
            market.simulateBuy(1, 0);

        assertEq(tokens, 0);
        assertEq(avgPrice, 0);
        assertEq(expectedRedemption, 0);
        assertEq(profitIfWins, 0);
    }
}
