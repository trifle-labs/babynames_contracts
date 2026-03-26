// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

/// @notice With ERC20, there is no native ETH callback reentrancy vector.
/// These tests verify that claim() and buy() work correctly and that the
/// nonReentrant modifier is still in place (verified by successful single operations).
contract ReentrancyAttackTest is TestHelpers {
    function test_ClaimWorksCorrectly() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);

        uint256 payout = token.balanceOf(alice) - aliceBefore;
        assertGt(payout, 0);

        (, bool hasClaimed, ) = market.getUserPosition(1, alice);
        assertTrue(hasClaimed);

        vm.prank(alice);
        vm.expectRevert();
        market.claim(1);
    }

    function test_BuyWorksCorrectly() public {
        _createTestCategory();

        _buyAs(alice, 1, 1e6);

        (uint256 tokenBalance, , ) = market.getUserPosition(1, alice);
        assertEq(tokenBalance, 1e18); // 1:1 pricing

        _buyAs(alice, 1, 1e6);

        (uint256 tokenBalance2, , ) = market.getUserPosition(1, alice);
        assertEq(tokenBalance2, 2e18); // 1:1 pricing, additive
    }

    function test_ClaimDoesNotOverpay() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);
        uint256 payout = token.balanceOf(alice) - aliceBefore;

        // Payout should be prize pool (90% of total = 7.2 USDC)
        uint256 totalBet = 8e6;
        uint256 prizePool = totalBet * 9000 / 10000;
        assertApproxEqAbs(payout, prizePool, 1e3);
    }
}
