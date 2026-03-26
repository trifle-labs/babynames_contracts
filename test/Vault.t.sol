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
            oracle,          // defaultOracle
            20e6,            // defaultLaunchThreshold ($20)
            7 days,          // defaultDeadlineDuration
            address(this)    // owner
        );

        // Grant vault the MARKET_CREATOR_ROLE
        pm.grantMarketCreatorRole(address(vault));

        // Fund vault for creation fees
        usdc.mint(address(vault), 1000e6);

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

    function _proposeAsAlice(string memory _name, uint256 yesAmt, uint256 noAmt)
        internal
        returns (bytes32 proposalId)
    {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = yesAmt;
        amounts[1] = noAmt;
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        proposalId = vault.propose(_name, proof, amounts);
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

        bytes32 proposalId = _proposeAsAlice("Olivia", 5e6, 5e6);

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
        vault.propose("Olivia", emptyProof, amounts);
    }

    // ========== 3. COMMIT ==========

    function test_commit_multipleUsersAccumulate() public {
        bytes32 proposalId = _proposeAsAlice("Emma", 5e6, 5e6);

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
        bytes32 proposalId = _proposeAsAlice("Liam", 5e6, 5e6);
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

        // Both users have locked tokens
        uint256[] memory aliceLocked = vault.getLocked(info.marketId, alice);
        uint256[] memory bobLocked = vault.getLocked(info.marketId, bob);
        assertEq(aliceLocked.length, 2);
        assertEq(bobLocked.length, 2);

        // Both committed equally so should have equal locked shares
        assertEq(aliceLocked[0], bobLocked[0]);
        assertEq(aliceLocked[1], bobLocked[1]);
    }

    function test_launchMarket_belowThresholdReverts() public {
        bytes32 proposalId = _proposeAsAlice("Noah", 5e6, 5e6);
        // Only 10e6 committed, threshold is 20e6

        vm.expectRevert(Vault.BelowThreshold.selector);
        vault.launchMarket(proposalId);
    }

    // ========== 5. SAME-PRICE GUARANTEE ==========

    function test_samePriceGuarantee_shareRatioMatchesUsdcRatio() public {
        // Alice and Bob both commit to YES with different amounts
        // Share ratio should match USDC ratio
        bytes32 proposalId = _proposeAsAlice("Sophia", 8e6, 2e6);
        _commitAsBob(proposalId, 4e6, 6e6);

        // Total: YES=12e6, NO=8e6, total=20e6 => meets threshold
        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        uint256[] memory aliceLocked = vault.getLocked(info.marketId, alice);
        uint256[] memory bobLocked = vault.getLocked(info.marketId, bob);

        // For YES outcome: alice committed 8e6, bob committed 4e6 (ratio 2:1)
        // So alice should have 2x bob's YES shares
        if (bobLocked[0] > 0) {
            // aliceLocked[0] / bobLocked[0] should be ~2
            // Use cross-multiplication to avoid rounding: aliceLocked[0] * 1 ~= bobLocked[0] * 2
            assertApproxEqAbs(aliceLocked[0] * 1, bobLocked[0] * 2, 1);
        }

        // For NO outcome: alice committed 2e6, bob committed 6e6 (ratio 1:3)
        if (aliceLocked[1] > 0) {
            assertApproxEqAbs(aliceLocked[1] * 3, bobLocked[1] * 1, 1);
        }
    }

    // ========== 6. WITHDRAW COMMITMENT ==========

    function test_withdrawCommitment_afterExpiry() public {
        bytes32 proposalId = _proposeAsAlice("Charlotte", 5e6, 5e6);

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
        bytes32 proposalId = _proposeAsAlice("Charlotte", 5e6, 5e6);

        vm.prank(alice);
        vm.expectRevert(Vault.NotWithdrawable.selector);
        vault.withdrawCommitment(proposalId);
    }

    // ========== 7. CANCEL PROPOSAL ==========

    function test_cancelProposal_ownerCancelsUsersWithdraw() public {
        bytes32 proposalId = _proposeAsAlice("Amelia", 5e6, 5e6);
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
        bytes32 proposalId = _proposeAsAlice("Amelia", 5e6, 5e6);

        vm.prank(alice);
        vm.expectRevert();
        vault.cancelProposal(proposalId);
    }

    // ========== 8. CLAIM REFUND ==========

    function test_claimRefund_afterLaunchUnspentRefundable() public {
        // Create a proposal with asymmetric bets to generate unspent USDC
        bytes32 proposalId = _proposeAsAlice("Harper", 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        // Total = 40e6, threshold = 20e6
        uint256 aliceBefore = usdc.balanceOf(alice);
        uint256 bobBefore = usdc.balanceOf(bob);

        vault.launchMarket(proposalId);

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

    // ========== 9. UNLOCK ==========

    function test_unlock_afterResolutionTransfersTokens() public {
        bytes32 proposalId = _proposeAsAlice("Evelyn", 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        bytes32 marketId = info.marketId;
        PredictionMarket.MarketInfo memory mInfo = pm.getMarketInfo(marketId);

        uint256[] memory aliceLocked = vault.getLocked(marketId, alice);
        assertTrue(aliceLocked[0] > 0 || aliceLocked[1] > 0, "alice should have locked tokens");

        // Resolve market: YES wins (100% payout to outcome 0)
        uint256[] memory payoutPcts = new uint256[](2);
        payoutPcts[0] = 1e6; // YES wins
        payoutPcts[1] = 0;
        vm.prank(oracle);
        pm.resolveMarketWithPayoutSplit(marketId, payoutPcts);

        // Alice unlocks
        uint256 aliceYesBefore = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNoBefore = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);

        vm.prank(alice);
        vault.unlock(marketId);

        // Alice received her locked tokens
        uint256 aliceYesAfter = IERC20(mInfo.outcomeTokens[0]).balanceOf(alice);
        uint256 aliceNoAfter = IERC20(mInfo.outcomeTokens[1]).balanceOf(alice);
        assertEq(aliceYesAfter - aliceYesBefore, aliceLocked[0]);
        assertEq(aliceNoAfter - aliceNoBefore, aliceLocked[1]);

        // Locked amounts cleared
        uint256[] memory aliceLockedAfter = vault.getLocked(marketId, alice);
        assertEq(aliceLockedAfter.length, 0);

        // Alice can now redeem YES tokens on PredictionMarket
        if (aliceLocked[0] > 0) {
            vm.prank(alice);
            IERC20(mInfo.outcomeTokens[0]).approve(address(pm), aliceLocked[0]);
            vm.prank(alice);
            pm.redeem(mInfo.outcomeTokens[0], aliceLocked[0]);
        }
    }

    function test_unlock_beforeResolutionReverts() public {
        bytes32 proposalId = _proposeAsAlice("Mia", 10e6, 10e6);
        _commitAsBob(proposalId, 10e6, 10e6);

        vault.launchMarket(proposalId);

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);

        vm.prank(alice);
        vm.expectRevert(Vault.MarketNotResolved.selector);
        vault.unlock(info.marketId);
    }

    function test_unlock_noLockedTokensReverts() public {
        vm.prank(alice);
        vm.expectRevert(Vault.NoLockedTokens.selector);
        vault.unlock(bytes32(uint256(999)));
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
        assertEq(info.name, ""); // no name for admin proposals
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
            0,  // use default threshold
            0   // use default deadline
        );

        Vault.ProposalInfo memory info = vault.getProposal(proposalId);
        assertEq(info.launchThreshold, 20e6); // defaultLaunchThreshold
        assertEq(info.deadline, block.timestamp + 7 days); // defaultDeadlineDuration
    }

    // ========== 11. DUPLICATE NAME ==========

    function test_duplicateName_revertsWhileActive() public {
        _proposeAsAlice("Olivia", 5e6, 5e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        vm.expectRevert(Vault.DuplicateName.selector);
        vault.propose("Olivia", proof, amounts);
    }

    function test_duplicateName_caseInsensitive() public {
        _proposeAsAlice("Olivia", 5e6, 5e6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        vm.expectRevert(Vault.DuplicateName.selector);
        vault.propose("olivia", proof, amounts);
    }

    function test_duplicateName_allowedAfterExpiry() public {
        _proposeAsAlice("Olivia", 5e6, 5e6);

        // Warp past deadline so original proposal expires
        vm.warp(block.timestamp + 7 days + 1);

        // Now bob can propose the same name
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5e6;
        amounts[1] = 5e6;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(bob);
        bytes32 proposalId = vault.propose("Olivia", proof, amounts);
        assertTrue(proposalId != bytes32(0));
    }
}
