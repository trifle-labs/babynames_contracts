// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";
import "./helpers/ChainConfig.sol";

contract DeployBabyNameMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address resolver = vm.envAddress("RESOLVER_ADDRESS");

        ChainConfig.Config memory config = ChainConfig.get();

        vm.startBroadcast(deployerPrivateKey);

        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        BabyNameMarket market = new BabyNameMarket(resolver, tokenAddress);

        vm.stopBroadcast();

        // Write deployment artifact
        string memory json = string.concat(
            '{"address":"', vm.toString(address(market)),
            '","resolver":"', vm.toString(resolver),
            '","token":"', vm.toString(tokenAddress),
            '","chainId":', vm.toString(block.chainid),
            ',"chainName":"', config.name,
            '","deployer":"', vm.toString(vm.addr(deployerPrivateKey)),
            '"}'
        );
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeFile(path, json);

        console.log("BabyNameMarket deployed to:", address(market));
        console.log("Chain:", config.name);
        console.log("Resolver:", resolver);
    }
}
