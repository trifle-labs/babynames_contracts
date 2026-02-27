// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract ResolutionFuzzTest is TestHelpers {
    function testFuzz_PayoutsLessEqualCollateral(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 0.001 ether, 50 ether);
        a2 = bound(a2, 0.001 ether, 50 ether);

        _createTestCategory();

        vm.deal(alice, a1);
        vm.deal(bob, a2);

        _buyAs(alice, 1, a1);
        _buyAs(bob, 2, a2);

        vm.prank(resolver);
        market.resolve(1, 1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.claim(1);
        uint256 payout = alice.balance - aliceBefore;

        assertLe(payout, a1 + a2);

        uint256 prizePool = (a1 + a2) * 9000 / 10000;
        assertLe(payout, prizePool + 1);
    }

    function testFuzz_TwoWinnersShareFairly(uint256 a1, uint256 a2, uint256 loser) public {
        a1 = bound(a1, 0.01 ether, 5 ether);
        a2 = bound(a2, 0.01 ether, 5 ether);
        loser = bound(loser, 10 ether, 50 ether); // loser > winners to avoid pool-full

        _createTestCategory();

        vm.deal(alice, a1);
        vm.deal(bob, a2);
        vm.deal(carol, loser);

        _buyAs(alice, 1, a1);
        _buyAs(carol, 2, loser);
        _buyAs(bob, 1, a2);

        vm.prank(resolver);
        market.resolve(1, 1);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        market.claim(1);
        vm.prank(bob);
        market.claim(1);

        uint256 alicePayout = alice.balance - aliceBefore;
        uint256 bobPayout = bob.balance - bobBefore;

        uint256 totalPayout = alicePayout + bobPayout;
        uint256 prizePool = (a1 + a2 + loser) * 9000 / 10000;

        assertApproxEqAbs(totalPayout, prizePool, 1e12);
    }
}
