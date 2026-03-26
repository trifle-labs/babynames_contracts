// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract ViewFunctionsTest is TestHelpers {
    function test_GetExpectedRedemption_EmptyPool() public {
        _createTestCategory();
        uint256 redemption = market.getExpectedRedemption(1);
        assertEq(redemption, type(uint256).max);
    }

    function test_GetExpectedRedemption_WithBets() public {
        _createTestCategory();
        _buyAs(alice, 1, 1e6);
        _buyAs(bob, 2, 1e6);

        uint256 redemption = market.getExpectedRedemption(1);
        assertGt(redemption, 0);
    }

    function test_CanBuy_ValidPool() public {
        _createTestCategory();
        (bool canBuyNow, string memory reason) = market.canBuy(1);
        assertTrue(canBuyNow);
        assertEq(bytes(reason).length, 0);
    }

    function test_CanBuy_InvalidPool() public {
        (bool canBuyNow, string memory reason) = market.canBuy(999);
        assertFalse(canBuyNow);
        assertEq(reason, "Invalid pool");
    }

    function test_CanBuy_ResolvedCategory() public {
        uint256 catId = _createTestCategory();
        _buyAs(alice, 1, 1e6);

        vm.prank(resolver);
        market.resolve(catId, 1);

        (bool canBuyNow, string memory reason) = market.canBuy(1);
        assertFalse(canBuyNow);
        assertEq(reason, "Category resolved");
    }

    function test_CanBuy_BettingClosed() public {
        _createTestCategory();

        vm.warp(block.timestamp + 31 days);

        (bool canBuyNow, string memory reason) = market.canBuy(1);
        assertFalse(canBuyNow);
        assertEq(reason, "Betting closed");
    }

    function test_GetPoolInfo() public {
        _createTestCategory();
        _buyAs(alice, 1, 1e6);

        (uint256 catId, string memory name, uint256 totalSupply, uint256 collateral, uint256 price) =
            market.getPoolInfo(1);

        assertEq(catId, 1);
        assertEq(name, "Olivia");
        assertEq(totalSupply, 1e18); // 1:1 pricing
        assertEq(collateral, 1e18);
        assertEq(price, 1e18); // Always $1
    }

    function test_GetUserPosition_NonParticipant() public {
        _createTestCategory();

        (uint256 tokenBalance, bool hasClaimed, uint256 potentialPayout) =
            market.getUserPosition(1, alice);

        assertEq(tokenBalance, 0);
        assertFalse(hasClaimed);
        assertEq(potentialPayout, 0);
    }

    function test_GetUserPosition_WithTokens() public {
        _createTestCategory();
        _buyAs(alice, 1, 1e6);

        (uint256 tokenBalance, bool hasClaimed, uint256 potentialPayout) =
            market.getUserPosition(1, alice);

        assertEq(tokenBalance, 1e18); // 1:1 pricing
        assertFalse(hasClaimed);
        assertGt(potentialPayout, 0);
    }

    function test_GetCategoryPools_Empty() public {
        // Category 0 doesn't exist
        uint256[] memory pools = market.getCategoryPools(0);
        assertEq(pools.length, 0);
    }

    function test_GetCategoryInfo() public {
        uint256 catId = _createTestCategory();

        (
            uint256 year,
            uint256 position,
            ,
            BabyNameMarket.Gender gender,
            ,
            uint256 poolCount,
            bool resolved,
            ,
            ,
            uint256 deadline,
        ) = market.getCategoryInfo(catId);

        assertEq(year, 2025);
        assertEq(position, 1);
        assertEq(uint8(gender), uint8(BabyNameMarket.Gender.Female));
        assertEq(poolCount, 3);
        assertFalse(resolved);
        assertGt(deadline, block.timestamp);
    }

    function test_SimulateBuy() public {
        _createTestCategory();

        _buyAs(alice, 1, 1e6);
        _buyAs(bob, 2, 500_000);

        (uint256 tokens, uint256 avgPrice, uint256 expectedRedemption, ) =
            market.simulateBuy(1, 500_000);

        // 1:1 pricing
        assertEq(tokens, 5e17); // 500_000 * 1e12 = 5e17
        assertEq(avgPrice, 1e18); // Always $1
        assertGt(expectedRedemption, 0);
    }

    function test_SimulateBuy_Zero() public {
        _createTestCategory();

        (uint256 tokens, uint256 avgPrice, uint256 expectedRedemption, int256 profitIfWins) =
            market.simulateBuy(1, 0);

        assertEq(tokens, 0);
        assertEq(avgPrice, 0);
        assertEq(expectedRedemption, 0);
        assertEq(profitIfWins, 0);
    }
}
