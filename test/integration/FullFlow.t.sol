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
        _buyAs(alice, 1, 1e6);
        _buyAs(carol, 2, 1_500_000);
        _buyAs(bob, 1, 500_000);
        _buyAs(alice, 3, 500_000);
        _buyAs(alice, 4, 500_000);

        (, , , uint256 total, , , , , ) = market.getCategoryInfo(catId);
        assertEq(total, 4 ether); // 4e6 USDC normalizes to 4e18

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

        assertGt(aliceGain, bobGain);
        assertApproxEqAbs(aliceGain + bobGain, 3_600_000, 1e3);
    }

    function test_FullFlow_TreasuryAccumulation() public {
        _createTestCategory();
        _createTestCategoryMale();

        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);
        _buyAs(carol, 4, 2e6);
        _buyAs(alice, 5, 1e6);

        vm.startPrank(resolver);
        market.resolve(1, 1);
        market.resolve(2, 4);
        vm.stopPrank();

        assertEq(market.treasury(), 1.1 ether); // 1.1e6 USDC normalizes to 1.1e18
    }

    function test_FullFlow_ClaimAfterTreasuryWithdraw() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 5e6);
        _buyAs(bob, 2, 3e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(owner);
        market.withdrawTreasury(owner);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);

        assertApproxEqAbs(token.balanceOf(alice) - aliceBefore, 7_200_000, 1e3);
    }
}
