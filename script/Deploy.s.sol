// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";
import "../src/BetSlipSVG.sol";
import "../src/BetSlipLogo.sol";
import "./helpers/ChainConfig.sol";

contract DeployBabyNameMarket is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address resolver = vm.envAddress("RESOLVER_ADDRESS");

        ChainConfig.Config memory config = ChainConfig.get();

        vm.startBroadcast(deployerPrivateKey);

        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        BetSlipLogo logoContract = new BetSlipLogo();
        BetSlipSVG renderer = new BetSlipSVG(address(logoContract));
        BabyNameMarket market = new BabyNameMarket(resolver, tokenAddress, address(renderer));

        vm.stopBroadcast();

        // Write deployment artifact
        address deployer = vm.addr(deployerPrivateKey);
        string memory part1 = string.concat(
            '{"address":"', vm.toString(address(market)),
            '","resolver":"', vm.toString(resolver),
            '","token":"', vm.toString(tokenAddress), '"'
        );
        string memory part2 = string.concat(
            ',"chainId":', vm.toString(block.chainid),
            ',"chainName":"', config.name,
            '","deployer":"', vm.toString(deployer), '"}'
        );
        string memory json = string.concat(part1, part2);
        string memory path = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeFile(path, json);

        console.log("BabyNameMarket deployed to:", address(market));
        console.log("Chain:", config.name);
        console.log("Resolver:", resolver);
    }
}
