// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {StoneFormToken, StoneFormMockUSD} from "../src/StoneFormToken.sol";
import {StoneFormPresaleAdvanced} from "../src/StoneFormPresaleAdvanced.sol";

abstract contract CodeConstants {
    uint256 public constant BSC_MAINNET_CHAIN_ID = 56;
    uint256 public constant BSC_TESTNET_CHAIN_ID = 97;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    // BSC mainnet addresses
    address public constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    address public constant BSC_SABLIER = 0x06bd1Ec1d80acc45ba332f79B08d2d9e24240C74;

    // Default Anvil account #0
    address public constant DEFAULT_ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Presale config
    uint256 public constant MIN_PURCHASE = 1e18;
    uint256 public constant MAX_PURCHASE = 10_000_000 ether;
}

contract HelperConfig is CodeConstants, Script {
    struct NetworkConfig {
        address admin;
        address signer;
        address sablier;
        address usdt;
        address mockUsd;
        address presaleToken;
        uint256 deployerKey;
    }

    mapping(uint256 chainId => NetworkConfig) private s_networkConfigs;
    NetworkConfig private s_localConfig;

    constructor() {
        s_networkConfigs[BSC_MAINNET_CHAIN_ID] = getBscMainnetConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilConfig();
        } else {
            return s_networkConfigs[chainId];
        }
    }

    function setConfig(uint256 chainId, NetworkConfig memory config) public {
        s_networkConfigs[chainId] = config;
    }

    function getBscMainnetConfig() internal view returns (NetworkConfig memory) {
        return NetworkConfig({
            admin: vm.envOr("ADMIN_ADDRESS", address(0)),
            signer: vm.envOr("SIGNER_ADDRESS", address(0)),
            sablier: BSC_SABLIER,
            usdt: BSC_USDT,
            mockUsd: address(0),
            presaleToken: address(0),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() internal returns (NetworkConfig memory) {
        if (s_localConfig.sablier != address(0)) {
            return s_localConfig;
        }

        // Deploy mocks for local testing
        vm.startBroadcast(DEFAULT_ANVIL_KEY);

        StoneFormMockUSD mockUsd = new StoneFormMockUSD(DEFAULT_ANVIL_ACCOUNT);

        // Deploy a minimal mock Sablier (tests will use a proper mock)
        // For the config we just need a non-zero address; tests override this
        MockSablierPlaceholder mockSablier = new MockSablierPlaceholder();

        vm.stopBroadcast();

        s_localConfig = NetworkConfig({
            admin: DEFAULT_ANVIL_ACCOUNT,
            signer: DEFAULT_ANVIL_ACCOUNT,
            sablier: address(mockSablier),
            usdt: address(0),
            mockUsd: address(mockUsd),
            presaleToken: address(0),
            deployerKey: DEFAULT_ANVIL_KEY
        });

        return s_localConfig;
    }

    function buildTiers() public pure returns (StoneFormPresaleAdvanced.Tier[] memory tiers) {
        tiers = new StoneFormPresaleAdvanced.Tier[](3);

        tiers[0] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 1e16,
            tierTotalTokenSold: 0,
            maxCap: 50_000 ether,
            vestingDuration: 180 days,
            tgeUnlockPercent: 10
        });

        tiers[1] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 15e15,
            tierTotalTokenSold: 0,
            maxCap: 30_000 ether,
            vestingDuration: 270 days,
            tgeUnlockPercent: 15
        });

        tiers[2] = StoneFormPresaleAdvanced.Tier({
            tierPrice: 2e16,
            tierTotalTokenSold: 0,
            maxCap: 20_000 ether,
            vestingDuration: 365 days,
            tgeUnlockPercent: 20
        });
    }
}

/// @dev Minimal placeholder so HelperConfig can deploy a non-zero Sablier address on Anvil.
contract MockSablierPlaceholder {
    // Intentionally empty — tests use a full-featured mock.

    }
