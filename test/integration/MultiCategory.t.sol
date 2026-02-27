// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract MultiCategoryTest is TestHelpers {
    function test_ConcurrentCategories() public {
        uint256 cat1 = _createTestCategory();
        uint256 cat2 = _createTestCategoryMale();

        assertEq(cat1, 1);
        assertEq(cat2, 2);

        // Pools are isolated
        uint256[] memory pools1 = market.getCategoryPools(cat1);
        uint256[] memory pools2 = market.getCategoryPools(cat2);

        assertEq(pools1.length, 3);
        assertEq(pools2.length, 3);

        // Pool IDs: cat1 gets 1,2,3; cat2 gets 4,5,6
        assertEq(pools1[0], 1);
        assertEq(pools2[0], 4);
    }

    function test_PoolIdIsolation() public {
        _createTestCategory();
        _createTestCategoryMale();

        // Bet on both categories
        _buyAs(alice, 1, 1 ether);   // cat1 pool
        _buyAs(alice, 4, 1 ether);   // cat2 pool

        // Collateral is isolated per category
        (, , , uint256 total1, , , , , ) = market.getCategoryInfo(1);
        (, , , uint256 total2, , , , , ) = market.getCategoryInfo(2);

        assertEq(total1, 1 ether);
        assertEq(total2, 1 ether);
    }

    function test_ResolveOneNotOther() public {
        _createTestCategory();
        _createTestCategoryMale();

        _buyAs(alice, 1, 1 ether);
        _buyAs(bob, 4, 1 ether);

        // Resolve only category 1
        vm.prank(resolver);
        market.resolve(1, 1);

        (, , , , , bool resolved1, , , ) = market.getCategoryInfo(1);
        (, , , , , bool resolved2, , , ) = market.getCategoryInfo(2);

        assertTrue(resolved1);
        assertFalse(resolved2);

        // Can still buy in category 2
        _buyAs(carol, 5, 0.5 ether);
    }

    function test_MultipleCategoriesSequentialIds() public {
        for (uint256 i = 0; i < 5; i++) {
            string[] memory names = _twoNames();
            market.createCategory(2025, i + 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days);
        }

        assertEq(market.nextCategoryId(), 6);
        // 5 categories * 2 pools each = 10 pools + 1 (next)
        assertEq(market.nextPoolId(), 11);
    }
}
