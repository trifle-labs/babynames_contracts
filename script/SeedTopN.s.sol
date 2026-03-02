// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/// @notice Seed Top 3 and Top 10 categories for 2025, both genders
contract SeedTopN is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        uint256 deadline2025 = 1778918400; // 2026-05-15

        string[] memory girls = new string[](10);
        girls[0] = "Olivia";
        girls[1] = "Emma";
        girls[2] = "Amelia";
        girls[3] = "Charlotte";
        girls[4] = "Mia";
        girls[5] = "Sophia";
        girls[6] = "Isabella";
        girls[7] = "Evelyn";
        girls[8] = "Ava";
        girls[9] = "Sofia";

        string[] memory boys = new string[](10);
        boys[0] = "Liam";
        boys[1] = "Noah";
        boys[2] = "Oliver";
        boys[3] = "Theodore";
        boys[4] = "James";
        boys[5] = "Henry";
        boys[6] = "Mateo";
        boys[7] = "Elijah";
        boys[8] = "Lucas";
        boys[9] = "William";

        vm.startBroadcast(deployerKey);

        // Top 3 categories
        market.createCategory(2025, 3, 3, BabyNameMarket.Gender.Female, girls, deadline2025);
        market.createCategory(2025, 3, 3, BabyNameMarket.Gender.Male, boys, deadline2025);

        // Top 10 categories
        market.createCategory(2025, 10, 3, BabyNameMarket.Gender.Female, girls, deadline2025);
        market.createCategory(2025, 10, 3, BabyNameMarket.Gender.Male, boys, deadline2025);

        vm.stopBroadcast();

        console.log("Seeded 4 Top N categories for 2025 (Top 3 + Top 10, both genders)");
    }
}
