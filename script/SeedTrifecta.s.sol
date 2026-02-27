// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/**
 * @notice Seeds trifecta categories (720 pools each).
 *         Separate script due to high transaction count.
 *
 * Run per gender/year:
 *   GENDER=0 YEAR=2025 forge script script/SeedTrifecta.s.sol:SeedTrifecta ...
 *   GENDER=1 YEAR=2025 forge script script/SeedTrifecta.s.sol:SeedTrifecta ...
 *   GENDER=0 YEAR=2026 forge script script/SeedTrifecta.s.sol:SeedTrifecta ...
 *   GENDER=1 YEAR=2026 forge script script/SeedTrifecta.s.sol:SeedTrifecta ...
 */
contract SeedTrifecta is Script {

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
        uint256 genderVal = vm.envUint("GENDER");  // 0=Female, 1=Male
        uint256 year = vm.envUint("YEAR");

        BabyNameMarket market = BabyNameMarket(marketAddr);
        BabyNameMarket.Gender gender = genderVal == 0
            ? BabyNameMarket.Gender.Female
            : BabyNameMarket.Gender.Male;

        string[10] storage names = genderVal == 0 ? girls : boys;

        uint256 deadline = year == 2025 ? uint256(1778918400) : uint256(1810454400);

        vm.startBroadcast(deployerKey);

        // Create category with first 2 triples
        string[] memory firstTwo = new string[](2);
        firstTwo[0] = string.concat(names[0], " / ", names[1], " / ", names[2]);
        firstTwo[1] = string.concat(names[0], " / ", names[1], " / ", names[3]);
        uint256 catId = market.createCategory(year, 123, gender, firstTwo, deadline);

        console.log("Created trifecta category:", catId);

        // Add remaining 718 triples
        uint256 count = 0;
        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = 0; j < 10; j++) {
                if (j == i) continue;
                for (uint256 k = 0; k < 10; k++) {
                    if (k == i || k == j) continue;
                    if (i == 0 && j == 1 && k == 2) continue;
                    if (i == 0 && j == 1 && k == 3) continue;

                    market.addNameToCategory(catId, string.concat(names[i], " / ", names[j], " / ", names[k]));
                    count++;
                }
            }
        }

        vm.stopBroadcast();

        console.log("Added triples:", count);
        console.log("Total pools:", count + 2);
    }
}
