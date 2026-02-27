// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/BabyNameMarket.sol";

abstract contract TestHelpers is Test {
    BabyNameMarket public market;

    address public owner = address(1);
    address public resolver = address(2);
    address public alice = address(3);
    address public bob = address(4);
    address public carol = address(5);

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_DEADLINE_OFFSET = 30 days;

    function setUp() public virtual {
        vm.prank(owner);
        market = new BabyNameMarket(resolver);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    function _createTestCategory() internal returns (uint256) {
        string[] memory names = new string[](3);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";

        return market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Female,
            names,
            block.timestamp + DEFAULT_DEADLINE_OFFSET
        );
    }

    function _createTestCategoryMale() internal returns (uint256) {
        string[] memory names = new string[](3);
        names[0] = "Liam";
        names[1] = "Noah";
        names[2] = "Oliver";

        return market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Male,
            names,
            block.timestamp + DEFAULT_DEADLINE_OFFSET
        );
    }

    function _twoNames() internal pure returns (string[] memory) {
        string[] memory names = new string[](2);
        names[0] = "NameA";
        names[1] = "NameB";
        return names;
    }

    function _buyAs(address user, uint256 poolId, uint256 amount) internal {
        vm.prank(user);
        market.buy{value: amount}(poolId);
    }
}
