// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract ResolutionTest is TestHelpers {
    function test_Resolve() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        (, , , uint256 totalCollateral, , bool resolved, uint256 winningPoolId, uint256 prizePool, ) =
            market.getCategoryInfo(catId);

        assertTrue(resolved);
        assertEq(winningPoolId, 1);
        assertEq(totalCollateral, 8e18); // 8e6 native normalizes to 8e18
        assertEq(prizePool, 72e17);      // 90% of 8e18
        assertEq(market.treasury(), 8e17); // 10% of 8e18
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

        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 aliceBefore = token.balanceOf(alice);

        vm.prank(alice);
        market.claim(1);

        uint256 aliceAfter = token.balanceOf(alice);
        // Prize pool is 7.2 USDC (7_200_000 native units), allow small rounding
        assertApproxEqAbs(aliceAfter - aliceBefore, 7_200_000, 100);

        (, bool hasClaimed, ) = market.getUserPosition(1, alice);
        assertTrue(hasClaimed);
    }

    function test_Claim_ProportionalPayouts() public {
        uint256 catId = _createTestCategory();

        // Balanced bets across pools to avoid pool-full
        _buyAs(alice, 1, 1e6);
        _buyAs(carol, 2, 2e6);
        _buyAs(bob, 1, 500_000);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(alice);
        market.claim(1);
        vm.prank(bob);
        market.claim(1);

        uint256 aliceGain = token.balanceOf(alice) - aliceBefore;
        uint256 bobGain = token.balanceOf(bob) - bobBefore;

        // Alice bought more and earlier, should get more
        assertGt(aliceGain, bobGain);

        // Total payouts ~ prize pool (90% of 3.5 USDC = 3_150_000 native)
        uint256 expectedPrizePool = 3_500_000 * 9000 / 10000;
        assertApproxEqAbs(aliceGain + bobGain, expectedPrizePool, 100);
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
        _buyAs(alice, 1, 1e6);

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
        _buyAs(alice, 2, 1e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.NotWinningPool.selector);
        market.claim(2);
    }

    function test_RevertWhen_ClaimNotResolved() public {
        _createTestCategory();
        _buyAs(alice, 1, 1e6);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.CategoryNotResolved.selector);
        market.claim(1);
    }

    function test_RevertWhen_ClaimNoBalance() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 1e6);

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
