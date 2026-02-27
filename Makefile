-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil size

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install openzeppelin/openzeppelin-contracts@v5.0.2 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

size:; forge build --sizes

snapshot :; forge snapshot

format :; forge fmt

coverage :; forge coverage

coverage-report :; forge coverage --report lcov && genhtml lcov.info -o coverage && cd coverage && python3 -m http.server 8000

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -vvvv
NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY_USER) --broadcast -vvvv

# Set NETWORK_ARGS based on the network specified in ARGS for deployment
# make deploy ARGS="--network sepolia"
ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY_DEPLOYER) --broadcast --gas-price 50000000000 --slow --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network mainnet,$(ARGS)),--network mainnet)
	NETWORK_ARGS := --rpc-url $(MAINNET_RPC_URL) --private-key $(PRIVATE_KEY_DEPLOYER) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

# quick deploy and interaction scripts for testnet testing

deploy-script:
	@forge script script/1a_DeployScript.s.sol:DeployScript $(NETWORK_ARGS)

deploy-configs:
	@forge script script/1b_ConfigureMocks.s.sol:ConfigureMocks $(NETWORK_ARGS)

deploy-adapters:
	@forge script script/2_DeployAndRegisterAdapter.s.sol:DeployAndRegisterAdapter $(NETWORK_ARGS)

supply: 
	@forge script script/3_SupplyToLiidia.s.sol:SupplyToLiidia $(NETWORK_ARGS)

borrow:
	@forge script script/4_BorrowFromLiidia.s.sol:BorrowFromLiidia $(NETWORK_ARGS)

drop-price:
	@forge script script/5_DropAssetPrices.s.sol:DropAssetPrices $(NETWORK_ARGS)

deploy-liiquidate:
	@forge script script/DeployLiiquidate.s.sol:DeployLiiquidate $(NETWORK_ARGS)

man-liiquidate:
	@forge script script/ManualLiiquidate.s.sol:ManualLiiquidate $(NETWORK_ARGS)

# quick deploy and interaction scripts for gas estimation on Sepolia

sim-deploy-script:
	@forge script script/1a_DeployScript.s.sol:DeployScript --rpc-url $(SEPOLIA_RPC_URL)

sim-deploy-configs:
	@forge script script/1b_ConfigureMocks.s.sol:ConfigureMocks --rpc-url $(SEPOLIA_RPC_URL)

sim-deploy-adapters:
	@forge script script/2_DeployAndRegisterAdapter.s.sol:DeployAndRegisterAdapter --rpc-url $(SEPOLIA_RPC_URL)

sim-supply:
	@forge script script/3_SupplyToLiidia.s.sol:SupplyToLiidia --rpc-url $(SEPOLIA_RPC_URL)

sim-borrow:
	@forge script script/4_BorrowFromLiidia.s.sol:BorrowFromLiidia --rpc-url $(SEPOLIA_RPC_URL)

sim-drop-price:
	@forge script script/5_DropAssetPrices.s.sol:DropAssetPrices --rpc-url $(SEPOLIA_RPC_URL)

sim-deploy-liiquidate:
	@forge script script/DeployLiiquidate.s.sol:DeployLiiquidate --rpc-url $(SEPOLIA_RPC_URL)

sim-man-liiquidate:
	@forge script script/ManualLiiquidate.s.sol:ManualLiiquidate --rpc-url $(SEPOLIA_RPC_URL)
