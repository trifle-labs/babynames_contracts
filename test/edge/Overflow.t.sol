// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract OverflowTest is TestHelpers {
    function test_LargeBuy() public {
        _createTestCategory();

        _fundUser(alice, 1000e6);
        // Buy large amounts spread across pools
        _buyAs(alice, 1, 250e6);
        _buyAs(alice, 2, 250e6);

        (, , uint256 totalSupply, uint256 collateral, uint256 price) = market.getPoolInfo(1);
        assertGt(totalSupply, 0);
        assertEq(collateral, 250 ether); // 250e6 USDC normalizes to 250e18
        assertGt(price, 0);
    }

    function test_ManySmallBuys() public {
        _createTestCategory();

        // Spread across pools to avoid pool-full
        for (uint256 i = 0; i < 25; i++) {
            address buyer = address(uint160(100 + i));
            _fundUser(buyer, 1e6);
            _buyAs(buyer, 1, 10_000);
            _buyAs(buyer, 2, 10_000);
        }

        (, , uint256 totalSupply, uint256 collateral, ) = market.getPoolInfo(1);
        assertGt(totalSupply, 0);
        assertEq(collateral, 0.25 ether); // 25 * 10_000 = 250_000 USDC -> 0.25e18
    }

    function test_LargeNumberOfPools() public {
        string[] memory names = new string[](20);
        for (uint256 i = 0; i < 20; i++) {
            names[i] = string(abi.encodePacked("Name", vm.toString(i)));
        }

        uint256 catId = market.createCategory(
            2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days
        );

        uint256[] memory poolIds = market.getCategoryPools(catId);
        assertEq(poolIds.length, 20);
    }

    function test_LargeBuyThenResolveAndClaim() public {
        _createTestCategory();

        _fundUser(alice, 1000e6);
        _fundUser(bob, 500e6);

        _buyAs(alice, 1, 800e6);
        _buyAs(bob, 2, 200e6);

        vm.prank(resolver);
        market.resolve(1, 1);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(1);

        uint256 payout = token.balanceOf(alice) - aliceBefore;
        assertApproxEqAbs(payout, 900e6, 1e3);
    }
}
