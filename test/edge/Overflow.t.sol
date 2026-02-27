// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract OverflowTest is TestHelpers {
    function test_LargeEthBuy() public {
        _createTestCategory();

        vm.deal(alice, 1000 ether);
        // Buy large amounts spread across pools
        _buyAs(alice, 1, 250 ether);
        _buyAs(alice, 2, 250 ether);

        (, , uint256 totalSupply, uint256 collateral, uint256 price) = market.getPoolInfo(1);
        assertGt(totalSupply, 0);
        assertEq(collateral, 250 ether);
        assertGt(price, 0);
    }

    function test_ManySmallBuys() public {
        _createTestCategory();

        // Spread across pools to avoid pool-full
        for (uint256 i = 0; i < 25; i++) {
            address buyer = address(uint160(100 + i));
            vm.deal(buyer, 1 ether);
            vm.prank(buyer);
            market.buy{value: 0.01 ether}(1);
            vm.prank(buyer);
            market.buy{value: 0.01 ether}(2);
        }

        (, , uint256 totalSupply, uint256 collateral, ) = market.getPoolInfo(1);
        assertGt(totalSupply, 0);
        assertEq(collateral, 0.25 ether);
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

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 500 ether);

        _buyAs(alice, 1, 800 ether);
        _buyAs(bob, 2, 200 ether);

        vm.prank(resolver);
        market.resolve(1, 1);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.claim(1);

        uint256 payout = alice.balance - aliceBefore;
        assertApproxEqAbs(payout, 900 ether, 1e12);
    }
}
