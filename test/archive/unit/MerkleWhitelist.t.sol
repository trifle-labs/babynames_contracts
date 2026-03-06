// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../helpers/TestHelpers.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleWhitelistTest is TestHelpers {
    // Merkle tree for 5 names: ["olivia", "emma", "charlotte", "liam", "noah"]
    // Using OZ StandardMerkleTree leaf format: keccak256(bytes.concat(keccak256(abi.encode(name))))

    bytes32 OLIVIA_LEAF;
    bytes32 EMMA_LEAF;
    bytes32 CHARLOTTE_LEAF;
    bytes32 LIAM_LEAF;
    bytes32 NOAH_LEAF;

    bytes32 merkleRoot;
    // Store proofs for each name
    mapping(string => bytes32[]) proofs;

    function setUp() public override {
        super.setUp();

        // Compute leaf hashes
        OLIVIA_LEAF = keccak256(bytes.concat(keccak256(abi.encode("olivia"))));
        EMMA_LEAF = keccak256(bytes.concat(keccak256(abi.encode("emma"))));
        CHARLOTTE_LEAF = keccak256(bytes.concat(keccak256(abi.encode("charlotte"))));
        LIAM_LEAF = keccak256(bytes.concat(keccak256(abi.encode("liam"))));
        NOAH_LEAF = keccak256(bytes.concat(keccak256(abi.encode("noah"))));

        // Build a merkle tree from the 5 leaves
        bytes32[] memory leaves = new bytes32[](5);
        leaves[0] = OLIVIA_LEAF;
        leaves[1] = EMMA_LEAF;
        leaves[2] = CHARLOTTE_LEAF;
        leaves[3] = LIAM_LEAF;
        leaves[4] = NOAH_LEAF;

        // Sort leaves for deterministic tree
        _sortBytes32(leaves);

        // Build tree bottom-up
        // Level 0: 5 leaves -> pad to 8 (next power of 2? no, we do simple pairwise)
        // Actually, let's compute the root and proofs properly
        merkleRoot = _computeRoot(leaves);

        // Compute proof for each name
        _storeProof("olivia", OLIVIA_LEAF, leaves);
        _storeProof("emma", EMMA_LEAF, leaves);
        _storeProof("charlotte", CHARLOTTE_LEAF, leaves);
        _storeProof("liam", LIAM_LEAF, leaves);
        _storeProof("noah", NOAH_LEAF, leaves);

        // Set the merkle root on the contract
        vm.prank(owner);
        market.setNamesMerkleRoot(merkleRoot);
    }

    // ============ Tree Building Helpers ============

    function _sortBytes32(bytes32[] memory arr) internal pure {
        for (uint256 i = 1; i < arr.length; i++) {
            bytes32 key = arr[i];
            uint256 j = i;
            while (j > 0 && arr[j-1] > key) {
                arr[j] = arr[j-1];
                j--;
            }
            arr[j] = key;
        }
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 1) return leaves[0];

        // Build each level
        bytes32[] memory current = leaves;
        while (current.length > 1) {
            uint256 len = current.length;
            uint256 nextLen = (len + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLen);
            for (uint256 i = 0; i < nextLen; i++) {
                if (2 * i + 1 < len) {
                    next[i] = _hashPair(current[2*i], current[2*i+1]);
                } else {
                    next[i] = current[2*i]; // Odd leaf promoted
                }
            }
            current = next;
        }
        return current[0];
    }

    function _storeProof(string memory name, bytes32 leaf, bytes32[] memory sortedLeaves) internal {
        // Find index of leaf
        uint256 idx = type(uint256).max;
        for (uint256 i = 0; i < sortedLeaves.length; i++) {
            if (sortedLeaves[i] == leaf) {
                idx = i;
                break;
            }
        }
        require(idx != type(uint256).max, "leaf not found");

        // Build proof by walking up the tree
        bytes32[] memory current = sortedLeaves;
        bytes32[] memory tempProof = new bytes32[](10); // max depth
        uint256 proofLen = 0;
        uint256 currentIdx = idx;

        while (current.length > 1) {
            uint256 len = current.length;
            uint256 nextLen = (len + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLen);

            uint256 pairIdx = currentIdx ^ 1; // sibling index
            if (pairIdx < len) {
                tempProof[proofLen++] = current[pairIdx];
            }

            for (uint256 i = 0; i < nextLen; i++) {
                if (2 * i + 1 < len) {
                    next[i] = _hashPair(current[2*i], current[2*i+1]);
                } else {
                    next[i] = current[2*i];
                }
            }

            currentIdx = currentIdx / 2;
            current = next;
        }

        // Copy to storage
        for (uint256 i = 0; i < proofLen; i++) {
            proofs[name].push(tempProof[i]);
        }
    }

    function _getProof(string memory name) internal view returns (bytes32[] memory) {
        return proofs[name];
    }

    function _getProofs(string[] memory names) internal view returns (bytes32[][] memory) {
        bytes32[][] memory result = new bytes32[][](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            // Lowercase the name for proof lookup
            result[i] = proofs[_toLower(names[i])];
        }
        return result;
    }

    function _toLower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] >= 0x41 && b[i] <= 0x5A) {
                b[i] = bytes1(uint8(b[i]) + 32);
            }
        }
        return string(b);
    }

    // ============ Tests ============

    function test_ValidProof_CreateCategory() public {
        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "Emma";

        bytes32[][] memory nameProofs = _getProofs(names);

        // Verify proofs work before passing to contract
        assertTrue(MerkleProof.verify(nameProofs[0], merkleRoot, OLIVIA_LEAF));
        assertTrue(MerkleProof.verify(nameProofs[1], merkleRoot, EMMA_LEAF));

        uint256 catId = market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, nameProofs
        );
        assertEq(catId, 1);
    }

    function test_InvalidProof_CreateCategory() public {
        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "NotAName";

        bytes32[][] memory nameProofs = new bytes32[][](2);
        nameProofs[0] = _getProof("olivia");
        nameProofs[1] = new bytes32[](0); // invalid proof for invalid name

        vm.expectRevert(BabyNameMarketCurve.InvalidNameProof.selector);
        market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, nameProofs
        );
    }

    function test_ValidProof_AddNameToCategory() public {
        // First create category with valid names
        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "Emma";

        uint256 catId = market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, _getProofs(names)
        );

        // Add a new valid name
        uint256 poolId = market.addNameToCategory(catId, "Charlotte", _getProof("charlotte"));
        (, string memory name, , , ) = market.getPoolInfo(poolId);
        assertEq(name, "Charlotte");
    }

    function test_InvalidProof_AddNameToCategory() public {
        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "Emma";

        uint256 catId = market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, _getProofs(names)
        );

        vm.expectRevert(BabyNameMarketCurve.InvalidNameProof.selector);
        market.addNameToCategory(catId, "NotAName", _emptyProof());
    }

    function test_NoMerkleRoot_AllNamesAllowed() public {
        // Remove merkle root
        vm.prank(owner);
        market.setNamesMerkleRoot(bytes32(0));

        string[] memory names = new string[](2);
        names[0] = "AnyRandomName";
        names[1] = "AnotherRandomName";

        // Should work with empty proofs when no root is set
        uint256 catId = market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, _emptyProofs()
        );
        assertEq(catId, 1);
    }

    function test_ManualApproval_BypassesMerkle() public {
        // Manually approve a name that's not in the tree
        vm.prank(owner);
        market.approveNameManually("Xylophone");

        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "Xylophone";

        bytes32[][] memory nameProofs = new bytes32[][](2);
        nameProofs[0] = _getProof("olivia");
        nameProofs[1] = new bytes32[](0); // no merkle proof needed for approved names

        uint256 catId = market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, nameProofs
        );
        assertEq(catId, 1);
    }

    function test_ExactaTrifecta_SkipsValidation() public {
        // Exacta and trifecta should not validate names
        string[] memory names = new string[](2);
        names[0] = "NotARealName / AlsoFake";
        names[1] = "FakeName / StillFake";

        // These should work because exacta (type 1) skips validation
        uint256 catId = market.createCategory(
            2025, 12, 1, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, _emptyProofs()
        );
        assertGt(catId, 0);

        // Trifecta (type 2) also skips
        string[] memory triNames = new string[](2);
        triNames[0] = "A / B / C";
        triNames[1] = "D / E / F";
        uint256 catId2 = market.createCategory(
            2025, 123, 2, BabyNameMarketCurve.Gender.Female, triNames, block.timestamp + 30 days, _emptyProofs()
        );
        assertGt(catId2, 0);
    }

    function test_OnlyOwner_SetMerkleRoot() public {
        vm.prank(alice);
        vm.expectRevert();
        market.setNamesMerkleRoot(bytes32(uint256(1)));
    }

    function test_OnlyOwner_ApproveNameManually() public {
        vm.prank(alice);
        vm.expectRevert();
        market.approveNameManually("Test");
    }

    function test_CaseInsensitive_Validation() public {
        // "OLIVIA" should match "olivia" in the tree
        string[] memory names = new string[](2);
        names[0] = "OLIVIA";
        names[1] = "emma";

        bytes32[][] memory nameProofs = new bytes32[][](2);
        nameProofs[0] = _getProof("olivia");
        nameProofs[1] = _getProof("emma");

        uint256 catId = market.createCategory(
            2025, 1, 0, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, nameProofs
        );
        assertEq(catId, 1);
    }

    function test_TopN_ValidatesNames() public {
        // TopN (type 3) should also validate names
        string[] memory names = new string[](2);
        names[0] = "Olivia";
        names[1] = "Emma";

        uint256 catId = market.createCategory(
            2025, 3, 3, BabyNameMarketCurve.Gender.Female, names, block.timestamp + 30 days, _getProofs(names)
        );
        assertGt(catId, 0);

        // Invalid name should fail
        string[] memory badNames = new string[](2);
        badNames[0] = "Olivia";
        badNames[1] = "NotARealName";

        bytes32[][] memory badProofs = new bytes32[][](2);
        badProofs[0] = _getProof("olivia");
        badProofs[1] = new bytes32[](0);

        vm.expectRevert(BabyNameMarketCurve.InvalidNameProof.selector);
        market.createCategory(
            2025, 3, 3, BabyNameMarketCurve.Gender.Female, badNames, block.timestamp + 30 days, badProofs
        );
    }

    event NamesMerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event NameManuallyApproved(string name);

    function test_Events() public {
        bytes32 newRoot = bytes32(uint256(42));

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit NamesMerkleRootUpdated(merkleRoot, newRoot);
        market.setNamesMerkleRoot(newRoot);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit NameManuallyApproved("TestName");
        market.approveNameManually("TestName");
    }
}
