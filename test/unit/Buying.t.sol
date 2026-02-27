// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract BuyingTest is TestHelpers {
    function test_Buy() public {
        _createTestCategory();

        vm.prank(alice);
        market.buy{value: 1 ether}(1);

        (uint256 tokenBalance, , ) = market.getUserPosition(1, alice);
        assertGt(tokenBalance, 0);

        (, , , uint256 collateral, uint256 price) = market.getPoolInfo(1);
        assertEq(collateral, 1 ether);
        assertGt(price, 0);
    }

    function test_BuyMultipleTimes() public {
        _createTestCategory();

        // Spread bets to avoid pool-full
        _buyAs(alice, 1, 0.5 ether);
        _buyAs(carol, 2, 0.5 ether);

        uint256 priceAfterAlice = market.getCurrentPrice(1);

        _buyAs(bob, 1, 0.5 ether);
        uint256 priceAfterBob = market.getCurrentPrice(1);

        // Price increases
        assertGt(priceAfterBob, priceAfterAlice);

        // Alice bought earlier (cheaper), should have more tokens
        (uint256 aliceTokens, , ) = market.getUserPosition(1, alice);
        (uint256 bobTokens, , ) = market.getUserPosition(1, bob);
        assertGt(aliceTokens, bobTokens);
    }

    function test_BuyUpdatesCollateral() public {
        _createTestCategory();

        _buyAs(alice, 1, 2 ether);
        _buyAs(bob, 2, 1 ether);

        (, , , uint256 totalCollateral, , , , , ) = market.getCategoryInfo(1);
        assertEq(totalCollateral, 3 ether);
    }

    event TokensPurchased(uint256 indexed poolId, address indexed buyer, uint256 tokens, uint256 cost, uint256 avgPrice);

    function test_BuyEmitsEvent() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit TokensPurchased(1, alice, 0, 0, 0);
        market.buy{value: 1 ether}(1);
    }

    function test_RevertWhen_BuyInvalidPool() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InvalidPool.selector);
        market.buy{value: 1 ether}(999);
    }

    function test_RevertWhen_BuyBelowMinBet() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InsufficientBet.selector);
        market.buy{value: 0.0001 ether}(1);
    }

    function test_RevertWhen_BuyZeroValue() public {
        _createTestCategory();

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InsufficientBet.selector);
        market.buy{value: 0}(1);
    }

    function test_RevertWhen_BettingClosed() public {
        _createTestCategory();

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.BettingClosed.selector);
        market.buy{value: 1 ether}(1);
    }

    function test_RevertWhen_BuyPaused() public {
        _createTestCategory();

        vm.prank(owner);
        market.pause();

        vm.prank(alice);
        vm.expectRevert();
        market.buy{value: 1 ether}(1);
    }

    function test_RevertWhen_BuyResolvedCategory() public {
        _createTestCategory();

        _buyAs(alice, 1, 1 ether);

        vm.prank(resolver);
        market.resolve(1, 1);

        vm.prank(bob);
        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.buy{value: 1 ether}(1);
    }
}
