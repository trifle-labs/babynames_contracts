// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";

/// @notice Set the names merkle root on a deployed BabyNameMarket contract.
/// Usage:
///   MERKLE_ROOT=$(cat data/merkle-root.txt) forge script script/SetMerkleRoot.s.sol \
///     --rpc-url <RPC_URL> --broadcast -vvv
contract SetMerkleRoot is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        bytes32 root = vm.envBytes32("MERKLE_ROOT");

        BabyNameMarket market = BabyNameMarket(marketAddr);

        vm.startBroadcast(deployerKey);
        market.setNamesMerkleRoot(root);
        vm.stopBroadcast();

        console.log("Merkle root set to:");
        console.logBytes32(root);
    }
}
