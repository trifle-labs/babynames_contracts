// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract FullFlowTest is TestHelpers {
    function test_FullFlow_MultiUser() public {
        string[] memory names = new string[](4);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";
        names[3] = "Sophia";

        uint256 catId = market.createCategory(
            2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days
        );

        // Balanced bets to avoid pool-full
        _buyAs(alice, 1, 1 ether);
        _buyAs(carol, 2, 1.5 ether);
        _buyAs(bob, 1, 0.5 ether);
        _buyAs(alice, 3, 0.5 ether);
        _buyAs(alice, 4, 0.5 ether);

        (, , , uint256 total, , , , , ) = market.getCategoryInfo(catId);
        assertEq(total, 4 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        market.claim(1);
        vm.prank(bob);
        market.claim(1);

        uint256 aliceGain = alice.balance - aliceBefore;
        uint256 bobGain = bob.balance - bobBefore;

        assertGt(aliceGain, bobGain);
        assertApproxEqAbs(aliceGain + bobGain, 3.6 ether, 1e12);
    }

    function test_FullFlow_TreasuryAccumulation() public {
        _createTestCategory();
        _createTestCategoryMale();

        _buyAs(alice, 1, 5 ether);
        _buyAs(bob, 2, 3 ether);
        _buyAs(carol, 4, 2 ether);
        _buyAs(alice, 5, 1 ether);

        vm.startPrank(resolver);
        market.resolve(1, 1);
        market.resolve(2, 4);
        vm.stopPrank();

        assertEq(market.treasury(), 1.1 ether);
    }

    function test_FullFlow_ClaimAfterTreasuryWithdraw() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 5 ether);
        _buyAs(bob, 2, 3 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(owner);
        market.withdrawTreasury(owner);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.claim(1);

        assertApproxEqAbs(alice.balance - aliceBefore, 7.2 ether, 1e12);
    }
}
