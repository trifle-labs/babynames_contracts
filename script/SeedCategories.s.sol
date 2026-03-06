// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/**
 * @notice Seeds the deployed BabyNameMarket with 2025 prediction categories.
 *
 * Categories (10 total):
 *   Per gender (Female + Male):
 *   - #1 Most Popular (10 pools, single-position)
 *   - #2 Most Popular (10 pools, single-position)
 *   - #3 Most Popular (10 pools, single-position)
 *   - Top 3 (10 pools = top 10 names, topN — multiple winners)
 *   - Top 10 (25 pools = top 25 names, topN — multiple winners)
 *
 * Usage:
 *   source .env && forge script script/SeedCategories.s.sol:SeedCategories \
 *     --rpc-url <RPC_URL> --broadcast -vvv
 */
contract SeedCategories is Script {

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        // Deadline: May 15 2026 (SSA release ~Mother's Day)
        uint256 deadline = 1778918400; // 2026-05-15T00:00:00Z

        bytes32[][] memory emptyProofs = new bytes32[][](0);

        vm.startBroadcast(deployerKey);

        // ---- Girls ----
        string[] memory girlsTop10 = _girlsTop10();
        string[] memory girlsTop25 = _girlsTop25();

        // #1, #2, #3 single-position (categoryType=0)
        market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Female, girlsTop10, deadline, emptyProofs);
        market.createCategory(2025, 2, 0, BabyNameMarket.Gender.Female, girlsTop10, deadline, emptyProofs);
        market.createCategory(2025, 3, 0, BabyNameMarket.Gender.Female, girlsTop10, deadline, emptyProofs);

        // Top 3 (categoryType=3, position=3, 10 pools)
        market.createCategory(2025, 3, 3, BabyNameMarket.Gender.Female, girlsTop10, deadline, emptyProofs);

        // Top 10 (categoryType=3, position=10, 25 pools)
        market.createCategory(2025, 10, 3, BabyNameMarket.Gender.Female, girlsTop25, deadline, emptyProofs);

        // ---- Boys ----
        string[] memory boysTop10 = _boysTop10();
        string[] memory boysTop25 = _boysTop25();

        // #1, #2, #3 single-position (categoryType=0)
        market.createCategory(2025, 1, 0, BabyNameMarket.Gender.Male, boysTop10, deadline, emptyProofs);
        market.createCategory(2025, 2, 0, BabyNameMarket.Gender.Male, boysTop10, deadline, emptyProofs);
        market.createCategory(2025, 3, 0, BabyNameMarket.Gender.Male, boysTop10, deadline, emptyProofs);

        // Top 3 (categoryType=3, position=3, 10 pools)
        market.createCategory(2025, 3, 3, BabyNameMarket.Gender.Male, boysTop10, deadline, emptyProofs);

        // Top 10 (categoryType=3, position=10, 25 pools)
        market.createCategory(2025, 10, 3, BabyNameMarket.Gender.Male, boysTop25, deadline, emptyProofs);

        vm.stopBroadcast();

        console.log("Seeded 10 categories for 2025:");
        console.log("  6 single-position (#1, #2, #3 x 2 genders)");
        console.log("  2 top-3 (10 pools each)");
        console.log("  2 top-10 (25 pools each)");
    }

    // 2024 SSA top 10 girls
    function _girlsTop10() internal pure returns (string[] memory names) {
        names = new string[](10);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Amelia";
        names[3] = "Charlotte";
        names[4] = "Mia";
        names[5] = "Sophia";
        names[6] = "Isabella";
        names[7] = "Evelyn";
        names[8] = "Ava";
        names[9] = "Sofia";
    }

    // 2024 SSA top 25 girls
    function _girlsTop25() internal pure returns (string[] memory names) {
        names = new string[](25);
        names[0] = "Olivia";
        names[1] = "Emma";
        names[2] = "Amelia";
        names[3] = "Charlotte";
        names[4] = "Mia";
        names[5] = "Sophia";
        names[6] = "Isabella";
        names[7] = "Evelyn";
        names[8] = "Ava";
        names[9] = "Sofia";
        names[10] = "Camila";
        names[11] = "Harper";
        names[12] = "Luna";
        names[13] = "Eleanor";
        names[14] = "Violet";
        names[15] = "Aurora";
        names[16] = "Elizabeth";
        names[17] = "Eliana";
        names[18] = "Hazel";
        names[19] = "Chloe";
        names[20] = "Ellie";
        names[21] = "Nora";
        names[22] = "Gianna";
        names[23] = "Lily";
        names[24] = "Emily";
    }

    // 2024 SSA top 10 boys
    function _boysTop10() internal pure returns (string[] memory names) {
        names = new string[](10);
        names[0] = "Liam";
        names[1] = "Noah";
        names[2] = "Oliver";
        names[3] = "Theodore";
        names[4] = "James";
        names[5] = "Henry";
        names[6] = "Mateo";
        names[7] = "Elijah";
        names[8] = "Lucas";
        names[9] = "William";
    }

    // 2024 SSA top 25 boys
    function _boysTop25() internal pure returns (string[] memory names) {
        names = new string[](25);
        names[0] = "Liam";
        names[1] = "Noah";
        names[2] = "Oliver";
        names[3] = "Theodore";
        names[4] = "James";
        names[5] = "Henry";
        names[6] = "Mateo";
        names[7] = "Elijah";
        names[8] = "Lucas";
        names[9] = "William";
        names[10] = "Benjamin";
        names[11] = "Levi";
        names[12] = "Ezra";
        names[13] = "Sebastian";
        names[14] = "Jack";
        names[15] = "Daniel";
        names[16] = "Samuel";
        names[17] = "Michael";
        names[18] = "Ethan";
        names[19] = "Asher";
        names[20] = "John";
        names[21] = "Hudson";
        names[22] = "Luca";
        names[23] = "Leo";
        names[24] = "Elias";
    }
}
