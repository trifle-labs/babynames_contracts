// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract CurveMathFuzzTest is TestHelpers {
    function testFuzz_PriceBelowCeiling(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 500 ether);

        _createTestCategory();

        vm.deal(alice, amount);
        _buyAs(alice, 1, amount);

        uint256 price = market.getCurrentPrice(1);
        assertLe(price, market.CEILING());
    }

    function testFuzz_TokensForEthRoundTrip(uint256 amount) public {
        amount = bound(amount, 0.01 ether, 100 ether);

        _createTestCategory();

        uint256 tokens = market.calculateTokensForEth(1, amount);
        assertGt(tokens, 0);

        uint256 cost = market.calculateBuyCost(1, tokens);
        assertLe(cost, amount);
    }

    function testFuzz_MonotonicallyIncreasingPrice(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 0.01 ether, 10 ether);
        a2 = bound(a2, 0.01 ether, 10 ether);

        _createTestCategory();

        // Give enough funds for all buys
        vm.deal(alice, 200 ether);
        vm.deal(bob, 200 ether);

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
