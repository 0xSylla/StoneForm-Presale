-include .env

.PHONY: all clean build test snapshot format anvil deploy-bsc deploy-anvil install

all: clean build test

# Build & compile
build:; forge build
clean:; forge clean
test:; forge test
snapshot:; forge snapshot
format:; forge fmt

# Local node
anvil:; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# Deploy
deploy-bsc:
	@forge script script/DeployStoneFormAdvanced.s.sol:DeployStoneFormAdvanced --rpc-url $(BSC_RPC_URL) --account defaultKey --broadcast --verify --etherscan-api-key $(BSCSCAN_API_KEY) -vvvv

deploy-anvil:
	@forge script script/DeployStoneFormAdvanced.s.sol:DeployStoneFormAdvanced --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

# Install dependencies
install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install foundry-rs/forge-std --no-commit

# Test with verbosity
test-v:; forge test -vvv
test-vv:; forge test -vvvv

# Coverage
coverage:; forge coverage
