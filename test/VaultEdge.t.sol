// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Vault} from "../src/Vault.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

contract TestUSDC2 is ERC20 {
    function name() public pure override returns (string memory) { return "Test USDC"; }
    function symbol() public pure override returns (string memory) { return "tUSDC"; }
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract VaultEdgeTest is Test {
    TestUSDC2 usdc;
    PredictionMarket pm;
    Vault vault;

    address oracle = address(0xBEEF);
    address treasury = address(0xCAFE);
    address feeSource = address(0xFEE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC4A7);
    address dave = address(0xDA7E);

    function setUp() public {
        usdc = new TestUSDC2();

        vm.startPrank(address(this), address(this));
        pm = new PredictionMarket();
        pm.initialize(address(usdc));
        pm.grantRoles(address(this), pm.PROTOCOL_MANAGER_ROLE());
        vm.stopPrank();
        pm.setMarketCreationFee(5e6);

        vault = new Vault(
            address(pm),
            treasury,        // surplusRecipient
            feeSource,       // feeSource
            oracle,          // defaultOracle
            20e6,            // defaultLaunchThreshold ($20)
            7 days,          // defaultDeadlineDuration
            address(this)    // owner
        );

        // Open the default year for proposals
        vault.openYear(2025);

        pm.grantMarketCreatorRole(address(vault));

        // Fund feeSource and approve vault from feeSource
        usdc.mint(feeSource, 10_000e6);
        vm.prank(feeSource);
        usdc.approve(address(vault), type(uint256).max);

        // Fund users
        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        usdc.mint(charlie, 100_000e6);
        usdc.mint(dave, 100_000e6);

        // Approve vault from users
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(dave);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ========== HELPERS ==========

    function _proposeAs(address user, string memory _name, uint16 year, uint256 yesAmt, uint256 noAmt)
        internal
        returns (bytes32 proposalId)
    {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = yesAmt;
        amounts[1] = noAmt;
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(user);
        proposalId = vault.propose(_name, year, proof, amounts);
    }

    function _commitAs(address user, bytes32 proposalId, uint256 yesAmt, uint256 noAmt) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = yesAmt;
        amounts[1] = noAmt;
        vm.prank(user);
        vault.commit(proposalId, amounts);
    }

    // ========== 1. DUST ACCOUNTING ==========

    /// @notice With mulDiv rounding down, sum of individual claimed shares may be less than
    ///         totalSharesPerOutcome, leaving dust permanently stuck in the vault.
    function test_dustAccounting_sumClaimedLeTotalShares() public {
        // Alice proposes with odd amount, bob and charlie commit odd amounts
        bytes32 proposalId = _proposeAs(alice, "Dusty", 2025, 7e6, 0);
        _commitAs(bob, proposalId, 13e6, 0);
        _commitAs(charlie, proposalId, 0, 11e6);

        // Total YES = 20e6, NO = 11e6, total = 31e6 >= threshold 20e6

        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        bytes32 marketId = info.marketId;
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(marketId);

        // Get total shares the vault actually holds (aggregate trade result)
        uint256 vaultYesBalance = IERC20(mInfo.outcomeTokens[0]).balanceOf(address(vault));
        uint256 vaultNoBalance = IERC20(mInfo.outcomeTokens[1]).balanceOf(address(vault));

        // All users claim shares
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);
        vm.prank(charlie);
        vault.claimShares(proposalId);

        // Sum up all users' claimed shares (now in their wallets)
        uint256 sumYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice)
            + IERC20(mInfo.outcomeTokens[0]).balanceOf(bob)
            + IERC20(mInfo.outcomeTokens[0]).balanceOf(charlie);
        uint256 sumNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice)
            + IERC20(mInfo.outcomeTokens[1]).balanceOf(bob)
            + IERC20(mInfo.outcomeTokens[1]).balanceOf(charlie);

        // mulDiv rounds down, so sum of individual allocations <= total shares held
        assertLe(sumYes, vaultYesBalance, "YES: sum of claimed > vault balance");
        assertLe(sumNo, vaultNoBalance, "NO: sum of claimed > vault balance");

        // Calculate dust
        uint256 dustYes = vaultYesBalance - sumYes;
        uint256 dustNo = vaultNoBalance - sumNo;

        console2.log("=== DUST ACCOUNTING ===");
        console2.log("Vault YES balance:", vaultYesBalance);
        console2.log("Sum claimed YES:  ", sumYes);
        console2.log("Dust YES:         ", dustYes);
        console2.log("Vault NO balance: ", vaultNoBalance);
        console2.log("Sum claimed NO:   ", sumNo);
        console2.log("Dust NO:          ", dustNo);

        // Dust is permanently stuck -- this is the rounding cost
        if (dustYes > 0 || dustNo > 0) {
            console2.log("WARNING: Dust detected -- tokens permanently stuck in vault");
        }
    }

    // ========== 2. TINY COMMITMENT ==========

    /// @notice A 1-wei commitment might get 0 shares but still have USDC locked.
    function test_tinyCommitment_oneWei() public {
        // Alice proposes with 1 wei to YES
        bytes32 proposalId = _proposeAs(alice, "Tiny", 2025, 1, 0);

        // Bob commits enough to meet threshold
        _commitAs(bob, proposalId, 20e6, 0);

        // Total = 20e6 + 1, YES = 20e6 + 1, NO = 0
        // Launch
        vault.launchMarket(proposalId);

        // Both users claim shares
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(info.marketId);

        uint256 aliceYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);
        uint256 bobYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(bob);
        uint256 bobNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(bob);

        console2.log("=== TINY COMMITMENT (1 wei) ===");
        console2.log("Alice YES shares:", aliceYes);
        console2.log("Alice NO shares: ", aliceNo);
        console2.log("Bob YES shares:  ", bobYes);
        console2.log("Bob NO shares:   ", bobNo);

        // Alice's refund
        uint256 aliceRefund = vault.pendingRefunds(alice);
        console2.log("Alice pending refund:", aliceRefund);

        // If Alice gets 0 shares AND 0 refund, her 1 wei is lost
        if (aliceYes == 0 && aliceNo == 0 && aliceRefund == 0) {
            console2.log("BUG: Alice's 1 wei is permanently stuck -- no shares, no refund");
        }
    }

    // ========== 3. BINARY SEARCH EXTREME ASYMMETRY ==========

    /// @notice Extreme ratio of YES/NO commitments might cause binary search issues.
    function test_binarySearch_extremeAsymmetry() public {
        // 19e6 YES, 1e6 NO (19:1 ratio)
        bytes32 proposalId = _proposeAs(alice, "Skewed", 2025, 19e6, 1e6);

        // Total = 20e6 = threshold
        vault.launchMarket(proposalId);

        // Alice claims shares
        vm.prank(alice);
        vault.claimShares(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(info.marketId);

        uint256 aliceYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);

        console2.log("=== EXTREME ASYMMETRY (19:1) ===");
        console2.log("Alice YES shares:", aliceYes);
        console2.log("Alice NO shares: ", aliceNo);

        // Both should be > 0 since she committed to both outcomes
        assertTrue(aliceYes > 0, "YES shares should be > 0");
        assertTrue(aliceNo > 0, "NO shares should be > 0");
    }

    // ========== 4. BINARY SEARCH UPPER BOUND ==========

    /// @notice If a user commits a very large amount, the binary search upper bound
    ///         of hi=2e6 might be too low, causing zero or minimal shares.
    function test_binarySearch_upperBoundSufficient() public {
        // Commit 500e6 to a single outcome -- the binary search hi=2e6 is a scaling
        // factor, not a share count, so let's see if it holds.
        bytes32 proposalId = _proposeAs(alice, "BigBet", 2025, 500e6, 0);

        // Need bob to also commit to meet minimum -- actually 500e6 >> 20e6 threshold
        // But NO side has 0 commits. Let's add some NO.
        _commitAs(bob, proposalId, 0, 1e6);

        // Total = 501e6
        vault.launchMarket(proposalId);

        // Both users claim shares
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(info.marketId);

        uint256 aliceYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 bobNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(bob);

        console2.log("=== BINARY SEARCH UPPER BOUND (500e6 commitment) ===");
        console2.log("Alice YES shares:", aliceYes);
        console2.log("Bob NO shares:   ", bobNo);

        // Key check: did we actually get meaningful shares?
        assertTrue(aliceYes > 0, "Alice should have YES shares");

        // How much was actually spent vs committed?
        uint256 aliceRefund = vault.pendingRefunds(alice);
        uint256 bobRefund = vault.pendingRefunds(bob);
        uint256 totalRefund = aliceRefund + bobRefund;
        uint256 actualCost = 501e6 - totalRefund;

        console2.log("Total committed:  ", uint256(501e6));
        console2.log("Actual cost:      ", actualCost);
        console2.log("Total refund:     ", totalRefund);
        console2.log("Utilization %:    ", actualCost * 100 / 501e6);

        // If utilization is very low (say < 50%), the binary search upper bound is
        // likely too restrictive
        if (actualCost * 100 / 501e6 < 50) {
            console2.log("WARNING: Low utilization suggests binary search upper bound (hi=2e6) is too low");
        }
    }

    // ========== 5. LAUNCH WITH EXACTLY THRESHOLD ==========

    function test_launchExactThreshold() public {
        // Alice proposes with exactly 20e6, meeting the threshold immediately
        bytes32 proposalId = _proposeAs(alice, "Exact", 2025, 10e6, 10e6);

        // Total committed = 20e6 = threshold
        Vault.ProposalInfo memory infoBefore = vault.getProposal(proposalId);
        assertEq(infoBefore.totalCommitted, 20e6);
        assertEq(infoBefore.launchThreshold, 20e6);

        // Launch should succeed
        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(uint256(info.state), uint256(Vault.ProposalState.LAUNCHED));
        assertTrue(info.marketId != bytes32(0));
        console2.log("=== LAUNCH EXACT THRESHOLD: SUCCESS ===");
    }

    // ========== 6. MULTIPLE ACTIVE PROPOSALS ==========

    function test_multipleActiveProposals() public {
        // Propose 3 different names
        bytes32 p1 = _proposeAs(alice, "Alpha", 2025, 10e6, 10e6);
        bytes32 p2 = _proposeAs(bob, "Bravo", 2025, 10e6, 10e6);
        bytes32 p3 = _proposeAs(charlie, "Cedar", 2025, 10e6, 10e6);

        // All three should be different
        assertTrue(p1 != p2, "p1 != p2");
        assertTrue(p2 != p3, "p2 != p3");
        assertTrue(p1 != p3, "p1 != p3");

        // Launch all 3
        vault.launchMarket(p1);
        vault.launchMarket(p2);
        vault.launchMarket(p3);

        Vault.ProposalInfo memory info1 = vault.getProposal(p1);
        Vault.ProposalInfo memory info2 = vault.getProposal(p2);
        Vault.ProposalInfo memory info3 = vault.getProposal(p3);

        assertEq(uint256(info1.state), uint256(Vault.ProposalState.LAUNCHED));
        assertEq(uint256(info2.state), uint256(Vault.ProposalState.LAUNCHED));
        assertEq(uint256(info3.state), uint256(Vault.ProposalState.LAUNCHED));

        // All should have different marketIds
        assertTrue(info1.marketId != info2.marketId, "market1 != market2");
        assertTrue(info2.marketId != info3.marketId, "market2 != market3");
        assertTrue(info1.marketId != info3.marketId, "market1 != market3");

        console2.log("=== MULTIPLE PROPOSALS: All 3 launched independently ===");
    }

    // ========== 7. REFUND ACCOUNTING ==========

    /// @notice Conservation of funds: sum of refunds + actualCost == totalCommitted
    function test_refundAccounting_sumsCorrectly() public {
        // 3 users with varying amounts
        bytes32 proposalId = _proposeAs(alice, "Refundy", 2025, 7e6, 3e6);
        _commitAs(bob, proposalId, 4e6, 8e6);
        _commitAs(charlie, proposalId, 2e6, 6e6);

        // Total = 10+12+8 = 30e6
        uint256 totalCommitted = 30e6;

        vault.launchMarket(proposalId);

        // All users must claim shares to get refunds credited
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);
        vm.prank(charlie);
        vault.claimShares(proposalId);

        // Sum pending refunds
        uint256 aliceRefund = vault.pendingRefunds(alice);
        uint256 bobRefund = vault.pendingRefunds(bob);
        uint256 charlieRefund = vault.pendingRefunds(charlie);
        uint256 totalRefunds = aliceRefund + bobRefund + charlieRefund;

        uint256 vaultBalAfter = usdc.balanceOf(address(vault));

        console2.log("=== REFUND ACCOUNTING ===");
        console2.log("Total committed:  ", totalCommitted);
        console2.log("Alice refund:     ", aliceRefund);
        console2.log("Bob refund:       ", bobRefund);
        console2.log("Charlie refund:   ", charlieRefund);
        console2.log("Total refunds:    ", totalRefunds);
        console2.log("Vault bal after:  ", vaultBalAfter);

        // Vault balance after launch should be enough to pay all refunds
        assertGe(
            vaultBalAfter,
            totalRefunds,
            "BUG: Vault cannot pay all pending refunds"
        );

        // Conservation: refunds should not exceed what was unspent
        assertLe(totalRefunds, totalCommitted, "Refunds exceed total committed");
    }

    // ========== 8. PROPOSE AFTER LAUNCH (NAME REUSE) ==========

    /// @notice BUG FOUND: Re-proposing the same name+year+region after launch hits DuplicateMarketKey
    ///         because the duplicate check now blocks both OPEN and LAUNCHED proposals.
    function test_proposeAfterLaunch_sameNameBlocked() public {
        // Propose and launch "Olivia" for 2025
        bytes32 proposalId1 = _proposeAs(alice, "Olivia", 2025, 10e6, 10e6);
        vault.launchMarket(proposalId1);

        Vault.ProposalInfo memory info1 = vault.getProposal(proposalId1);
        assertEq(uint256(info1.state), uint256(Vault.ProposalState.LAUNCHED));

        // Same name+year+region should revert with DuplicateMarketKey (LAUNCHED state is blocked)
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e6;
        amounts[1] = 10e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        vm.expectRevert(Vault.DuplicateMarketKey.selector);
        vault.propose("Olivia", 2025, proof, amounts);

        console2.log("=== NAME REUSE AFTER LAUNCH ===");
        console2.log("Same name+year+region correctly blocked after launch (DuplicateMarketKey)");
    }

    // ========== 9. COMMIT AFTER DEADLINE ==========

    function test_commitAfterDeadline_reverts() public {
        bytes32 proposalId = _proposeAs(alice, "Tardy", 2025, 5e6, 5e6);

        // Warp past deadline
        vm.warp(block.timestamp + 7 days + 1);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;

        vm.prank(bob);
        vm.expectRevert(Vault.DeadlinePassed.selector);
        vault.commit(proposalId, amounts);

        console2.log("=== COMMIT AFTER DEADLINE: Correctly reverts ===");
    }

    // ========== 10. LAUNCH AFTER DEADLINE ==========

    /// @notice launchMarket now enforces deadline: block.timestamp >= prop.deadline reverts.
    function test_launchAfterDeadline_reverts() public {
        bytes32 proposalId = _proposeAs(alice, "LateLaunch", 2025, 10e6, 10e6);

        // Warp past deadline
        vm.warp(block.timestamp + 7 days + 1);

        // Proposal is still OPEN (nobody withdrew or cancelled)
        Vault.ProposalInfo memory infoBefore = vault.getProposal(proposalId);
        assertEq(uint256(infoBefore.state), uint256(Vault.ProposalState.OPEN));

        // launchMarket now checks deadline and reverts
        vm.expectRevert(Vault.DeadlinePassed.selector);
        vault.launchMarket(proposalId);

        console2.log("=== LAUNCH AFTER DEADLINE: Correctly reverts ===");
    }

    // ========== 11. DOUBLE WITHDRAW ==========

    function test_doubleWithdraw_secondReverts() public {
        bytes32 proposalId = _proposeAs(alice, "DoubleW", 2025, 10e6, 10e6);

        // Warp past deadline to make it withdrawable
        vm.warp(block.timestamp + 7 days + 1);

        // First withdraw succeeds
        vm.prank(alice);
        vault.withdrawCommitment(proposalId);

        // Second withdraw should revert
        vm.prank(alice);
        vm.expectRevert(Vault.NothingToWithdraw.selector);
        vault.withdrawCommitment(proposalId);

        console2.log("=== DOUBLE WITHDRAW: Second correctly reverts ===");
    }

    // ========== 12. VAULT INSUFFICIENT BALANCE FOR CREATION FEE ==========

    /// @notice Now that feeSource pays creation fees, the vault itself doesn't need balance.
    ///         But if feeSource is underfunded, the launch will revert.
    function test_feeSourceInsufficientForCreationFee() public {
        // Create a new feeSource with no funds
        address poorFeeSource = address(0xBAAD);
        vault.setFeeSource(poorFeeSource);

        // poorFeeSource approves vault but has no USDC
        vm.prank(poorFeeSource);
        usdc.approve(address(vault), type(uint256).max);

        // Propose and commit enough to meet threshold
        bytes32 proposalId = _proposeAs(alice, "Broke", 2025, 10e6, 10e6);

        // This should revert because feeSource has no USDC to pay creation fee
        vm.expectRevert();
        vault.launchMarket(proposalId);

        console2.log("=== FEE SOURCE INSUFFICIENT: Correctly reverts ===");
    }

    /// @notice Test where feeSource truly has insufficient balance: fee exceeds available
    function test_feeSourceInsufficientForCreationFee_trueShortfall() public {
        // Set a very high creation fee
        pm.setMarketCreationFee(1000e6);

        // feeSource only has 10_000e6 but fee = 1000e6 * 2 = 2000e6
        // Actually 10_000e6 > 2000e6, so this would succeed.
        // Let's create a new feeSource with very little balance.
        address poorFeeSource = address(0xBAAD);
        vault.setFeeSource(poorFeeSource);
        usdc.mint(poorFeeSource, 100e6); // only 100 USDC
        vm.prank(poorFeeSource);
        usdc.approve(address(vault), type(uint256).max);

        // Alice proposes with 10+10 = 20e6
        bytes32 proposalId = _proposeAs(alice, "TooExpensive", 2025, 10e6, 10e6);

        // feeSource has 100e6 but fee = 1000e6 * 2 = 2000e6
        // This should revert on transferFrom
        vm.expectRevert();
        vault.launchMarket(proposalId);

        console2.log("=== TRUE SHORTFALL: Correctly reverts when fee > feeSource balance ===");
    }
}
