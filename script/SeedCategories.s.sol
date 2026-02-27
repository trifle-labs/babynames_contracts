// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/**
 * @notice Seeds the deployed BabyNameMarket with common categories
 *         based on 2024 SSA top 10 results as starting predictions for 2025.
 *
 * Usage:
 *   source .env && forge script script/SeedCategories.s.sol:SeedCategories \
 *     --rpc-url <RPC_URL> --broadcast
 *
 * Env vars:
 *   PRIVATE_KEY - deployer/sender private key
 *   MARKET_ADDRESS - deployed BabyNameMarket address
 */
contract SeedCategories is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        // Deadline: May 15, 2026 (SSA typically releases around Mother's Day)
        uint256 deadline = 1778918400; // 2026-05-15T00:00:00Z

        vm.startBroadcast(deployerKey);

        // ============ #1 Girl Name 2025 ============
        // Based on 2024 top 10 girls + plausible contenders
        string[] memory girlNames1 = new string[](10);
        girlNames1[0] = "Olivia";
        girlNames1[1] = "Emma";
        girlNames1[2] = "Amelia";
        girlNames1[3] = "Charlotte";
        girlNames1[4] = "Mia";
        girlNames1[5] = "Sophia";
        girlNames1[6] = "Isabella";
        girlNames1[7] = "Evelyn";
        girlNames1[8] = "Ava";
        girlNames1[9] = "Sofia";
        market.createCategory(2025, 1, BabyNameMarket.Gender.Female, girlNames1, deadline);

        // ============ #1 Boy Name 2025 ============
        // Based on 2024 top 10 boys + plausible contenders
        string[] memory boyNames1 = new string[](10);
        boyNames1[0] = "Liam";
        boyNames1[1] = "Noah";
        boyNames1[2] = "Oliver";
        boyNames1[3] = "Theodore";
        boyNames1[4] = "James";
        boyNames1[5] = "Henry";
        boyNames1[6] = "Mateo";
        boyNames1[7] = "Elijah";
        boyNames1[8] = "Lucas";
        boyNames1[9] = "William";
        market.createCategory(2025, 1, BabyNameMarket.Gender.Male, boyNames1, deadline);

        // ============ #1 Girl Name 2026 ============
        // Same names, longer-range prediction
        uint256 deadline2027 = 1810454400; // 2027-05-15T00:00:00Z
        market.createCategory(2026, 1, BabyNameMarket.Gender.Female, girlNames1, deadline2027);

        // ============ #1 Boy Name 2026 ============
        market.createCategory(2026, 1, BabyNameMarket.Gender.Male, boyNames1, deadline2027);

        vm.stopBroadcast();

        console.log("Seeded 4 categories (2 per gender, 2025 + 2026)");
        console.log("Girl #1 2025: categoryId 1");
        console.log("Boy #1 2025: categoryId 2");
        console.log("Girl #1 2026: categoryId 3");
        console.log("Boy #1 2026: categoryId 4");
    }
}
