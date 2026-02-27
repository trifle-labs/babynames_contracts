// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/**
 * @notice Adds expanded categories to an already-seeded contract.
 *         Assumes categories 1-4 (#1 girl/boy 2025/2026) already exist.
 *         Adds: #2, #3, exacta, trifecta for both genders and years.
 */
contract SeedExpanded is Script {

    string[10] girls = [
        "Olivia", "Emma", "Amelia", "Charlotte", "Mia",
        "Sophia", "Isabella", "Evelyn", "Ava", "Sofia"
    ];

    string[10] boys = [
        "Liam", "Noah", "Oliver", "Theodore", "James",
        "Henry", "Mateo", "Elijah", "Lucas", "William"
    ];

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        uint256 deadline2025 = 1778918400;
        uint256 deadline2026 = 1810454400;

        vm.startBroadcast(deployerKey);

        // ---- 2025: #2 and #3 singles ----
        _createSingle(market, 2025, 2, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createSingle(market, 2025, 2, BabyNameMarket.Gender.Male, boys, deadline2025);
        _createSingle(market, 2025, 3, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createSingle(market, 2025, 3, BabyNameMarket.Gender.Male, boys, deadline2025);

        // ---- 2026: #2 and #3 singles ----
        _createSingle(market, 2026, 2, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createSingle(market, 2026, 2, BabyNameMarket.Gender.Male, boys, deadline2026);
        _createSingle(market, 2026, 3, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createSingle(market, 2026, 3, BabyNameMarket.Gender.Male, boys, deadline2026);

        // ---- 2025 + 2026: Exacta ----
        _createExacta(market, 2025, BabyNameMarket.Gender.Female, girls, deadline2025);
        _createExacta(market, 2025, BabyNameMarket.Gender.Male, boys, deadline2025);
        _createExacta(market, 2026, BabyNameMarket.Gender.Female, girls, deadline2026);
        _createExacta(market, 2026, BabyNameMarket.Gender.Male, boys, deadline2026);

        vm.stopBroadcast();

        console.log("Seeded singles (#2, #3) and exacta categories");
        console.log("Trifecta must be seeded separately due to tx count");
    }

    function _createSingle(
        BabyNameMarket market,
        uint256 year,
        uint256 position,
        BabyNameMarket.Gender gender,
        string[10] storage names,
        uint256 deadline
    ) internal {
        string[] memory nameList = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            nameList[i] = names[i];
        }
        market.createCategory(year, position, gender, nameList, deadline);
    }

    function _createExacta(
        BabyNameMarket market,
        uint256 year,
        BabyNameMarket.Gender gender,
        string[10] storage names,
        uint256 deadline
    ) internal {
        // 10 * 9 = 90 ordered pairs
        string[] memory firstTwo = new string[](2);
        firstTwo[0] = string.concat(names[0], " / ", names[1]);
        firstTwo[1] = string.concat(names[0], " / ", names[2]);
        uint256 catId = market.createCategory(year, 12, gender, firstTwo, deadline);

        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = 0; j < 10; j++) {
                if (i == j) continue;
                if (i == 0 && j == 1) continue;
                if (i == 0 && j == 2) continue;
                market.addNameToCategory(catId, string.concat(names[i], " / ", names[j]));
            }
        }
    }
}
