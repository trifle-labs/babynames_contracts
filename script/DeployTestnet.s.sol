// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PredictionMarket.sol";
import "../src/Vault.sol";
import "../src/OutcomeToken.sol";
import "../src/RewardDistributor.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice Minimal ERC20 for testnet deployments (open mint)
contract TestUSDC is ERC20 {
    function name() public pure override returns (string memory) {
        return "Test USDC";
    }

    function symbol() public pure override returns (string memory) {
        return "tUSDC";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DeployTestnet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TestUSDC and mint to deployer
        TestUSDC usdc = new TestUSDC();
        usdc.mint(deployer, 10_000_000 * 1e6); // 10M tUSDC
        console.log("TestUSDC:", address(usdc));

        // 2. Deploy PredictionMarket
        PredictionMarket pm = new PredictionMarket();
        pm.initialize(address(usdc));
        // Set market creation fee to $5/outcome
        pm.grantRoles(deployer, pm.PROTOCOL_MANAGER_ROLE());
        pm.setMarketCreationFee(5e6);
        console.log("PredictionMarket:", address(pm));

        // 3. Deploy Vault
        //    - surplusRecipient = deployer (test treasury)
        //    - defaultOracle = deployer (manual resolution for testing)
        //    - defaultLaunchThreshold = $20 (low for testing)
        //    - defaultDeadlineDuration = 7 days
        Vault vault = new Vault(
            address(pm),
            deployer,       // surplusRecipient
            deployer,       // feeSource
            deployer,       // defaultOracle
            20e6,           // defaultLaunchThreshold ($20)
            7 days,         // defaultDeadlineDuration
            deployer        // owner
        );
        console.log("Vault:", address(vault));

        // 4. Grant Vault the MARKET_CREATOR_ROLE on PredictionMarket
        pm.grantMarketCreatorRole(address(vault));

        // 5. Fund Vault with USDC for market creation fees
        //    At $5/outcome, fee_min ≈ $0.70, so $100 covers ~140 markets
        usdc.mint(address(vault), 100e6);
        console.log("Vault funded with 100 tUSDC for creation fees");

        // 6. Deploy RewardDistributor
        RewardDistributor rd = new RewardDistributor(address(usdc), deployer);
        console.log("RewardDistributor:", address(rd));

        vm.stopBroadcast();

        // Write deployment artifact
        string memory chainIdStr = vm.toString(block.chainid);
        string memory json = string.concat(
            '{"PredictionMarket":"', vm.toString(address(pm)),
            '","Vault":"', vm.toString(address(vault)),
            '","TestUSDC":"', vm.toString(address(usdc)),
            '","RewardDistributor":"', vm.toString(address(rd)),
            '","OutcomeTokenImpl":"', vm.toString(pm.outcomeTokenImplementation()),
            '","chainId":', chainIdStr,
            ',"deployer":"', vm.toString(deployer),
            '","oracle":"', vm.toString(deployer),
            '","surplusRecipient":"', vm.toString(deployer),
            '"}'
        );
        string memory path = string.concat("deployments/", chainIdStr, ".json");
        vm.writeFile(path, json);
        console.log("Deployment artifact written to", path);
    }
}
