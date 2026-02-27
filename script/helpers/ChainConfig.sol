// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ChainConfig {
    struct Config {
        address resolver;
        uint256 deadlineOffset; // seconds from deployment
        string name;
    }

    function get() internal view returns (Config memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            return Config({
                resolver: address(0), // Set via RESOLVER_ADDRESS env
                deadlineOffset: 120 days,
                name: "mainnet"
            });
        } else if (chainId == 8453) {
            return Config({
                resolver: address(0),
                deadlineOffset: 120 days,
                name: "base"
            });
        } else if (chainId == 11155111) {
            return Config({
                resolver: address(0),
                deadlineOffset: 30 days,
                name: "sepolia"
            });
        } else if (chainId == 84532) {
            return Config({
                resolver: address(0),
                deadlineOffset: 30 days,
                name: "base_sepolia"
            });
        } else {
            // Local / anvil
            return Config({
                resolver: address(0),
                deadlineOffset: 30 days,
                name: "local"
            });
        }
    }
}
