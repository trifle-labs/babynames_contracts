// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/**
 * @notice Seeds the deployed BabyNameMarket with categories based on 2024 SSA top 10.
 *
 * Categories per gender per year:
 *   - #1, #2, #3 single-name predictions (10 pools each)
 *   - Exacta: 1st+2nd combination (position=12, 90 pools - all ordered pairs)
 *   - Trifecta: 1st+2nd+3rd combination (position=123, 720 pools - all ordered triples)
 *
 * Usage:
 *   source .env && forge script script/SeedCategories.s.sol:SeedCategories \
 *     --rpc-url <RPC_URL> --broadcast -vvv
 *
 * Env vars:
 *   PRIVATE_KEY    - deployer/sender private key
 *   MARKET_ADDRESS - deployed BabyNameMarket address
 */
contract SeedCategories is Script {

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        // 2024 SSA top 10 girls
        string[10] memory girls = [
            "Olivia", "Emma", "Amelia", "Charlotte", "Mia",
            "Sophia", "Isabella", "Evelyn", "Ava", "Sofia"
        ];

        // 2024 SSA top 10 boys
        string[10] memory boys = [
            "Liam", "Noah", "Oliver", "Theodore", "James",
            "Henry", "Mateo", "Elijah", "Lucas", "William"
        ];

        // Deadline: May 15 2026 (SSA release ~Mother's Day)
        uint256 deadline2025 = 1778918400; // 2026-05-15T00:00:00Z
        uint256 deadline2026 = 1810454400; // 2027-05-15T00:00:00Z

        vm.startBroadcast(deployerKey);

        // ==========================================
        // 2025 predictions
        // ==========================================

        // Single positions: #1, #2, #3
        _createSingleCategory(market, 2025, 1, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createSingleCategory(market, 2025, 1, BabyNameMarket.Gender.Male, boys, deadline2025);
        _createSingleCategory(market, 2025, 2, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createSingleCategory(market, 2025, 2, BabyNameMarket.Gender.Male, boys, deadline2025);
        _createSingleCategory(market, 2025, 3, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createSingleCategory(market, 2025, 3, BabyNameMarket.Gender.Male, boys, deadline2025);

        // Exacta: position=12 means predict 1st AND 2nd in order
        _createExactaCategory(market, 2025, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createExactaCategory(market, 2025, BabyNameMarket.Gender.Male, boys, deadline2025);

        // Trifecta: position=123 means predict 1st, 2nd AND 3rd in order
        _createTrifectaCategory(market, 2025, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createTrifectaCategory(market, 2025, BabyNameMarket.Gender.Male, boys, deadline2025);

        // ==========================================
        // 2026 predictions
        // ==========================================

        _createSingleCategory(market, 2026, 1, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createSingleCategory(market, 2026, 1, BabyNameMarket.Gender.Male, boys, deadline2026);
        _createSingleCategory(market, 2026, 2, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createSingleCategory(market, 2026, 2, BabyNameMarket.Gender.Male, boys, deadline2026);
        _createSingleCategory(market, 2026, 3, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createSingleCategory(market, 2026, 3, BabyNameMarket.Gender.Male, boys, deadline2026);

        _createExactaCategory(market, 2026, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createExactaCategory(market, 2026, BabyNameMarket.Gender.Male, boys, deadline2026);

        _createTrifectaCategory(market, 2026, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createTrifectaCategory(market, 2026, BabyNameMarket.Gender.Male, boys, deadline2026);

        vm.stopBroadcast();

        console.log("Seeded categories complete");
        console.log("Per year: 6 single + 2 exacta + 2 trifecta = 10 categories");
        console.log("Total: 20 categories across 2025 + 2026");
    }

    function _createSingleCategory(
        BabyNameMarket market,
        uint256 year,
        uint256 position,
        BabyNameMarket.Gender gender,
        string[10] memory names,
        uint256 deadline
    ) internal {
        string[] memory nameList = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            nameList[i] = names[i];
        }
        market.createCategory(year, position, gender, nameList, deadline);
    }

    function _createExactaCategory(
        BabyNameMarket market,
        uint256 year,
        BabyNameMarket.Gender gender,
        string[10] memory names,
        uint256 deadline
    ) internal {
        // Build all ordered pairs: 10 * 9 = 90
        // Create with first 2, then add the rest
        string[] memory firstTwo = new string[](2);
        firstTwo[0] = string.concat(names[0], " / ", names[1]);
        firstTwo[1] = string.concat(names[0], " / ", names[2]);
        uint256 catId = market.createCategory(year, 12, gender, firstTwo, deadline);

        // Add remaining 88 pairs
        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = 0; j < 10; j++) {
                if (i == j) continue;
                // Skip the two we already created
                if (i == 0 && j == 1) continue;
                if (i == 0 && j == 2) continue;

                string memory pairName = string.concat(names[i], " / ", names[j]);
                market.addNameToCategory(catId, pairName);
            }
        }
    }

    function _createTrifectaCategory(
        BabyNameMarket market,
        uint256 year,
        BabyNameMarket.Gender gender,
        string[10] memory names,
        uint256 deadline
    ) internal {
        // Build all ordered triples: 10 * 9 * 8 = 720
        // Create with first 2, then add the rest
        string[] memory firstTwo = new string[](2);
        firstTwo[0] = string.concat(names[0], " / ", names[1], " / ", names[2]);
        firstTwo[1] = string.concat(names[0], " / ", names[1], " / ", names[3]);
        uint256 catId = market.createCategory(year, 123, gender, firstTwo, deadline);

        // Add remaining 718 triples
        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = 0; j < 10; j++) {
                if (j == i) continue;
                for (uint256 k = 0; k < 10; k++) {
                    if (k == i || k == j) continue;
                    // Skip the two we already created
                    if (i == 0 && j == 1 && k == 2) continue;
                    if (i == 0 && j == 1 && k == 3) continue;

                    string memory triName = string.concat(names[i], " / ", names[j], " / ", names[k]);
                    market.addNameToCategory(catId, triName);
                }
            }
        }
    }
}
