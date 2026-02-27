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
        _buyAs(alice, 1, 0.1 ether);
        _buyAs(alice, 2, 0.1 ether);
        uint256 price1 = market.getCurrentPrice(1);

        _buyAs(bob, 1, 0.1 ether);
        _buyAs(bob, 2, 0.1 ether);
        uint256 price2 = market.getCurrentPrice(1);

        assertGt(price1, 0);
        assertGt(price2, price1);
    }

    function test_PriceApproachesCeiling() public {
        _createTestCategory();

        // Large buys spread across pools to avoid pool-full
        vm.deal(alice, 2000 ether);
        _buyAs(alice, 1, 500 ether);
        _buyAs(alice, 2, 500 ether);

        uint256 price = market.getCurrentPrice(1);

        // Price should be positive and bounded by ceiling
        assertGt(price, 0);
        assertLe(price, market.CEILING());
    }

    function test_PriceBelowCeiling() public {
        _createTestCategory();

        vm.deal(alice, 2000 ether);
        _buyAs(alice, 1, 500 ether);
        _buyAs(alice, 2, 500 ether);

        uint256 price = market.getCurrentPrice(1);
        assertLe(price, market.CEILING());
    }

    function test_CalculateBuyCost_ZeroTokens() public {
        _createTestCategory();
        uint256 cost = market.calculateBuyCost(1, 0);
        assertEq(cost, 0);
    }

    function test_CalculateTokensForEth_ZeroEth() public {
        _createTestCategory();
        uint256 tokens = market.calculateTokensForEth(1, 0);
        assertEq(tokens, 0);
    }

    function test_CalculateTokensForEth_Consistency() public {
        _createTestCategory();

        uint256 tokens = market.calculateTokensForEth(1, 1 ether);
        assertGt(tokens, 0);

        uint256 cost = market.calculateBuyCost(1, tokens);
        // Cost should be close to 1 ether (binary search rounds down)
        assertLe(cost, 1 ether);
        assertGt(cost, 0.99 ether);
    }

    function test_SimulateBuy() public {
        _createTestCategory();

        _buyAs(alice, 1, 1 ether);
        _buyAs(bob, 2, 0.5 ether);

        (uint256 tokens, uint256 avgPrice, uint256 expectedRedemption, ) =
            market.simulateBuy(1, 0.5 ether);

        assertGt(tokens, 0);
        assertGt(avgPrice, 0);
        assertGt(expectedRedemption, 0);
    }

    function test_SimulateBuy_ZeroEth() public {
        _createTestCategory();

        (uint256 tokens, uint256 avgPrice, uint256 expectedRedemption, int256 profitIfWins) =
            market.simulateBuy(1, 0);

        assertEq(tokens, 0);
        assertEq(avgPrice, 0);
        assertEq(expectedRedemption, 0);
        assertEq(profitIfWins, 0);
    }
}
