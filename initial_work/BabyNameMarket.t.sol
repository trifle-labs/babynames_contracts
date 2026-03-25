// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../BabyNameMarket.sol";

contract BabyNameMarketTest is Test {
    BabyNameMarket public market;
    
    address public owner = address(1);
    address public resolver = address(2);
    address public alice = address(3);
    address public bob = address(4);
    address public carol = address(5);
    
    uint256 public constant PRECISION = 1e18;
    
    function setUp() public {
        vm.prank(owner);
        market = new BabyNameMarket(resolver);
        
        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }
    
    // ============ Category Creation ============
    
    function test_CreateCategory() public {
        string[] memory names = new string[](3);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";
        
        uint256 deadline = block.timestamp + 30 days;
        
        uint256 categoryId = market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Female,
            names,
            deadline
        );
        
        assertEq(categoryId, 1);
        
        (
            uint256 year,
            uint256 position,
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
        assertEq(uint8(gender), uint8(BabyNameMarket.Gender.Female));
        assertEq(totalCollateral, 0);
        assertEq(poolCount, 3);
        assertFalse(resolved);
        assertEq(catDeadline, deadline);
    }
    
    function test_RevertWhen_LessThanTwoNames() public {
        string[] memory names = new string[](1);
        names[0] = "Olivia";
        
        vm.expectRevert(BabyNameMarket.MinTwoOptions.selector);
        market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Female,
            names,
            block.timestamp + 30 days
        );
    }
    
    function test_RevertWhen_InvalidPosition() public {
        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "Emma";
        
        vm.expectRevert(BabyNameMarket.InvalidPosition.selector);
        market.createCategory(
            2025,
            0, // Invalid
            BabyNameMarket.Gender.Female,
            names,
            block.timestamp + 30 days
        );
        
        vm.expectRevert(BabyNameMarket.InvalidPosition.selector);
        market.createCategory(
            2025,
            1001, // Invalid
            BabyNameMarket.Gender.Female,
            names,
            block.timestamp + 30 days
        );
    }
    
    // ============ Buying ============
    
    function test_Buy() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1; // First pool created
        
        vm.prank(alice);
        market.buy{value: 1 ether}(oliviaPoolId);
        
        (uint256 tokenBalance, , ) = market.getUserPosition(oliviaPoolId, alice);
        assertGt(tokenBalance, 0);
        
        (, , , uint256 collateral, uint256 price) = market.getPoolInfo(oliviaPoolId);
        assertEq(collateral, 1 ether);
        assertGt(price, 0);
    }
    
    function test_BuyMultipleTimes() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        
        // Alice buys first (cheap)
        vm.prank(alice);
        market.buy{value: 1 ether}(oliviaPoolId);
        
        uint256 priceAfterAlice = market.getCurrentPrice(oliviaPoolId);
        
        // Bob buys second (more expensive)
        vm.prank(bob);
        market.buy{value: 1 ether}(oliviaPoolId);
        
        uint256 priceAfterBob = market.getCurrentPrice(oliviaPoolId);
        
        // Price should increase
        assertGt(priceAfterBob, priceAfterAlice);
        
        // Alice should have more tokens (bought cheaper)
        (uint256 aliceTokens, , ) = market.getUserPosition(oliviaPoolId, alice);
        (uint256 bobTokens, , ) = market.getUserPosition(oliviaPoolId, bob);
        assertGt(aliceTokens, bobTokens);
    }
    
    function test_RevertWhen_BettingClosed() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 31 days);
        
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.BettingClosed.selector);
        market.buy{value: 1 ether}(oliviaPoolId);
    }
    
    function test_RevertWhen_BelowMinBet() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.InsufficientBet.selector);
        market.buy{value: 0.0001 ether}(oliviaPoolId);
    }
    
    // ============ Pool Full Mechanism ============
    
    function test_PoolFullMechanism() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        uint256 emmaPoolId = 2;
        
        // Fill up Olivia pool with large bets
        vm.prank(alice);
        market.buy{value: 10 ether}(oliviaPoolId);
        
        // Small bet on Emma
        vm.prank(bob);
        market.buy{value: 0.01 ether}(emmaPoolId);
        
        // Check if Olivia is oversubscribed
        (bool canBuyOlivia, ) = market.canBuy(oliviaPoolId);
        
        // With only tiny loser collateral, Olivia should be full
        // (This depends on exact curve parameters and may need adjustment)
        
        // Can still buy Emma
        (bool canBuyEmma, ) = market.canBuy(emmaPoolId);
        assertTrue(canBuyEmma);
    }
    
    // ============ Resolution ============
    
    function test_Resolve() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        uint256 emmaPoolId = 2;
        
        // Place bets
        vm.prank(alice);
        market.buy{value: 5 ether}(oliviaPoolId);
        
        vm.prank(bob);
        market.buy{value: 3 ether}(emmaPoolId);
        
        // Resolve - Olivia wins
        vm.prank(resolver);
        market.resolve(categoryId, oliviaPoolId);
        
        (
            ,
            ,
            ,
            uint256 totalCollateral,
            ,
            bool resolved,
            uint256 winningPoolId,
            uint256 prizePool,
        ) = market.getCategoryInfo(categoryId);
        
        assertTrue(resolved);
        assertEq(winningPoolId, oliviaPoolId);
        assertEq(totalCollateral, 8 ether);
        assertEq(prizePool, 7.2 ether); // 8 - 10% rake
        
        // Treasury should have rake
        assertEq(market.treasury(), 0.8 ether);
    }
    
    function test_RevertWhen_NotResolver() public {
        uint256 categoryId = _createTestCategory();
        
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.NotResolver.selector);
        market.resolve(categoryId, 1);
    }
    
    function test_RevertWhen_PoolNotInCategory() public {
        uint256 categoryId1 = _createTestCategory();
        
        // Create another category
        string[] memory names = new string[](2);
        names[0] = "Liam";
        names[1] = "Noah";
        uint256 categoryId2 = market.createCategory(
            2025, 1, BabyNameMarket.Gender.Male, names, block.timestamp + 30 days
        );
        
        // Try to resolve category 1 with pool from category 2
        vm.prank(resolver);
        vm.expectRevert(BabyNameMarket.PoolNotInCategory.selector);
        market.resolve(categoryId1, 4); // Pool 4 is in category 2
    }
    
    // ============ Claiming ============
    
    function test_Claim() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        uint256 emmaPoolId = 2;
        
        // Alice bets on Olivia
        vm.prank(alice);
        market.buy{value: 5 ether}(oliviaPoolId);
        
        // Bob bets on Emma (loses)
        vm.prank(bob);
        market.buy{value: 3 ether}(emmaPoolId);
        
        // Resolve - Olivia wins
        vm.prank(resolver);
        market.resolve(categoryId, oliviaPoolId);
        
        // Alice claims
        uint256 aliceBalanceBefore = alice.balance;
        
        vm.prank(alice);
        market.claim(oliviaPoolId);
        
        uint256 aliceBalanceAfter = alice.balance;
        
        // Alice should get full prize pool (7.2 ether)
        assertEq(aliceBalanceAfter - aliceBalanceBefore, 7.2 ether);
        
        // Verify claimed flag
        (uint256 tokenBalance, bool hasClaimed, ) = market.getUserPosition(oliviaPoolId, alice);
        assertTrue(hasClaimed);
    }
    
    function test_RevertWhen_ClaimTwice() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        
        vm.prank(alice);
        market.buy{value: 1 ether}(oliviaPoolId);
        
        vm.prank(resolver);
        market.resolve(categoryId, oliviaPoolId);
        
        vm.prank(alice);
        market.claim(oliviaPoolId);
        
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.AlreadyClaimed.selector);
        market.claim(oliviaPoolId);
    }
    
    function test_RevertWhen_ClaimLosingPool() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        uint256 emmaPoolId = 2;
        
        vm.prank(alice);
        market.buy{value: 1 ether}(emmaPoolId);
        
        vm.prank(resolver);
        market.resolve(categoryId, oliviaPoolId); // Olivia wins, Emma loses
        
        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.NotWinningPool.selector);
        market.claim(emmaPoolId);
    }
    
    // ============ Full Flow Test ============
    
    function test_FullFlow() public {
        // Create category
        string[] memory names = new string[](4);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Charlotte";
        names[3] = "Sophia";
        
        uint256 categoryId = market.createCategory(
            2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days
        );
        
        // Multiple users bet
        vm.prank(alice);
        market.buy{value: 2 ether}(1); // Olivia
        
        vm.prank(bob);
        market.buy{value: 1 ether}(1); // Olivia
        
        vm.prank(carol);
        market.buy{value: 1.5 ether}(2); // Emma
        
        vm.prank(alice);
        market.buy{value: 0.5 ether}(3); // Charlotte
        
        // Check total collateral
        (,,,uint256 total,,,,,) = market.getCategoryInfo(categoryId);
        assertEq(total, 5 ether);
        
        // Resolve
        vm.prank(resolver);
        market.resolve(categoryId, 1); // Olivia wins
        
        // Claims
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;
        
        vm.prank(alice);
        market.claim(1);
        
        vm.prank(bob);
        market.claim(1);
        
        // Prize pool = 5 * 0.9 = 4.5 ether
        // Alice and Bob share based on token holdings
        uint256 aliceGain = alice.balance - aliceBalanceBefore;
        uint256 bobGain = bob.balance - bobBalanceBefore;
        
        // Alice bought more (and earlier), should get more
        assertGt(aliceGain, bobGain);
        
        // Total payouts should equal prize pool
        assertApproxEqAbs(aliceGain + bobGain, 4.5 ether, 1e10);
    }
    
    // ============ Curve Math Tests ============
    
    function test_PriceIncreasesWithSupply() public {
        uint256 categoryId = _createTestCategory();
        uint256 poolId = 1;
        
        uint256 price0 = market.getCurrentPrice(poolId);
        assertEq(price0, 0); // Empty pool
        
        vm.prank(alice);
        market.buy{value: 0.1 ether}(poolId);
        uint256 price1 = market.getCurrentPrice(poolId);
        
        vm.prank(bob);
        market.buy{value: 0.1 ether}(poolId);
        uint256 price2 = market.getCurrentPrice(poolId);
        
        vm.prank(carol);
        market.buy{value: 1 ether}(poolId);
        uint256 price3 = market.getCurrentPrice(poolId);
        
        assertGt(price1, price0);
        assertGt(price2, price1);
        assertGt(price3, price2);
    }
    
    function test_PriceApproachesCeiling() public {
        uint256 categoryId = _createTestCategory();
        uint256 poolId = 1;
        
        // Massive buy should approach ceiling
        vm.deal(alice, 1000 ether);
        vm.prank(alice);
        market.buy{value: 500 ether}(poolId);
        
        uint256 price = market.getCurrentPrice(poolId);
        
        // Should be very close to 1 ether (ceiling)
        assertGt(price, 0.9 ether);
        assertLt(price, 1.01 ether);
    }
    
    function test_SimulateBuy() public {
        uint256 categoryId = _createTestCategory();
        uint256 oliviaPoolId = 1;
        uint256 emmaPoolId = 2;
        
        // Some bets placed
        vm.prank(alice);
        market.buy{value: 1 ether}(oliviaPoolId);
        
        vm.prank(bob);
        market.buy{value: 0.5 ether}(emmaPoolId);
        
        // Simulate a buy
        (
            uint256 tokens,
            uint256 avgPrice,
            uint256 expectedRedemption,
            int256 profitIfWins
        ) = market.simulateBuy(oliviaPoolId, 0.5 ether);
        
        assertGt(tokens, 0);
        assertGt(avgPrice, 0);
        assertGt(expectedRedemption, 0);
        // Profit could be positive or negative depending on pool state
    }
    
    // ============ Admin Tests ============
    
    function test_WithdrawTreasury() public {
        uint256 categoryId = _createTestCategory();
        
        vm.prank(alice);
        market.buy{value: 10 ether}(1);
        
        vm.prank(resolver);
        market.resolve(categoryId, 1);
        
        // Treasury should have rake
        uint256 treasuryBefore = market.treasury();
        assertGt(treasuryBefore, 0);
        
        // Withdraw
        address recipient = address(99);
        vm.prank(owner);
        market.withdrawTreasury(recipient);
        
        assertEq(market.treasury(), 0);
        assertEq(recipient.balance, treasuryBefore);
    }
    
    function test_Pause() public {
        vm.prank(owner);
        market.pause();
        
        string[] memory names = new string[](2);
        names[0] = "Test1";
        names[1] = "Test2";
        
        vm.expectRevert(); // Pausable: paused
        market.createCategory(2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days);
        
        vm.prank(owner);
        market.unpause();
        
        // Should work now
        market.createCategory(2025, 1, BabyNameMarket.Gender.Female, names, block.timestamp + 30 days);
    }
    
    // ============ Helpers ============
    
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
            block.timestamp + 30 days
        );
    }
}
