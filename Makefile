-include .env

.PHONY: build test coverage gas snapshot clean deploy export-abi anvil

# Build
build:
	forge build

clean:
	forge clean

# Test
test:
	forge test -vvv

test-ci:
	FOUNDRY_PROFILE=ci forge test -vvv

coverage:
	forge coverage

gas:
	forge snapshot

# ABI export
export-abi:
	@mkdir -p abi
	forge inspect BabyNameMarket abi > abi/BabyNameMarket.json
	@echo "ABI exported to abi/BabyNameMarket.json"

# Local dev
anvil:
	anvil

deploy-local:
	forge script script/Deploy.s.sol:DeployBabyNameMarket --rpc-url http://127.0.0.1:8545 --broadcast

setup-local:
	forge script script/SetupCategories.s.sol:SetupCategories --rpc-url http://127.0.0.1:8545 --broadcast

# Mainnet
deploy-mainnet:
	forge script script/Deploy.s.sol:DeployBabyNameMarket --rpc-url $(ETH_RPC_URL) --broadcast --verify

# Sepolia
deploy-sepolia:
	forge script script/Deploy.s.sol:DeployBabyNameMarket --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify

# Base
deploy-base:
	forge script script/Deploy.s.sol:DeployBabyNameMarket --rpc-url $(BASE_RPC_URL) --broadcast --verify

# Base Sepolia
deploy-base-sepolia:
	forge script script/Deploy.s.sol:DeployBabyNameMarket --rpc-url $(BASE_SEPOLIA_RPC_URL) --broadcast --verify
