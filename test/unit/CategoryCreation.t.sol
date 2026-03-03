// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract CategoryCreationTest is TestHelpers {
    function test_CreateCategory() public {
        string[] memory names = new string[](3);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";

        uint256 deadline = block.timestamp + 30 days;

        uint256 categoryId = market.createCategory(
            2025, 1, 0, BabyNameMarket.Gender.Female, names, deadline, _emptyProofs()
        );

        assertEq(categoryId, 1);

        (
            uint256 year,
            uint256 position,
            uint8 categoryType,
            BabyNameMarket.Gender gender,
            uint256 totalCollateral,
            uint256 poolCount,
            bool resolved,
            ,
            ,
            uint256 catDeadline
        ) = market.getCategoryInfo(categoryId);

        assertEq(year, 2025);
        assertEq(position, 1);
        assertEq(categoryType, 0);
        assertEq(uint8(gender), uint8(BabyNameMarket.Gender.Female));
        assertEq(totalCollateral, 0);
        assertEq(poolCount, 3);
        assertFalse(resolved);
        assertEq(catDeadline, deadline);
    }

    event CategoryCreated(uint256 indexed categoryId, uint256 year, uint256 position, uint8 categoryType, BabyNameMarket.Gender gender, uint256 deadline);

    function test_CreateCategory_EmitsEvents() public {
        string[] memory names = _twoNames();

        vm.expectEmit(true, false, false, true);
        emit CategoryCreated(1, 2025, 5, 0, BabyNameMarket.Gender.Male, block.timestamp + 30 days);

        market.createCategory(2025, 5, 0, BabyNameMarket.Gender.Male, names, block.timestamp + 30 days, _emptyProofs());
    }

    function test_CreateCategory_PoolsCreated() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        assertEq(poolIds.length, 3);

        (, string memory name0, , , ) = market.getPoolInfo(poolIds[0]);
        (, string memory name1, , , ) = market.getPoolInfo(poolIds[1]);
        assertEq(name0, "Olivia");
        assertEq(name1, "Emma");
    }

    function test_CreateCategory_BoundaryPositions() public {
        string[] memory names = _twoNames();

        // Position 1 (min)
        uint256 cat1 = market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
        assertEq(cat1, 1);

        // Position 1000 (max)
        uint256 cat2 = market.createCategory(2025, 1000, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
        assertEq(cat2, 2);
    }

    function test_CreateCategory_TopN() public {
        uint256 catId = _createTopNCategory(10);

        (
            ,
            uint256 position,
            uint8 categoryType,
            ,
            ,
            uint256 poolCount,
            ,
            ,
            ,
        ) = market.getCategoryInfo(catId);

        assertEq(position, 10);
        assertEq(categoryType, 3); // CAT_TOP_N
        assertEq(poolCount, 3);
    }

    function test_AddNameToCategory() public {
        uint256 catId = _createTestCategory();

        uint256 poolId = market.addNameToCategory(catId, "Sophia", _emptyProof());

        uint256[] memory poolIds = market.getCategoryPools(catId);
        assertEq(poolIds.length, 4);
        (, string memory name, , , ) = market.getPoolInfo(poolId);
        assertEq(name, "Sophia");
    }

    function test_CreateCategory_OneName() public {
        string[] memory names = new string[](1);
        names[0] = "Olivia";

        uint256 catId = market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
        uint256[] memory poolIds = market.getCategoryPools(catId);
        assertEq(poolIds.length, 1);

        (, string memory name0, , , ) = market.getPoolInfo(poolIds[0]);
        assertEq(name0, "Olivia");
    }

    function test_RevertWhen_ZeroNames() public {
        string[] memory names = new string[](0);

        vm.expectRevert(BabyNameMarket.MinOneOption.selector);
        market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
    }

    function test_RevertWhen_InvalidPosition_Zero() public {
        string[] memory names = _twoNames();

        vm.expectRevert(BabyNameMarket.InvalidPosition.selector);
        market.createCategory(2025, 0, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
    }

    function test_RevertWhen_InvalidPosition_Above1000() public {
        string[] memory names = _twoNames();

        vm.expectRevert(BabyNameMarket.InvalidPosition.selector);
        market.createCategory(2025, 1001, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
    }

    function test_RevertWhen_InvalidCategoryType() public {
        string[] memory names = _twoNames();

        vm.expectRevert(BabyNameMarket.InvalidCategoryType.selector);
        market.createCategory(2025, 1, 4, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
    }

    function test_RevertWhen_InvalidDeadline() public {
        string[] memory names = _twoNames();

        vm.expectRevert(BabyNameMarket.InvalidDeadline.selector);
        market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Female, names, block.timestamp, _emptyProofs());
    }

    function test_RevertWhen_AddNamePostDeadline() public {
        uint256 catId = _createTestCategory();

        vm.warp(block.timestamp + 31 days);

        vm.expectRevert(BabyNameMarket.BettingClosed.selector);
        market.addNameToCategory(catId, "Sophia", _emptyProof());
    }

    function test_RevertWhen_AddNameInvalidCategory() public {
        vm.expectRevert(BabyNameMarket.InvalidCategory.selector);
        market.addNameToCategory(999, "Sophia", _emptyProof());
    }

    function test_RevertWhen_AddNameToResolvedCategory() public {
        uint256 catId = _createTestCategory();

        _buyAs(alice, 1, 1e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.addNameToCategory(catId, "Sophia", _emptyProof());
    }

    function test_RevertWhen_CreateCategoryPaused() public {
        vm.prank(owner);
        market.pause();

        string[] memory names = _twoNames();
        vm.expectRevert();
        market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days, _emptyProofs());
    }

    // ============ addNameAndBuy ============

    function test_AddNameAndBuy() public {
        uint256 catId = _createTestCategory();

        vm.prank(alice);
        uint256 poolId = market.addNameAndBuy(catId, "Sophia", _emptyProof(), 1e6);

        // Pool was created
        uint256[] memory poolIds = market.getCategoryPools(catId);
        assertEq(poolIds.length, 4);
        (, string memory name, , , ) = market.getPoolInfo(poolId);
        assertEq(name, "Sophia");

        // Bet was placed
        uint256 bal = market.balances(poolId, alice);
        assertGt(bal, 0);
    }

    function test_AddNameAndBuy_ZeroAmount() public {
        uint256 catId = _createTestCategory();

        vm.prank(alice);
        uint256 poolId = market.addNameAndBuy(catId, "Sophia", _emptyProof(), 0);

        // Pool was created but no bet
        (, string memory name, , , ) = market.getPoolInfo(poolId);
        assertEq(name, "Sophia");
        assertEq(market.balances(poolId, alice), 0);
    }

    function test_RevertWhen_AddNameAndBuy_InvalidCategory() public {
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InvalidCategory.selector);
        market.addNameAndBuy(999, "Sophia", _emptyProof(), 1e6);
    }

    function test_RevertWhen_AddNameAndBuy_Resolved() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 1e6);
        vm.prank(resolver);
        market.resolve(catId, 1);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.CategoryAlreadyResolved.selector);
        market.addNameAndBuy(catId, "Sophia", _emptyProof(), 1e6);
    }

    function test_RevertWhen_AddNameAndBuy_PostDeadline() public {
        uint256 catId = _createTestCategory();
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.BettingClosed.selector);
        market.addNameAndBuy(catId, "Sophia", _emptyProof(), 1e6);
    }
}
