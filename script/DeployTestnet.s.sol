// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BabyNameMarket.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Dummy ERC20 for testnet deployments
contract TestUSDC is ERC20 {
    uint8 private _dec;

    constructor() ERC20("Test USDC", "tUSDC") {
        _dec = 6;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DeployTestnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address resolver = vm.envAddress("RESOLVER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy dummy USDC
        TestUSDC token = new TestUSDC();
        console.log("TestUSDC deployed to:", address(token));

        // 2. Mint 1,000,000 tUSDC to deployer
        token.mint(deployer, 1_000_000 * 1e6);
        console.log("Minted 1,000,000 tUSDC to deployer:", deployer);

        // 3. Deploy BabyNameMarket
        BabyNameMarket market = new BabyNameMarket(resolver, address(token));
        console.log("BabyNameMarket deployed to:", address(market));

        vm.stopBroadcast();

        // Write deployment artifact
        string memory json = string.concat(
            '{"address":"', vm.toString(address(market)),
            '","resolver":"', vm.toString(resolver),
            '","token":"', vm.toString(address(token)),
            '","chainId":', vm.toString(block.chainid),
            ',"chainName":"base_sepolia"',
            ',"deployer":"', vm.toString(deployer),
            '"}'
        );
        vm.writeFile("deployments/84532.json", json);
    }
}
