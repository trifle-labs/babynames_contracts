// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract TopNResolutionTest is TestHelpers {
    uint256 catId;

    function setUp() public override {
        super.setUp();
        // Create a Top 3 category with 3 pools (poolIds 1, 2, 3)
        catId = _createTopNCategory(3);
    }

    function test_ResolveTopN_BasicFlow() public {
        _fundUser(alice, 100e6);
        _fundUser(bob, 100e6);
        _fundUser(carol, 100e6);

        _buyAs(alice, 1, 100e6);
        _buyAs(bob, 2, 100e6);
        _buyAs(carol, 3, 100e6);

        // Resolve: pools 1 and 2 win
        uint256[] memory winners = new uint256[](2);
        winners[0] = 1;
        winners[1] = 2;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        (, , , , , , bool resolved, , , , ) = market.getCategoryInfo(catId);
        assertTrue(resolved);

        // Both alice and bob can claim
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        uint256 alicePayout = token.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        market.claim(2);
        uint256 bobPayout = token.balanceOf(bob) - bobBefore;

        // Equal bets, equal tokens (1:1), equal payouts
        // Total collateral: 300e6, prize pool: 270e6 (10% rake)
        // Each winner gets ~135e6
        assertApproxEqAbs(alicePayout, 135e6, 1e3);
        assertApproxEqAbs(bobPayout, 135e6, 1e3);
    }

    function test_ResolveTopN_UnequalBets() public {
        _fundUser(alice, 10e6);
        _fundUser(bob, 10e6);
        _fundUser(carol, 10e6);

        // Alice buys pool 1 for 10, Dave also buys pool 1 for 10
        // Bob buys pool 2 for 10
        address dave = address(0xDA);
        _fundUser(dave, 10e6);

        _buyAs(carol, 3, 10e6);
        _buyAs(alice, 1, 10e6);
        _buyAs(dave, 1, 10e6);
        _buyAs(bob, 2, 10e6);

        // Pools 1 and 2 win
        uint256[] memory winners = new uint256[](2);
        winners[0] = 1;
        winners[1] = 2;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        // 1:1 pricing: alice and bob invested same amount from zero, get same tokens
        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);
        (uint256 bobTokens, , ) = market.getUserPosition(2, bob);
        assertEq(aliceTokens, bobTokens);

        // But pool 1 has 2x the supply (alice+dave), so per-token rate is diluted
        // Total: 40e6, prize pool: 36e6, winning supply: pool1(20e18) + pool2(10e18) = 30e18
        // Rate = 36e18 / 30e18 = 1.2e18
        // Alice: 10e18 * 1.2 = 12e6, Bob: 10e18 * 1.2 = 12e6
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        uint256 alicePayout = token.balanceOf(alice) - aliceBefore;

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        market.claim(2);
        uint256 bobPayout = token.balanceOf(bob) - bobBefore;

        // Both invested same and hold same tokens, so get same payout
        assertApproxEqAbs(alicePayout, bobPayout, 100);
        assertGt(alicePayout, 0);
        assertGt(bobPayout, 0);
    }

    function test_ResolveTopN_AllPoolsWin() public {
        _fundUser(alice, 100e6);
        _fundUser(bob, 100e6);
        _fundUser(carol, 100e6);

        _buyAs(alice, 1, 100e6);
        _buyAs(bob, 2, 100e6);
        _buyAs(carol, 3, 100e6);

        // All 3 pools win in a top-3 category
        uint256[] memory winners = new uint256[](3);
        winners[0] = 1;
        winners[1] = 2;
        winners[2] = 3;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        // Everyone should get back ~90% of their bet (10% rake)
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        assertApproxEqAbs(token.balanceOf(alice) - aliceBefore, 90e6, 1e3);

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        market.claim(2);
        assertApproxEqAbs(token.balanceOf(bob) - bobBefore, 90e6, 1e3);

        uint256 carolBefore = token.balanceOf(carol);
        vm.prank(carol);
        market.claim(3);
        assertApproxEqAbs(token.balanceOf(carol) - carolBefore, 90e6, 1e3);
    }

    function test_ResolveTopN_SingleWinner() public {
        _fundUser(alice, 100e6);
        _fundUser(bob, 100e6);

        _buyAs(alice, 1, 100e6);
        _buyAs(bob, 2, 100e6);

        // Only 1 pool wins (still valid for topN)
        uint256[] memory winners = new uint256[](1);
        winners[0] = 1;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        // Alice gets all the prize pool
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        assertApproxEqAbs(token.balanceOf(alice) - aliceBefore, 180e6, 1e3);
    }

    function test_ResolveTopN_GetWinningPoolIds() public {
        _fundUser(alice, 10e6);
        _buyAs(alice, 1, 10e6);

        uint256[] memory winners = new uint256[](2);
        winners[0] = 1;
        winners[1] = 2;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        uint256[] memory stored = market.getWinningPoolIds(catId);
        assertEq(stored.length, 2);
        assertEq(stored[0], 1);
        assertEq(stored[1], 2);
    }

    // ---- Revert tests ----

    function test_RevertWhen_ResolveTopN_NotTopN() public {
        _createTestCategory(); // catId 2, pools 4-6

        uint256[] memory winners = new uint256[](1);
        winners[0] = 4;

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.NotTopNCategory.selector);
        market.resolveTopN(2, winners);
    }

    function test_RevertWhen_ResolveTopN_PoolNotInCategory() public {
        _createTestCategory(); // catId 2, pools 4-6

        _fundUser(alice, 10e6);
        _buyAs(alice, 1, 10e6);

        uint256[] memory winners = new uint256[](1);
        winners[0] = 4;

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.PoolNotInCategory.selector);
        market.resolveTopN(catId, winners);
    }

    function test_RevertWhen_ResolveTopN_EmptyWinners() public {
        uint256[] memory winners = new uint256[](0);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.EmptyWinners.selector);
        market.resolveTopN(catId, winners);
    }

    function test_RevertWhen_ResolveTopN_DuplicateWinners() public {
        uint256[] memory winners = new uint256[](2);
        winners[0] = 1;
        winners[1] = 1;

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.DuplicateWinner.selector);
        market.resolveTopN(catId, winners);
    }

    function test_RevertWhen_ResolveTopN_TooManyWinners() public {
        string[] memory names = new string[](5);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";
        names[3] = "Sophia";
        names[4] = "Mia";

        uint256 bigCat = market.createCategory(
            2025, 3, 3, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs()
        );

        uint256[] memory poolIds = market.getCategoryPools(bigCat);

        uint256[] memory winners = new uint256[](4);
        winners[0] = poolIds[0];
        winners[1] = poolIds[1];
        winners[2] = poolIds[2];
        winners[3] = poolIds[3];

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.TooManyWinners.selector);
        market.resolveTopN(bigCat, winners);
    }

    function test_RevertWhen_ResolveTopN_AlreadyResolved() public {
        uint256[] memory winners = new uint256[](1);
        winners[0] = 1;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.resolveTopN(catId, winners);
    }

    function test_RevertWhen_ClaimLosingPool_TopN() public {
        _fundUser(alice, 100e6);
        _fundUser(bob, 100e6);

        _buyAs(alice, 1, 100e6);
        _buyAs(bob, 3, 100e6);

        uint256[] memory winners = new uint256[](1);
        winners[0] = 1;

        vm.prank(resolver);
        market.resolveTopN(catId, winners);

        vm.prank(bob);
        vm.expectRevert(BabyNameMarket.NotWinningPool.selector);
        market.claim(3);
    }

    function test_RevertWhen_UseResolveOnTopN() public {
        _fundUser(alice, 10e6);
        _buyAs(alice, 1, 10e6);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.NotSingleWinnerCategory.selector);
        market.resolve(catId, 1);
    }
}
