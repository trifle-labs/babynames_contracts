// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract ResolutionTest is TestHelpers {
    function test_Resolve() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 5 ether);
        _buyAs(bob, 2, 3 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        (, , , uint256 totalCollateral, , bool resolved, uint256 winningPoolId, uint256 prizePool, ) =
            market.getCategoryInfo(catId);

        assertTrue(resolved);
        assertEq(winningPoolId, 1);
        assertEq(totalCollateral, 8 ether);
        assertEq(prizePool, 7.2 ether);
        assertEq(market.treasury(), 0.8 ether);
    }

    function test_Resolve_ZeroCollateral() public {
        uint256 catId = _createTestCategory();

        vm.prank(resolver);
        market.resolve(catId, 1);

        (, , , , , bool resolved, , uint256 prizePool, ) = market.getCategoryInfo(catId);
        assertTrue(resolved);
        assertEq(prizePool, 0);
        assertEq(market.treasury(), 0);
    }

    function test_Claim() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 5 ether);
        _buyAs(bob, 2, 3 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        market.claim(1);

        uint256 aliceAfter = alice.balance;
        // Prize pool is 7.2 ether, allow small rounding
        assertApproxEqAbs(aliceAfter - aliceBefore, 7.2 ether, 1e12);

        (, bool hasClaimed, ) = market.getUserPosition(1, alice);
        assertTrue(hasClaimed);
    }

    function test_Claim_ProportionalPayouts() public {
        uint256 catId = _createTestCategory();

        // Balanced bets across pools to avoid pool-full
        _buyAs(alice, 1, 1 ether);
        _buyAs(carol, 2, 2 ether);
        _buyAs(bob, 1, 0.5 ether);

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

        // Alice bought more and earlier, should get more
        assertGt(aliceGain, bobGain);

        // Total payouts ~ prize pool (90% of 3.5 ether)
        uint256 prizePool = 3.5 ether * 9000 / 10000;
        assertApproxEqAbs(aliceGain + bobGain, prizePool, 1e12);
    }

    function test_RevertWhen_NotResolver() public {
        uint256 catId = _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.NotResolver.selector);
        market.resolve(catId, 1);
    }

    function test_RevertWhen_ResolveInvalidCategory() public {
        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.InvalidCategory.selector);
        market.resolve(999, 1);
    }

    function test_RevertWhen_ResolveTwice() public {
        uint256 catId = _createTestCategory();

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.resolve(catId, 1);
    }

    function test_RevertWhen_PoolNotInCategory() public {
        _createTestCategory();
        _createTestCategoryMale();

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.PoolNotInCategory.selector);
        market.resolve(1, 4);
    }

    function test_RevertWhen_ClaimTwice() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 1 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(alice);
        market.claim(1);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.AlreadyClaimed.selector);
        market.claim(1);
    }

    function test_RevertWhen_ClaimLosingPool() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 2, 1 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.NotWinningPool.selector);
        market.claim(2);
    }

    function test_RevertWhen_ClaimNotResolved() public {
        _createTestCategory();
        _buyAs(alice, 1, 1 ether);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.CategoryNotResolved.selector);
        market.claim(1);
    }

    function test_RevertWhen_ClaimNoBalance() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 1 ether);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(bob);
        vm.expectRevert(BabyNameMarket.NoBalance.selector);
        market.claim(1);
    }

    function test_RevertWhen_ClaimInvalidPool() public {
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InvalidPool.selector);
        market.claim(999);
    }
}
