// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract BuyingTest is TestHelpers {
    function test_Buy() public {
        _createTestCategory();

        vm.prank(alice);
        market.buy(1, 1e6);

        (uint256 tokenBalance, , ) = market.getUserPosition(1, alice);
        // 1:1 pricing: 1e6 native = 1e18 normalized tokens
        assertEq(tokenBalance, 1e18);

        (, , , uint256 collateral, uint256 price) = market.getPoolInfo(1);
        assertEq(collateral, 1e18); // 1e6 native normalizes to 1e18
        assertEq(price, 1e18); // 1:1 pricing always $1
    }

    function test_BuyMultipleTimes() public {
        _createTestCategory();

        _buyAs(alice, 1, 500_000);
        _buyAs(bob, 1, 500_000);

        // 1:1 pricing: equal amounts = equal tokens
        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);
        (uint256 bobTokens, , ) = market.getUserPosition(1, bob);
        assertEq(aliceTokens, bobTokens);
    }

    function test_BuyUpdatesCollateral() public {
        _createTestCategory();

        _buyAs(alice, 1, 2e6);
        _buyAs(bob, 2, 1e6);

        (, , , , uint256 totalCollateral, , , , , , ) = market.getCategoryInfo(1);
        assertEq(totalCollateral, 3e18); // 3e6 native normalizes to 3e18
    }

    event TokensPurchased(uint256 indexed poolId, address indexed buyer, uint256 tokens, uint256 cost, uint256 avgPrice);

    function test_BuyEmitsEvent() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit TokensPurchased(1, alice, 1e18, 1e18, 1e18);
        market.buy(1, 1e6);
    }

    function test_RevertWhen_BuyInvalidPool() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InvalidPool.selector);
        market.buy(999, 1e6);
    }

    function test_RevertWhen_BuyBelowMinBet() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InsufficientBet.selector);
        market.buy(1, 100);
    }

    function test_RevertWhen_BuyZeroValue() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InsufficientBet.selector);
        market.buy(1, 0);
    }

    function test_RevertWhen_BettingClosed() public {
        _createTestCategory();

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.BettingClosed.selector);
        market.buy(1, 1e6);
    }

    function test_RevertWhen_BuyPaused() public {
        _createTestCategory();

        vm.prank(owner);
        market.pause();

        vm.prank(alice);
        vm.expectRevert();
        market.buy(1, 1e6);
    }

    function test_RevertWhen_BuyResolvedCategory() public {
        _createTestCategory();

        _buyAs(alice, 1, 1e6);

        vm.prank(resolver);
        market.resolve(1, 1);

        vm.prank(bob);
        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.buy(1, 1e6);
    }
}
