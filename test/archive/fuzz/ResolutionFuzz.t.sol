// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract ResolutionFuzzTest is TestHelpers {
    function testFuzz_PayoutsLessEqualCollateral(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 1_000, 50_000e6);
        a2 = bound(a2, 1_000, 50_000e6);

        _createTestCategory();

        _fundUser(alice, a1);
        _fundUser(bob, a2);

        _buyAs(alice, 1, a1);
        _buyAs(bob, 2, a2);

        vm.prank(resolver);
        market.resolve(1, 1);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        uint256 payout = token.balanceOf(alice) - aliceBefore;

        assertLe(payout, a1 + a2);

        uint256 prizePool = (a1 + a2) * 9000 / 10000;
        assertLe(payout, prizePool + 1);
    }

    function testFuzz_TwoWinnersShareFairly(uint256 a1, uint256 a2, uint256 loser) public {
        a1 = bound(a1, 10_000, 5e6);
        a2 = bound(a2, 10_000, 5e6);
        loser = bound(loser, 10e6, 50e6); // loser > winners to avoid pool-full

        _createTestCategory();

        _fundUser(alice, a1);
        _fundUser(bob, a2);
        _fundUser(carol, loser);

        _buyAs(alice, 1, a1);
        _buyAs(carol, 2, loser);
        _buyAs(bob, 1, a2);

        vm.prank(resolver);
        market.resolve(1, 1);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(alice);
        market.claim(1);
        vm.prank(bob);
        market.claim(1);

        uint256 alicePayout = token.balanceOf(alice) - aliceBefore;
        uint256 bobPayout = token.balanceOf(bob) - bobBefore;

        uint256 totalPayout = alicePayout + bobPayout;
        uint256 prizePool = (a1 + a2 + loser) * 9000 / 10000;

        assertApproxEqAbs(totalPayout, prizePool, 1e3);
    }
}
