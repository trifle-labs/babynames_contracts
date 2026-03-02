// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/// @notice Light seed: just single-position categories (#1, #2, #3) for 2025 + 2026
contract SeedLight is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        string[10] memory girls = [
            "Olivia", "Emma", "Amelia", "Charlotte", "Mia",
            "Sophia", "Isabella", "Evelyn", "Ava", "Sofia"
        ];
        string[10] memory boys = [
            "Liam", "Noah", "Oliver", "Theodore", "James",
            "Henry", "Mateo", "Elijah", "Lucas", "William"
        ];

        uint256 deadline2025 = 1778918400; // 2026-05-15
        uint256 deadline2026 = 1810454400; // 2027-05-15

        vm.startBroadcast(deployerKey);

        // 2025: #1, #2, #3 for each gender
        _create(market, 2025, 1, BabyNameMarket.Gender.Female, girls, deadline2025);
        _create(market, 2025, 1, BabyNameMarket.Gender.Male, boys, deadline2025);
        _create(market, 2025, 2, BabyNameMarket.Gender.Female, girls, deadline2025);
        _create(market, 2025, 2, BabyNameMarket.Gender.Male, boys, deadline2025);
        _create(market, 2025, 3, BabyNameMarket.Gender.Female, girls, deadline2025);
        _create(market, 2025, 3, BabyNameMarket.Gender.Male, boys, deadline2025);

        // 2026: #1, #2, #3 for each gender
        _create(market, 2026, 1, BabyNameMarket.Gender.Female, girls, deadline2026);
        _create(market, 2026, 1, BabyNameMarket.Gender.Male, boys, deadline2026);
        _create(market, 2026, 2, BabyNameMarket.Gender.Female, girls, deadline2026);
        _create(market, 2026, 2, BabyNameMarket.Gender.Male, boys, deadline2026);
        _create(market, 2026, 3, BabyNameMarket.Gender.Female, girls, deadline2026);
        _create(market, 2026, 3, BabyNameMarket.Gender.Male, boys, deadline2026);

        vm.stopBroadcast();

        console.log("Seeded 12 single-position categories (60 pools each gender)");
    }

    function _create(
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
        market.createCategory(year, position, 0, gender, nameList, deadline);
    }
}
