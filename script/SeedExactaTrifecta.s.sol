// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/// @notice Seed Exacta (position=12) and Trifecta (position=123) categories for 2025
contract SeedExactaTrifecta is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        BabyNameMarket market = BabyNameMarket(marketAddr);

        uint256 deadline2025 = 1778918400; // 2026-05-15

        vm.startBroadcast(deployerKey);

        // Exacta Girl: top predicted combos
        string[] memory exactaGirls = new string[](3);
        exactaGirls[0] = "Olivia / Emma";
        exactaGirls[1] = "Olivia / Amelia";
        exactaGirls[2] = "Emma / Olivia";
        market.createCategory(2025, 12, BabyNameMarket.Gender.Female, exactaGirls, deadline2025);

        // Exacta Boy
        string[] memory exactaBoys = new string[](3);
        exactaBoys[0] = "Liam / Noah";
        exactaBoys[1] = "Noah / Liam";
        exactaBoys[2] = "Liam / Oliver";
        market.createCategory(2025, 12, BabyNameMarket.Gender.Male, exactaBoys, deadline2025);

        // Trifecta Girl
        string[] memory trifectaGirls = new string[](3);
        trifectaGirls[0] = "Olivia / Emma / Amelia";
        trifectaGirls[1] = "Olivia / Amelia / Emma";
        trifectaGirls[2] = "Emma / Olivia / Amelia";
        market.createCategory(2025, 123, BabyNameMarket.Gender.Female, trifectaGirls, deadline2025);

        // Trifecta Boy
        string[] memory trifectaBoys = new string[](3);
        trifectaBoys[0] = "Liam / Noah / Oliver";
        trifectaBoys[1] = "Noah / Liam / Oliver";
        trifectaBoys[2] = "Liam / Oliver / Noah";
        market.createCategory(2025, 123, BabyNameMarket.Gender.Male, trifectaBoys, deadline2025);

        vm.stopBroadcast();

        console.log("Seeded 4 Exacta/Trifecta categories for 2025");
    }
}
