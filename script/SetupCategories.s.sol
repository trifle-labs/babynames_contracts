// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";
import "./helpers/ChainConfig.sol";

contract SetupCategories is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address marketAddress = vm.envAddress("MARKET_ADDRESS");

        BabyNameMarket market = BabyNameMarket(marketAddress);
        ChainConfig.Config memory config = ChainConfig.get();

        vm.startBroadcast(deployerPrivateKey);

        // 2025 Girls #1
        string[] memory girlsNames = new string[](10);
        girlsNames[0] = "Olivia";
        girlsNames[1] = "Emma";
        girlsNames[2] = "Charlotte";
        girlsNames[3] = "Amelia";
        girlsNames[4] = "Sophia";
        girlsNames[5] = "Mia";
        girlsNames[6] = "Isabella";
        girlsNames[7] = "Ava";
        girlsNames[8] = "Evelyn";
        girlsNames[9] = "Luna";

        uint256 deadline = block.timestamp + config.deadlineOffset;

        uint256 girlsCategory = market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Female,
            girlsNames,
            deadline
        );
        console.log("Girls #1 2025 category:", girlsCategory);

        // 2025 Boys #1
        string[] memory boysNames = new string[](10);
        boysNames[0] = "Liam";
        boysNames[1] = "Noah";
        boysNames[2] = "Oliver";
        boysNames[3] = "James";
        boysNames[4] = "Elijah";
        boysNames[5] = "William";
        boysNames[6] = "Henry";
        boysNames[7] = "Lucas";
        boysNames[8] = "Benjamin";
        boysNames[9] = "Theodore";

        uint256 boysCategory = market.createCategory(
            2025,
            1,
            BabyNameMarket.Gender.Male,
            boysNames,
            deadline
        );
        console.log("Boys #1 2025 category:", boysCategory);

        vm.stopBroadcast();
    }
}
