// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../helpers/TestHelpers.sol";
import "../../src/BetSlipSVG.sol";

/**
 * @title NFTVoucherTest
 * @notice Tests for the ERC-721 bet-slip NFT feature added to BabyNameMarket
 */
contract NFTVoucherTest is TestHelpers {

    // ============ Minting ============

    function test_buy_mintsNFT() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        uint256 beforeBalance = market.balanceOf(alice);
        uint256 beforeNextTokenId = market.nextTokenId();

        vm.prank(alice);
        market.buy(poolId, 5 * ONE_UNIT);

        assertEq(market.balanceOf(alice), beforeBalance + 1, "alice should own 1 NFT");
        assertEq(market.nextTokenId(), beforeNextTokenId + 1, "nextTokenId incremented");

        uint256 tokenId = beforeNextTokenId;
        assertEq(market.ownerOf(tokenId), alice, "alice owns the minted token");
    }

    function test_buy_storesVoucherData() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        uint256 tokenId = market.nextTokenId();

        vm.prank(alice);
        market.buy(poolId, 5 * ONE_UNIT);

        (uint256 vPoolId, uint256 vAmount, uint256 vPurchasedAt) = market.vouchers(tokenId);
        assertEq(vPoolId, poolId, "voucher poolId");
        // 5 USDC (6 decimals) normalized to 1e18 = 5e18
        assertEq(vAmount, 5 * 1e18, "voucher amount normalized to 1e18");
        assertApproxEqAbs(vPurchasedAt, block.timestamp, 1, "voucher purchasedAt");
    }

    function test_multipleBuys_mintMultipleNFTs() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        _buyAs(alice, poolId, 5 * ONE_UNIT);
        _buyAs(alice, poolId, 3 * ONE_UNIT);

        assertEq(market.balanceOf(alice), 2, "alice should own 2 NFTs");
        assertEq(market.ownerOf(1), alice);
        assertEq(market.ownerOf(2), alice);
    }

    function test_buy_emitsVoucherMinted() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        uint256 tokenId = market.nextTokenId();
        uint256 normalizedAmt = 5 * 1e18; // 5 USDC normalized to 1e18 (scaleFactor=1e12 for 6 decimals)

        vm.expectEmit(true, true, true, true);
        emit BabyNameMarket.VoucherMinted(tokenId, poolId, alice, normalizedAmt);

        _buyAs(alice, poolId, 5 * ONE_UNIT);
    }

    // ============ addNameAndBuy minting ============

    function test_addNameAndBuy_mintsNFT() public {
        uint256 catId = _createTestCategory();
        uint256 tokenId = market.nextTokenId();

        vm.prank(alice);
        market.addNameAndBuy(catId, "Aria", _emptyProof(), 5 * ONE_UNIT);

        assertEq(market.ownerOf(tokenId), alice, "alice owns minted token from addNameAndBuy");
    }

    function test_addNameAndBuy_zeroAmount_doesNotMintNFT() public {
        uint256 catId = _createTestCategory();
        uint256 beforeNextTokenId = market.nextTokenId();

        vm.prank(alice);
        market.addNameAndBuy(catId, "Aria", _emptyProof(), 0);

        assertEq(market.nextTokenId(), beforeNextTokenId, "no NFT minted when amount=0");
    }

    // ============ Soulbound (non-transferable) ============

    function test_transfer_revertsByDefault() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        _buyAs(alice, poolId, 5 * ONE_UNIT);
        uint256 tokenId = 1;

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.TokensNonTransferable.selector);
        market.transferFrom(alice, bob, tokenId);
    }

    function test_safeTransfer_revertsByDefault() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        _buyAs(alice, poolId, 5 * ONE_UNIT);

        vm.prank(alice);
        vm.expectRevert(BabyNameMarket.TokensNonTransferable.selector);
        market.safeTransferFrom(alice, bob, 1);
    }

    // ============ setTransfersEnabled ============

    function test_setTransfersEnabled_ownerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        market.setTransfersEnabled(true);
    }

    function test_setTransfersEnabled_allowsTransfer() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        _buyAs(alice, poolId, 5 * ONE_UNIT);

        // Enable transfers
        vm.prank(owner);
        market.setTransfersEnabled(true);
        assertTrue(market.transfersEnabled(), "transfers should be enabled");

        // Now transfer should succeed
        vm.prank(alice);
        market.transferFrom(alice, bob, 1);
        assertEq(market.ownerOf(1), bob, "bob should own the token after transfer");
    }

    function test_setTransfersEnabled_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BabyNameMarket.TransfersEnabledSet(true);
        market.setTransfersEnabled(true);
    }

    function test_setTransfersEnabled_canDisableAgain() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        vm.prank(owner);
        market.setTransfersEnabled(true);

        _buyAs(alice, poolId, 5 * ONE_UNIT);

        // Transfer succeeds while enabled
        vm.prank(alice);
        market.transferFrom(alice, bob, 1);
        assertEq(market.ownerOf(1), bob);

        // Disable transfers again
        vm.prank(owner);
        market.setTransfersEnabled(false);

        // Transfer now reverts
        vm.prank(bob);
        vm.expectRevert(BabyNameMarket.TokensNonTransferable.selector);
        market.transferFrom(bob, alice, 1);
    }

    // ============ tokenURI ============

    function test_tokenURI_returnsDataURI() public {
        uint256 catId = _createTestCategory();
        uint256[] memory poolIds = market.getCategoryPools(catId);
        uint256 poolId = poolIds[0];

        _buyAs(alice, poolId, 5 * ONE_UNIT);

        string memory uri = market.tokenURI(1);

        // Should start with "data:application/json;base64,"
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory uriBytes = bytes(uri);
        assertTrue(uriBytes.length > prefix.length, "tokenURI must have content");
        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(uriBytes[i], prefix[i], "tokenURI prefix mismatch");
        }
    }

    function test_tokenURI_revertsForNonexistentToken() public {
        vm.expectRevert();
        market.tokenURI(999);
    }

    // ============ ERC-721 Metadata ============

    function test_nftName() public view {
        assertEq(market.name(), "Baby Name Market Slip");
    }

    function test_nftSymbol() public view {
        assertEq(market.symbol(), "BNMS");
    }

    function test_supportsInterface_ERC721() public view {
        // ERC-721 interface ID
        assertTrue(market.supportsInterface(0x80ac58cd));
    }

    function test_supportsInterface_ERC721Metadata() public view {
        // ERC-721 Metadata interface ID
        assertTrue(market.supportsInterface(0x5b5e139f));
    }
}
