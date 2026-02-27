// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract BuyFuzzTest is TestHelpers {
    function testFuzz_BuyIncreasesSupply(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 100 ether);

        _createTestCategory();

        vm.deal(alice, amount);
        _buyAs(alice, 1, amount);

        (, , uint256 totalSupply, uint256 collateral, ) = market.getPoolInfo(1);
        assertGt(totalSupply, 0);
        assertEq(collateral, amount);
    }

    function testFuzz_BuyCollateralMatches(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 0.001 ether, 50 ether);
        amount2 = bound(amount2, 0.001 ether, 50 ether);

        _createTestCategory();

        vm.deal(alice, amount1);
        vm.deal(bob, amount2);

        // Buy into different pools to avoid pool-full
        _buyAs(alice, 1, amount1);
        _buyAs(bob, 2, amount2);

        (, , , uint256 totalCollateral, , , , , ) = market.getCategoryInfo(1);
        assertEq(totalCollateral, amount1 + amount2);
    }

    function testFuzz_MultiplePoolsBuys(uint256 a1, uint256 a2) public {
        a1 = bound(a1, 0.001 ether, 50 ether);
        a2 = bound(a2, 0.001 ether, 50 ether);

        _createTestCategory();

        vm.deal(alice, a1);
        vm.deal(bob, a2);

        _buyAs(alice, 1, a1);
        _buyAs(bob, 2, a2);

        (, , , uint256 totalCollateral, , , , , ) = market.getCategoryInfo(1);
        assertEq(totalCollateral, a1 + a2);
    }
}
