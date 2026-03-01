// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract CurveMathFuzzTest is TestHelpers {
    function testFuzz_PriceBelowCeiling(uint256 amount) public {
        amount = bound(amount, 1_000, 100_000e6);

        _createTestCategory();

        _fundUser(alice, amount);
        _buyAs(alice, 1, amount);

        uint256 price = market.getCurrentPrice(1);
        assertLe(price, market.CEILING());
    }

    function testFuzz_TokensForAmountRoundTrip(uint256 amount) public {
        amount = bound(amount, 10_000, 100_000e6);

        _createTestCategory();

        uint256 tokens = market.calculateTokensForAmount(1, amount);
        assertGt(tokens, 0);

        // calculateBuyCost returns cost in 18-decimal normalized form
        uint256 cost = market.calculateBuyCost(1, tokens);
        // Normalize input amount to 18 decimals for comparison
        assertLe(cost, amount * 1e12);
    }

    function testFuzz_MonotonicallyIncreasingPrice(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 10_000, 10e6);
        a2 = bound(a2, 10_000, 10e6);

        _createTestCategory();

        // Give enough funds for all buys
        _fundUser(alice, 200e6);
        _fundUser(bob, 200e6);

        // Buy balanced across pools to avoid pool-full
        _buyAs(alice, 1, a1);
        _buyAs(alice, 2, a1);
        _buyAs(alice, 3, a1);
        uint256 price1 = market.getCurrentPrice(1);

        _buyAs(bob, 1, a2);
        _buyAs(bob, 2, a2);
        _buyAs(bob, 3, a2);
        uint256 price2 = market.getCurrentPrice(1);

        assertGe(price2, price1);
    }
}
