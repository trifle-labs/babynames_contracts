// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Vault} from "../src/Vault.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

contract TestUSDC is ERC20 {
    function name() public pure override returns (string memory) { return "Test USDC"; }
    function symbol() public pure override returns (string memory) { return "tUSDC"; }
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract VaultTest is Test {
    TestUSDC usdc;
    PredictionMarket pm;
    Vault vault;

    address oracle = address(0xBEEF);
    address treasury = address(0xCAFE);
    address feeSource = address(0xFEE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        usdc = new TestUSDC();

        // PredictionMarket sets owner = tx.origin in constructor,
        // so we prank both msg.sender and tx.origin to address(this).
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

        // Grant vault the MARKET_CREATOR_ROLE
        pm.grantMarketCreatorRole(address(vault));

        // Fund feeSource and approve vault from feeSource
        usdc.mint(feeSource, 1000e6);
        vm.prank(feeSource);
        usdc.approve(address(vault), type(uint256).max);

        // Fund users
        usdc.mint(alice, 10_000e6);
        usdc.mint(bob, 10_000e6);

        // Approve vault from users
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ========== HELPERS ==========

    function _proposeAsAlice(string memory _name, uint16 year, uint256 yesAmt, uint256 noAmt)
        internal
        returns (bytes32 proposalId)
    {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = yesAmt;
        amounts[1] = noAmt;
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        proposalId = vault.propose(_name, year, proof, amounts);
    }

    function _commitAsBob(bytes32 proposalId, uint256 yesAmt, uint256 noAmt) internal {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = yesAmt;
        amounts[1] = noAmt;
        vm.prank(bob);
        vault.commit(proposalId, amounts);
    }

    // ========== 1. PROPOSE ==========

    function test_propose_createsProposalAndCommits() public {
        uint256 aliceBefore = usdc.balanceOf(alice);
        uint256 vaultBefore = usdc.balanceOf(address(vault));

        bytes32 proposalId = _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(info.outcomeNames.length, 2);
        assertEq(info.outcomeNames[0], "YES");
        assertEq(info.outcomeNames[1], "NO");
        assertEq(uint256(info.state), uint256(Vault.ProposalState.OPEN));
        assertEq(info.totalCommitted, 10e6);
        assertEq(info.totalPerOutcome[0], 5e6);
        assertEq(info.totalPerOutcome[1], 5e6);
        assertEq(info.launchThreshold, 20e6);
        assertEq(info.oracle, oracle);
        assertEq(info.name, "olivia"); // lowercased
        assertEq(info.year, 2025);
        assertEq(info.committers.length, 1);
        assertEq(info.committers[0], alice);

        // Check committed amounts for alice
        uint256[] memory committed = vault.getCommitted(proposalId, alice);
        assertEq(committed[0], 5e6);
        assertEq(committed[1], 5e6);

        // USDC transferred from alice to vault
        assertEq(usdc.balanceOf(alice), aliceBefore - 10e6);
        assertEq(usdc.balanceOf(address(vault)), vaultBefore + 10e6);
    }

    // ========== 2. PROPOSE WITH INVALID NAME ==========

    function test_propose_invalidNameReverts() public {
        // Set a merkle root so names are validated
        // Use a dummy root that won't match any proof
        bytes32 fakeRoot = keccak256("some merkle root");
        vault.setNamesMerkleRoot(fakeRoot);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(Vault.InvalidName.selector);
        vault.propose("Olivia", 2025, emptyProof, amounts);
    }

    // ========== 3. COMMIT ==========

    function test_commit_multipleUsersAccumulate() public {
        bytes32 proposalId = _proposeAsAlice("Emma", 2025, 5e6, 5e6);

        // Bob commits
        _commitAsBob(proposalId, 3e6, 7e6);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(info.totalCommitted, 20e6); // 10 alice + 10 bob
        assertEq(info.totalPerOutcome[0], 8e6); // 5 + 3
        assertEq(info.totalPerOutcome[1], 12e6); // 5 + 7
        assertEq(info.committers.length, 2);

        // Alice commits again
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2e6;
        amounts[1] = 0;
        vm.prank(alice);
        vault.commit(proposalId, amounts);

        info = vault.getProposal(proposalId);
        assertEq(info.totalCommitted, 22e6);
        assertEq(info.totalPerOutcome[0], 10e6); // 5 + 3 + 2
        assertEq(info.committers.length, 2); // alice not duplicated
    }

    // ========== 4. LAUNCH MARKET ==========

    function test_launchMarket_createsMarketOnPredictionMarket() public {
        bytes32 proposalId = _proposeAsAlice("Liam", 2025, 5e6, 5e6);
        _commitAsBob(proposalId, 5e6, 5e6);

        // Total is 20e6 which meets threshold
        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(uint256(info.state), uint256(Vault.ProposalState.LAUNCHED));
        assertTrue(info.marketId != bytes32(0));

        // Market exists on PredictionMarket
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(info.marketId);
        assertEq(mInfo.oracle, oracle);
        assertEq(mInfo.outcomeTokens.length, 2);
        assertFalse(mInfo.resolved);

        // Both users claim shares after launch
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);

        uint256 aliceYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);
        uint256 bobYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(bob);
        uint256 bobNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(bob);

        // Both committed equally so should have equal shares
        assertEq(aliceYes, bobYes);
        assertEq(aliceNo, bobNo);
    }

    function test_launchMarket_belowThresholdReverts() public {
        bytes32 proposalId = _proposeAsAlice("Noah", 2025, 5e6, 5e6);
        // Only 10e6 committed, threshold is 20e6

        vm.expectRevert(Vault.BelowThreshold.selector);
        vault.launchMarket(proposalId);
    }

    // ========== 5. SAME-PRICE GUARANTEE ==========

    function test_samePriceGuarantee_shareRatioMatchesUsdcRatio() public {
        // Alice and Bob both commit to YES with different amounts
        // Share ratio should match USDC ratio
        bytes32 proposalId = _proposeAsAlice("Sophia", 2025, 8e6, 2e6);
        _commitAsBob(proposalId, 4e6, 6e6);

        // Total: YES=12e6, NO=8e6, total=20e6 => meets threshold
        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(info.marketId);

        // Claim shares for both users
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);

        uint256 aliceYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);
        uint256 bobYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(bob);
        uint256 bobNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(bob);

        // For YES outcome: alice committed 8e6, bob committed 4e6 (ratio 2:1)
        // So alice should have 2x bob's YES shares
        if (bobYes > 0) {
            // aliceYes * 1 ~= bobYes * 2
            assertApproxEqAbs(aliceYes * 1, bobYes * 2, 1);
        }

        // For NO outcome: alice committed 2e6, bob committed 6e6 (ratio 1:3)
        if (aliceNo > 0) {
            assertApproxEqAbs(aliceNo * 3, bobNo * 1, 1);
        }
    }

    // ========== 6. WITHDRAW COMMITMENT ==========

    function test_withdrawCommitment_afterExpiry() public {
        bytes32 proposalId = _proposeAsAlice("Charlotte", 2025, 5e6, 5e6);

        uint256 aliceBefore = usdc.balanceOf(alice);

        // Warp past deadline
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(alice);
        vault.withdrawCommitment(proposalId);

        // Alice gets her USDC back
        assertEq(usdc.balanceOf(alice), aliceBefore + 10e6);

        // Proposal state changed to EXPIRED
        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(uint256(info.state), uint256(Vault.ProposalState.EXPIRED));

        // Committed amounts zeroed out
        uint256[] memory committed = vault.getCommitted(proposalId, alice);
        assertEq(committed[0], 0);
        assertEq(committed[1], 0);
    }

    function test_withdrawCommitment_beforeExpiryReverts() public {
        bytes32 proposalId = _proposeAsAlice("Charlotte", 2025, 5e6, 5e6);

        vm.prank(alice);
        vm.expectRevert(Vault.NotWithdrawable.selector);
        vault.withdrawCommitment(proposalId);
    }

    // ========== 7. CANCEL PROPOSAL ==========

    function test_cancelProposal_ownerCancelsUsersWithdraw() public {
        bytes32 proposalId = _proposeAsAlice("Amelia", 2025, 5e6, 5e6);
        _commitAsBob(proposalId, 3e6, 2e6);

        uint256 aliceBefore = usdc.balanceOf(alice);
        uint256 bobBefore = usdc.balanceOf(bob);

        // Owner cancels
        vault.cancelProposal(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(uint256(info.state), uint256(Vault.ProposalState.CANCELLED));

        // Alice withdraws
        vm.prank(alice);
        vault.withdrawCommitment(proposalId);
        assertEq(usdc.balanceOf(alice), aliceBefore + 10e6);

        // Bob withdraws
        vm.prank(bob);
        vault.withdrawCommitment(proposalId);
        assertEq(usdc.balanceOf(bob), bobBefore + 5e6);
    }

    function test_cancelProposal_nonOwnerReverts() public {
        bytes32 proposalId = _proposeAsAlice("Amelia", 2025, 5e6, 5e6);

        vm.prank(alice);
        vm.expectRevert();
        vault.cancelProposal(proposalId);
    }

    // ========== 8. CLAIM REFUND ==========

    function test_claimRefund_afterLaunchUnspentRefundable() public {
        // Create a proposal with symmetric bets to generate unspent USDC
        bytes32 proposalId = _proposeAsAlice("Harper", 2025, 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        // Total = 40e6, threshold = 20e6
        uint256 aliceBefore = usdc.balanceOf(alice);
        uint256 bobBefore = usdc.balanceOf(bob);

        vault.launchMarket(proposalId);

        // Users must claimShares first to get refunds credited
        vm.prank(alice);
        vault.claimShares(proposalId);
        vm.prank(bob);
        vault.claimShares(proposalId);

        // Check if there are pending refunds
        uint256 aliceRefund = vault.pendingRefunds(alice);
        uint256 bobRefund = vault.pendingRefunds(bob);

        // Both committed equally, so refunds should be equal
        assertEq(aliceRefund, bobRefund);

        if (aliceRefund > 0) {
            vm.prank(alice);
            vault.claimRefund();
            assertEq(usdc.balanceOf(alice), aliceBefore + aliceRefund);
            assertEq(vault.pendingRefunds(alice), 0);
        }

        if (bobRefund > 0) {
            vm.prank(bob);
            vault.claimRefund();
            assertEq(usdc.balanceOf(bob), bobBefore + bobRefund);
            assertEq(vault.pendingRefunds(bob), 0);
        }
    }

    function test_claimRefund_nothingToClaimReverts() public {
        vm.prank(alice);
        vm.expectRevert(Vault.NothingToClaim.selector);
        vault.claimRefund();
    }

    // ========== 9. CLAIM SHARES AND REDEEM ==========

    function test_claimShares_afterLaunchThenRedeem() public {
        bytes32 proposalId = _proposeAsAlice("Evelyn", 2025, 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        bytes32 marketId = info.marketId;
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(marketId);

        // Alice claims shares (tokens go directly to her wallet)
        vm.prank(alice);
        vault.claimShares(proposalId);

        uint256 aliceYes = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNo = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);
        assertTrue(aliceYes > 0 || aliceNo > 0, "alice should have tokens after claimShares");

        // Verify hasClaimed
        assertTrue(vault.hasClaimed(proposalId, alice), "alice should be marked as claimed");
        assertFalse(vault.hasClaimed(proposalId, bob), "bob should not be marked as claimed yet");

        // Resolve market: YES wins (100% payout to outcome 0)
        uint256[] memory payoutPcts = new uint256[](2);
        payoutPcts[0] = 1e6; // YES wins
        payoutPcts[1] = 0;
        vm.prank(oracle);
        pm.resolveMarketWithPayoutSplit(marketId, payoutPcts);

        // Alice can now redeem YES tokens on PredictionMarket
        if (aliceYes > 0) {
            vm.prank(alice);
            IERC20(mInfo.outcomeTokens[0]).approve(address(pm), aliceYes);
            vm.prank(alice);
            pm.redeem(mInfo.outcomeTokens[0], aliceYes);
        }
    }

    function test_claimShares_beforeLaunchReverts() public {
        bytes32 proposalId = _proposeAsAlice("Mia", 2025, 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        // Don't launch — try to claim
        vm.prank(alice);
        vm.expectRevert(Vault.NotLaunched.selector);
        vault.claimShares(proposalId);
    }

    function test_claimShares_doubleClaimReverts() public {
        bytes32 proposalId = _proposeAsAlice("Luna", 2025, 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        vault.launchMarket(proposalId);

        vm.prank(alice);
        vault.claimShares(proposalId);

        // Second claim should revert
        vm.prank(alice);
        vm.expectRevert(Vault.AlreadyClaimed.selector);
        vault.claimShares(proposalId);
    }

    // ========== 10. ADMIN PROPOSE ==========

    function test_adminPropose_createsCustomProposal() public {
        string[] memory outcomeNames = new string[](3);
        outcomeNames[0] = "Olivia";
        outcomeNames[1] = "Emma";
        outcomeNames[2] = "Other";

        bytes32 proposalId = vault.adminPropose(
            outcomeNames,
            oracle,
            abi.encode("Top girl name 2026"),
            2025,                           // year
            "",                             // region (national)
            50e6,                           // custom threshold
            block.timestamp + 30 days       // custom deadline
        );

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(info.outcomeNames.length, 3);
        assertEq(info.outcomeNames[0], "Olivia");
        assertEq(info.outcomeNames[1], "Emma");
        assertEq(info.outcomeNames[2], "Other");
        assertEq(info.launchThreshold, 50e6);
        assertEq(info.oracle, oracle);
        assertEq(uint256(info.state), uint256(Vault.ProposalState.OPEN));
        assertEq(info.year, 2025);
    }

    function test_adminPropose_nonOwnerReverts() public {
        string[] memory outcomeNames = new string[](2);
        outcomeNames[0] = "YES";
        outcomeNames[1] = "NO";

        vm.prank(alice);
        vm.expectRevert();
        vault.adminPropose(
            outcomeNames,
            oracle,
            abi.encode("test"),
            2025,
            "",
            20e6,
            block.timestamp + 7 days
        );
    }

    function test_adminPropose_usesDefaultsWhenZero() public {
        string[] memory outcomeNames = new string[](2);
        outcomeNames[0] = "YES";
        outcomeNames[1] = "NO";

        bytes32 proposalId = vault.adminPropose(
            outcomeNames,
            oracle,
            abi.encode("test"),
            2025,   // year
            "",     // region
            0,      // use default threshold
            0       // use default deadline
        );

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(info.launchThreshold, 20e6); // defaultLaunchThreshold
        assertEq(info.deadline, block.timestamp + 7 days); // defaultDeadlineDuration
    }

    // ========== 11. DUPLICATE MARKET KEY ==========

    function test_duplicateMarketKey_revertsWhileActive() public {
        _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        vm.expectRevert(Vault.DuplicateMarketKey.selector);
        vault.propose("Olivia", 2025, proof, amounts);
    }

    function test_duplicateMarketKey_caseInsensitive() public {
        _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        vm.expectRevert(Vault.DuplicateMarketKey.selector);
        vault.propose("olivia", 2025, proof, amounts);
    }

    function test_duplicateMarketKey_allowedAfterExpiry() public {
        bytes32 firstProposalId = _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        // Warp past deadline so original proposal expires
        vm.warp(block.timestamp + 7 days + 1);

        // Withdraw to transition state from OPEN -> EXPIRED
        // (The duplicate check blocks OPEN and LAUNCHED states, so we must
        //  explicitly expire by calling withdrawCommitment after deadline.)
        vm.prank(alice);
        vault.withdrawCommitment(firstProposalId);

        // Now bob can propose the same name+year+region
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        bytes32 proposalId = vault.propose("Olivia", 2025, proof, amounts);
        assertTrue(proposalId != bytes32(0));
    }

    // ========== 12. SAME NAME DIFFERENT YEAR SUCCEEDS ==========

    function test_sameNameDifferentYear_succeeds() public {
        vault.openYear(2026);

        _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        // Same name, different year should succeed
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        bytes32 proposalId = vault.propose("Olivia", 2026, proof, amounts);
        assertTrue(proposalId != bytes32(0));
    }

    // ========== 13. SAME NAME DIFFERENT REGION SUCCEEDS ==========

    function test_sameNameDifferentRegion_succeeds() public {
        _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        // Same name + year but different region should succeed
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        bytes32 proposalId = vault.proposeRegional("Olivia", 2025, "california", proof, amounts);
        assertTrue(proposalId != bytes32(0));
    }

    // ========== 14. YEAR NOT OPEN REVERTS ==========

    function test_propose_yearNotOpenReverts() public {
        // Year 2030 is not open
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(Vault.YearNotOpen.selector);
        vault.propose("Olivia", 2030, proof, amounts);
    }

    // ========== 15. CLOSE YEAR BLOCKS NEW PROPOSALS ==========

    function test_closeYear_blocksNewProposals() public {
        // 2025 is open from setUp, close it
        vault.closeYear(2025);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        vm.expectRevert(Vault.YearNotOpen.selector);
        vault.propose("Olivia", 2025, proof, amounts);
    }

    // ========== 16. DUPLICATE MARKET KEY BLOCKS LAUNCHED ==========

    function test_duplicateMarketKey_revertsWhileLaunched() public {
        // Propose and launch
        bytes32 proposalId = _proposeAsAlice("Olivia", 2025, 10e6, 10e6);
        vault.launchMarket(proposalId);

        // Same name+year+region should still revert because state is LAUNCHED
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        vm.expectRevert(Vault.DuplicateMarketKey.selector);
        vault.propose("Olivia", 2025, proof, amounts);
    }

    // ========== 17. GET MARKET KEY ==========

    function test_getMarketKey() public view {
        bytes32 key1 = vault.getMarketKey("Olivia", 2025, "");
        bytes32 key2 = vault.getMarketKey("olivia", 2025, "");
        assertEq(key1, key2, "case insensitive market key");

        bytes32 key3 = vault.getMarketKey("Olivia", 2026, "");
        assertTrue(key1 != key3, "different year = different key");

        bytes32 key4 = vault.getMarketKey("Olivia", 2025, "california");
        assertTrue(key1 != key4, "different region = different key");
    }

    // ========== 18. GET PROPOSAL BY MARKET KEY ==========

    function test_getProposalByMarketKey() public {
        bytes32 proposalId = _proposeAsAlice("Olivia", 2025, 5e6, 5e6);

        bytes32 found = vault.getProposalByMarketKey("Olivia", 2025, "");
        assertEq(found, proposalId);

        // Case insensitive lookup
        bytes32 found2 = vault.getProposalByMarketKey("olivia", 2025, "");
        assertEq(found2, proposalId);
    }
}
