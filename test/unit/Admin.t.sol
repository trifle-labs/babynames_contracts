// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract AdminTest is TestHelpers {
    function test_WithdrawTreasury() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 10e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        uint256 treasuryAmount = market.treasury();
        assertGt(treasuryAmount, 0);

        address recipient = address(99);
        vm.prank(owner);
        market.withdrawTreasury(recipient);

        assertEq(market.treasury(), 0);
        assertGt(token.balanceOf(recipient), 0);
    }

    function test_WithdrawTreasury_ZeroBalance() public {
        // Treasury is zero, should still work (sends 0)
        address recipient = address(99);
        vm.prank(owner);
        market.withdrawTreasury(recipient);

        assertEq(token.balanceOf(recipient), 0);
    }

    function test_SetResolver() public {
        address newResolver = address(42);

        vm.prank(owner);
        market.setResolver(newResolver);

        assertEq(market.resolver(), newResolver);
    }

    function test_Pause_Unpause() public {
        vm.prank(owner);
        market.pause();

        string[] memory names = _twoNames();
        vm.expectRevert();
        market.createCategory(2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days);

        vm.prank(owner);
        market.unpause();

        market.createCategory(2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days);
    }

    function test_RevertWhen_NonOwnerWithdrawTreasury() public {
        vm.prank(alice);
        vm.expectRevert();
        market.withdrawTreasury(alice);
    }

    function test_RevertWhen_NonOwnerSetResolver() public {
        vm.prank(alice);
        vm.expectRevert();
        market.setResolver(alice);
    }

    function test_RevertWhen_NonOwnerPause() public {
        vm.prank(alice);
        vm.expectRevert();
        market.pause();
    }

    function test_RevertWhen_NonOwnerUnpause() public {
        vm.prank(owner);
        market.pause();

        vm.prank(alice);
        vm.expectRevert();
        market.unpause();
    }
}
