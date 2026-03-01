// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract BuyFuzzTest is TestHelpers {
    function testFuzz_BuyIncreasesSupply(uint256 amount) public {
        amount = bound(amount, 1_000, 100_000e6);

        _createTestCategory();

        _fundUser(alice, amount);
        _buyAs(alice, 1, amount);

        (, , uint256 totalSupply, uint256 collateral, ) = market.getPoolInfo(1);
        assertGt(totalSupply, 0);
        // Collateral is stored in 18-decimal normalized form
        assertEq(collateral, amount * 1e12);
    }

    function testFuzz_BuyCollateralMatches(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1_000, 50_000e6);
        amount2 = bound(amount2, 1_000, 50_000e6);

        _createTestCategory();

        _fundUser(alice, amount1);
        _fundUser(bob, amount2);

        // Buy into different pools to avoid pool-full
        _buyAs(alice, 1, amount1);
        _buyAs(bob, 2, amount2);

        (, , , uint256 totalCollateral, , , , , ) = market.getCategoryInfo(1);
        assertEq(totalCollateral, (amount1 + amount2) * 1e12);
    }

    function testFuzz_MultiplePoolsBuys(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 1_000, 50_000e6);
        a2 = bound(a2, 1_000, 50_000e6);

        _createTestCategory();

        _fundUser(alice, a1);
        _fundUser(bob, a2);

        _buyAs(alice, 1, a1);
        _buyAs(bob, 2, a2);

        (, , , uint256 totalCollateral, , , , , ) = market.getCategoryInfo(1);
        assertEq(totalCollateral, (a1 + a2) * 1e12);
    }
}
