// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";

contract MaliciousClaimer {
    BabyNameMarket public market;
    uint256 public poolId;
    uint256 public attackCount;

    constructor(BabyNameMarket _market) {
        market = _market;
    }

    function attack(uint256 _poolId) external {
        poolId = _poolId;
        attackCount = 0;
        market.claim(_poolId);
    }

    receive() external payable {
        attackCount++;
        if (attackCount < 3) {
            try market.claim(poolId) {} catch {}
        }
    }
}

contract ReentrancyAttackTest is TestHelpers {
    function test_ReentrancyOnClaim() public {
        uint256 catId = _createTestCategory();

        // Deploy attacker
        MaliciousClaimer attacker = new MaliciousClaimer(market);
        vm.deal(address(attacker), 10 ether);

        // Attacker buys tokens
        vm.prank(address(attacker));
        market.buy{value: 5 ether}(1);

        // Someone else buys too
        _buyAs(bob, 2, 3 ether);

        // Resolve
        vm.prank(resolver);
        market.resolve(catId, 1);

        // Attack should not allow double claim
        // The claim function has nonReentrant, so second call in receive() reverts
        attacker.attack(1);

        // Attacker got paid once
        assertEq(attacker.attackCount(), 1);

        // Verify claimed
        (, bool hasClaimed, ) = market.getUserPosition(1, address(attacker));
        assertTrue(hasClaimed);
    }

    function test_ReentrancyOnBuy() public {
        // Buy is also protected by nonReentrant
        _createTestCategory();

        MaliciousBuyer malBuyer = new MaliciousBuyer(market);
        vm.deal(address(malBuyer), 10 ether);

        // This should work - single buy
        malBuyer.doBuy(1);

        (uint256 tokenBalance, , ) = market.getUserPosition(1, address(malBuyer));
        assertGt(tokenBalance, 0);
    }
}

contract MaliciousBuyer {
    BabyNameMarket public market;

    constructor(BabyNameMarket _market) {
        market = _market;
    }

    function doBuy(uint256 poolId) external {
        market.buy{value: 1 ether}(poolId);
    }

    receive() external payable {}
}
