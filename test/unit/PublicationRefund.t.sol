// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract PublicationRefundTest is TestHelpers {
    uint256 catId;

    function setUp() public override {
        super.setUp();
        vm.warp(1_700_000_000); // Set reasonable timestamp
        catId = _createTestCategory();
    }

    // ============ setPublicationTime (per year) ============

    function test_SetPublicationTime() public {
        uint256 pubTime = block.timestamp - 1 hours;

        vm.prank(resolver);
        market.setPublicationTime(2025, pubTime);

        assertEq(market.publicationTimes(2025), pubTime);

        (, , , , , , , , , , uint256 storedPubTime) = market.getCategoryInfo(catId);
        assertEq(storedPubTime, pubTime);
    }

    function test_SetPublicationTime_AppliesToAllCategoriesInYear() public {
        uint256 cat2 = _createTestCategoryMale(); // also year 2025

        uint256 pubTime = block.timestamp - 1 hours;
        vm.prank(resolver);
        market.setPublicationTime(2025, pubTime);

        (, , , , , , , , , , uint256 pub1) = market.getCategoryInfo(catId);
        (, , , , , , , , , , uint256 pub2) = market.getCategoryInfo(cat2);
        assertEq(pub1, pubTime);
        assertEq(pub2, pubTime);
    }

    function test_SetPublicationTime_EmitsEvent() public {
        uint256 pubTime = block.timestamp - 1 hours;

        vm.expectEmit(true, false, false, true);
        emit PublicationTimeSet(2025, pubTime);

        vm.prank(resolver);
        market.setPublicationTime(2025, pubTime);
    }

    function test_SetPublicationTime_DifferentYears() public {
        string[] memory names = _twoNames();
        market.createCategory(2024, 1, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);
        market.setPublicationTime(2024, block.timestamp - 2 hours);
        vm.stopPrank();

        assertEq(market.publicationTimes(2025), block.timestamp - 1 hours);
        assertEq(market.publicationTimes(2024), block.timestamp - 2 hours);
    }

    function test_RevertWhen_SetPublicationTime_NotResolver() public {
        vm.expectRevert(BabyNameMarket.NotResolver.selector);
        vm.prank(alice);
        market.setPublicationTime(2025, block.timestamp - 1 hours);
    }

    function test_RevertWhen_SetPublicationTime_AlreadySet() public {
        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        vm.expectRevert(BabyNameMarket.PublicationTimeAlreadySet.selector);
        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp - 2 hours);
    }

    function test_RevertWhen_SetPublicationTime_Zero() public {
        vm.expectRevert(BabyNameMarket.InvalidPublicationTime.selector);
        vm.prank(resolver);
        market.setPublicationTime(2025, 0);
    }

    function test_RevertWhen_SetPublicationTime_Future() public {
        vm.expectRevert(BabyNameMarket.InvalidPublicationTime.selector);
        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp + 1 hours);
    }

    // ============ refundInvalidBets ============

    function test_RefundInvalidBets_SingleUser() public {
        _buyAs(alice, 1, 5e6);

        // 1:1 pricing: tokens == collateral (normalized)
        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);
        assertEq(aliceTokens, 5e18);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory poolIds = new uint256[](1);
        address[] memory users = new address[](1);
        uint256[] memory tokenAmts = new uint256[](1);
        uint256[] memory collateralAmts = new uint256[](1);

        poolIds[0] = 1;
        users[0] = alice;
        tokenAmts[0] = aliceTokens;
        collateralAmts[0] = aliceTokens; // 1:1: tokens == collateral

        uint256 aliceBefore = token.balanceOf(alice);
        market.refundInvalidBets(catId, poolIds, users, tokenAmts, collateralAmts);
        vm.stopPrank();

        // Alice got refund
        assertEq(token.balanceOf(alice) - aliceBefore, 5e6);

        // Balance zeroed
        (uint256 remaining, , ) = market.getUserPosition(1, alice);
        assertEq(remaining, 0);

        // Pool and category collateral zeroed
        (, , uint256 newSupply, uint256 newCollateral, ) = market.getPoolInfo(1);
        assertEq(newSupply, 0);
        assertEq(newCollateral, 0);

        (, , , , uint256 totalCollateral, , , , , , ) = market.getCategoryInfo(catId);
        assertEq(totalCollateral, 0);
    }

    function test_RefundInvalidBets_PartialRefund() public {
        _buyAs(bob, 2, 3e6);
        _buyAs(carol, 3, 3e6);

        // Alice buys twice
        _buyAs(alice, 1, 3e6);
        (uint256 tokensAfterFirst, , ) = market.getUserPosition(1, alice);
        (, , , uint256 collateralAfterFirst, ) = market.getPoolInfo(1);

        _buyAs(alice, 1, 2e6);
        (uint256 tokensAfterSecond, , ) = market.getUserPosition(1, alice);
        (, , , uint256 collateralAfterSecond, ) = market.getPoolInfo(1);

        uint256 refundTokens = tokensAfterSecond - tokensAfterFirst;
        uint256 refundCollateral = collateralAfterSecond - collateralAfterFirst;
        // 1:1: refundTokens == refundCollateral
        assertEq(refundTokens, refundCollateral);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory poolIds = new uint256[](1);
        address[] memory users = new address[](1);
        uint256[] memory tokenAmts = new uint256[](1);
        uint256[] memory collateralAmts = new uint256[](1);

        poolIds[0] = 1;
        users[0] = alice;
        tokenAmts[0] = refundTokens;
        collateralAmts[0] = refundCollateral;

        market.refundInvalidBets(catId, poolIds, users, tokenAmts, collateralAmts);
        vm.stopPrank();

        // Alice still has first purchase tokens
        (uint256 remaining, , ) = market.getUserPosition(1, alice);
        assertEq(remaining, tokensAfterFirst);
    }

    function test_RefundInvalidBets_MultipleUsers() public {
        _buyAs(alice, 1, 3e6);
        _buyAs(bob, 2, 2e6);

        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);
        (uint256 bobTokens, , ) = market.getUserPosition(2, bob);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory poolIds = new uint256[](2);
        address[] memory users = new address[](2);
        uint256[] memory tokenAmts = new uint256[](2);
        uint256[] memory collateralAmts = new uint256[](2);

        poolIds[0] = 1;
        users[0] = alice;
        tokenAmts[0] = aliceTokens;
        collateralAmts[0] = aliceTokens; // 1:1

        poolIds[1] = 2;
        users[1] = bob;
        tokenAmts[1] = bobTokens;
        collateralAmts[1] = bobTokens; // 1:1

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        market.refundInvalidBets(catId, poolIds, users, tokenAmts, collateralAmts);
        vm.stopPrank();

        assertEq(token.balanceOf(alice) - aliceBefore, 3e6);
        assertEq(token.balanceOf(bob) - bobBefore, 2e6);
    }

    function test_RefundThenResolve() public {
        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);

        (uint256 bobTokens, , ) = market.getUserPosition(2, bob);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        // Refund Bob
        uint256[] memory poolIds = new uint256[](1);
        address[] memory users = new address[](1);
        uint256[] memory tokenAmts = new uint256[](1);
        uint256[] memory collateralAmts = new uint256[](1);

        poolIds[0] = 2;
        users[0] = bob;
        tokenAmts[0] = bobTokens;
        collateralAmts[0] = bobTokens; // 1:1

        market.refundInvalidBets(catId, poolIds, users, tokenAmts, collateralAmts);

        // Now resolve — only Alice's bet remains
        market.resolve(catId, 1);
        vm.stopPrank();

        // Alice claims — prize pool is 90% of 5e6 = 4.5e6
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        assertApproxEqAbs(token.balanceOf(alice) - aliceBefore, 4_500_000, 100);
    }

    function test_RefundInvalidBets_EmitsEvent() public {
        _buyAs(alice, 1, 5e6);

        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory poolIds = new uint256[](1);
        address[] memory users = new address[](1);
        uint256[] memory tokenAmts = new uint256[](1);
        uint256[] memory collateralAmts = new uint256[](1);

        poolIds[0] = 1;
        users[0] = alice;
        tokenAmts[0] = aliceTokens;
        collateralAmts[0] = aliceTokens; // 1:1

        vm.expectEmit(true, false, false, true);
        emit BetsRefunded(catId, aliceTokens, 1);

        market.refundInvalidBets(catId, poolIds, users, tokenAmts, collateralAmts);
        vm.stopPrank();
    }

    function test_RefundAcrossCategories_SameYear() public {
        uint256 cat2 = _createTestCategoryMale();

        _buyAs(alice, 1, 3e6);
        _buyAs(bob, 4, 2e6);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        _refundSingle(catId, 1, alice);
        _refundSingle(cat2, 4, bob);

        vm.stopPrank();

        (, , , , uint256 total1, , , , , , ) = market.getCategoryInfo(catId);
        assertEq(total1, 0);
        (, , , , uint256 total2, , , , , , ) = market.getCategoryInfo(cat2);
        assertEq(total2, 0);
    }

    function _refundSingle(uint256 _catId, uint256 poolId, address user) internal {
        (uint256 tokens, , ) = market.getUserPosition(poolId, user);

        uint256[] memory p = new uint256[](1);
        address[] memory u = new address[](1);
        uint256[] memory t = new uint256[](1);
        uint256[] memory c = new uint256[](1);
        p[0] = poolId; u[0] = user; t[0] = tokens; c[0] = tokens; // 1:1
        market.refundInvalidBets(_catId, p, u, t, c);
    }

    // ---- Revert tests ----

    function test_RevertWhen_RefundNotResolver() public {
        _buyAs(alice, 1, 1e6);

        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory p = new uint256[](0);
        address[] memory u = new address[](0);
        uint256[] memory t = new uint256[](0);
        uint256[] memory c = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.NotResolver.selector);
        market.refundInvalidBets(catId, p, u, t, c);
    }

    function test_RevertWhen_RefundInvalidCategory() public {
        uint256[] memory p = new uint256[](0);
        address[] memory u = new address[](0);
        uint256[] memory t = new uint256[](0);
        uint256[] memory c = new uint256[](0);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.InvalidCategory.selector);
        market.refundInvalidBets(999, p, u, t, c);
    }

    function test_RevertWhen_RefundResolved() public {
        _buyAs(alice, 1, 1e6);

        vm.startPrank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);
        market.resolve(catId, 1);
        vm.stopPrank();

        uint256[] memory p = new uint256[](0);
        address[] memory u = new address[](0);
        uint256[] memory t = new uint256[](0);
        uint256[] memory c = new uint256[](0);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.refundInvalidBets(catId, p, u, t, c);
    }

    function test_RevertWhen_RefundNoPublicationTime() public {
        uint256[] memory p = new uint256[](0);
        address[] memory u = new address[](0);
        uint256[] memory t = new uint256[](0);
        uint256[] memory c = new uint256[](0);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.PublicationTimeNotSet.selector);
        market.refundInvalidBets(catId, p, u, t, c);
    }

    function test_RevertWhen_RefundArrayLengthMismatch() public {
        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory p = new uint256[](1);
        address[] memory u = new address[](2);
        uint256[] memory t = new uint256[](1);
        uint256[] memory c = new uint256[](1);

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.ArrayLengthMismatch.selector);
        market.refundInvalidBets(catId, p, u, t, c);
    }

    function test_RevertWhen_RefundPoolNotInCategory() public {
        _createTestCategoryMale(); // catId 2, pools 4-6
        _buyAs(alice, 4, 1e6);

        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory p = new uint256[](1);
        address[] memory u = new address[](1);
        uint256[] memory t = new uint256[](1);
        uint256[] memory c = new uint256[](1);

        p[0] = 4; // belongs to catId 2
        u[0] = alice;
        t[0] = 1;
        c[0] = 1;

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.PoolNotInCategory.selector);
        market.refundInvalidBets(catId, p, u, t, c);
    }

    function test_RevertWhen_RefundExceedsBalance() public {
        _buyAs(alice, 1, 1e6);
        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);

        vm.prank(resolver);
        market.setPublicationTime(2025, block.timestamp - 1 hours);

        uint256[] memory p = new uint256[](1);
        address[] memory u = new address[](1);
        uint256[] memory t = new uint256[](1);
        uint256[] memory c = new uint256[](1);

        p[0] = 1;
        u[0] = alice;
        t[0] = aliceTokens + 1; // more than alice has
        c[0] = 1e18;

        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.RefundExceedsBalance.selector);
        market.refundInvalidBets(catId, p, u, t, c);
    }

    // ---- Events (declared for expectEmit) ----
    event PublicationTimeSet(uint256 indexed year, uint256 publicationTime);
    event BetsRefunded(uint256 indexed categoryId, uint256 totalRefunded, uint256 count);
}
