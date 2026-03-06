// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @notice Seed every pool with small bet amounts proportional to SSA popularity rankings.
///         With 1:1 pricing, tiny amounts establish the same odds ratios (~$1 per category).
contract SeedBets is Script {
    // Buy amounts in tUSDC (6 decimals) — proportional to real SSA popularity
    // Girls top 25 (~$1.50 total for top-10 categories, ~$2.50 for top-25)
    function girlAmount(string memory name) internal pure returns (uint256) {
        bytes32 h = keccak256(bytes(name));
        // Top 10
        if (h == keccak256("Olivia"))    return 150_000;
        if (h == keccak256("Emma"))      return 120_000;
        if (h == keccak256("Amelia"))    return 110_000;
        if (h == keccak256("Charlotte")) return 100_000;
        if (h == keccak256("Mia"))       return  90_000;
        if (h == keccak256("Sophia"))    return  80_000;
        if (h == keccak256("Isabella"))  return  70_000;
        if (h == keccak256("Evelyn"))    return  60_000;
        if (h == keccak256("Ava"))       return  50_000;
        if (h == keccak256("Sofia"))     return  40_000;
        // 11-25
        if (h == keccak256("Camila"))    return  38_000;
        if (h == keccak256("Harper"))    return  36_000;
        if (h == keccak256("Luna"))      return  34_000;
        if (h == keccak256("Eleanor"))   return  32_000;
        if (h == keccak256("Violet"))    return  30_000;
        if (h == keccak256("Aurora"))    return  28_000;
        if (h == keccak256("Elizabeth")) return  26_000;
        if (h == keccak256("Eliana"))    return  24_000;
        if (h == keccak256("Hazel"))     return  22_000;
        if (h == keccak256("Chloe"))     return  20_000;
        if (h == keccak256("Ellie"))     return  18_000;
        if (h == keccak256("Nora"))      return  16_000;
        if (h == keccak256("Gianna"))    return  14_000;
        if (h == keccak256("Lily"))      return  12_000;
        if (h == keccak256("Emily"))     return  10_000;
        return 0;
    }

    // Boys top 25
    function boyAmount(string memory name) internal pure returns (uint256) {
        bytes32 h = keccak256(bytes(name));
        // Top 10
        if (h == keccak256("Liam"))      return 150_000;
        if (h == keccak256("Noah"))      return 120_000;
        if (h == keccak256("Oliver"))    return 110_000;
        if (h == keccak256("Theodore"))  return 100_000;
        if (h == keccak256("James"))     return  90_000;
        if (h == keccak256("Henry"))     return  80_000;
        if (h == keccak256("Mateo"))     return  70_000;
        if (h == keccak256("Elijah"))    return  60_000;
        if (h == keccak256("Lucas"))     return  50_000;
        if (h == keccak256("William"))   return  40_000;
        // 11-25
        if (h == keccak256("Benjamin"))  return  38_000;
        if (h == keccak256("Levi"))      return  36_000;
        if (h == keccak256("Ezra"))      return  34_000;
        if (h == keccak256("Sebastian")) return  32_000;
        if (h == keccak256("Jack"))      return  30_000;
        if (h == keccak256("Daniel"))    return  28_000;
        if (h == keccak256("Samuel"))    return  26_000;
        if (h == keccak256("Michael"))   return  24_000;
        if (h == keccak256("Ethan"))     return  22_000;
        if (h == keccak256("Asher"))     return  20_000;
        if (h == keccak256("John"))      return  18_000;
        if (h == keccak256("Hudson"))    return  16_000;
        if (h == keccak256("Luca"))      return  14_000;
        if (h == keccak256("Leo"))       return  12_000;
        if (h == keccak256("Elias"))     return  10_000;
        return 0;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        address tokenAddr  = vm.envAddress("TOKEN_ADDRESS");

        BabyNameMarket market = BabyNameMarket(marketAddr);
        IERC20 token = IERC20(tokenAddr);
        uint256 nextCat = market.nextCategoryId();

        // Mint enough tUSDC for all bets (~10 categories at ~$1-2.50 each)
        uint256 mintAmount = 30e6;

        vm.startBroadcast(deployerKey);

        IMintable(tokenAddr).mint(msg.sender, mintAmount);
        token.approve(marketAddr, mintAmount);

        // Iterate all categories and buy into their pools
        for (uint256 catId = 0; catId < nextCat; catId++) {
            (
                ,           // year
                ,           // position
                uint8 categoryType,
                BabyNameMarket.Gender gender,
                ,           // totalCollateral
                ,           // poolCount
                bool resolved,
                ,           // winningPoolId
                ,           // prizePool
                ,           // deadline
                            // publicationTime
            ) = market.getCategoryInfo(catId);

            if (resolved) continue;

            // Only seed single-position and topN categories
            if (categoryType != 0 && categoryType != 3) continue;

            uint256[] memory poolIds = market.getCategoryPools(catId);

            for (uint256 i = 0; i < poolIds.length; i++) {
                (, string memory name, , ,) = market.getPoolInfo(poolIds[i]);

                uint256 amt = gender == BabyNameMarket.Gender.Female
                    ? girlAmount(name)
                    : boyAmount(name);

                if (amt == 0) continue;

                market.buy(poolIds[i], amt);
                console.log("  Bought %s for pool %s (%s)", amt, poolIds[i], name);
            }
        }

        vm.stopBroadcast();

        console.log("SeedBets complete");
    }
}
