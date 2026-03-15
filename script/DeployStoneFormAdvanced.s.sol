// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {StoneFormToken, StoneFormMockUSD} from "../src/StoneFormToken.sol";
import {StoneFormPresaleAdvanced} from "../src/StoneFormPresaleAdvanced.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {SetPresaleToken, AddPaymentTokens, InitPresale, FundPresale} from "./Interactions.s.sol";

contract DeployStoneFormAdvanced is Script {
    function run() external returns (StoneFormPresaleAdvanced, HelperConfig) {
        return deployPresale();
    }

    function deployPresale() public returns (StoneFormPresaleAdvanced, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        StoneFormPresaleAdvanced.Tier[] memory tiers = helperConfig.buildTiers();

        // --- Deploy ---
        vm.startBroadcast(config.deployerKey);

        StoneFormPresaleAdvanced presale = new StoneFormPresaleAdvanced(
            config.admin,
            config.signer,
            config.sablier,
            tiers,
            1e18,           // minPurchase
            10_000_000 ether // maxPurchase
        );

        // Deploy presale token, minted to presale contract
        StoneFormToken token = new StoneFormToken(address(presale));

        vm.stopBroadcast();

        // --- Post-deploy setup ---

        // 1. Set presale token
        SetPresaleToken setToken = new SetPresaleToken();
        setToken.setPresaleToken(address(presale), address(token), config.deployerKey);

        // 2. Configure payment tokens
        _addPaymentTokens(address(presale), config);

        // 3. Update config with deployed addresses
        config.presaleToken = address(token);
        helperConfig.setConfig(block.chainid, config);

        console2.log("StoneFormPresaleAdvanced deployed at:", address(presale));
        console2.log("StoneFormToken deployed at:", address(token));

        return (presale, helperConfig);
    }

    function _addPaymentTokens(address presale, HelperConfig.NetworkConfig memory config) internal {
        AddPaymentTokens addTokens = new AddPaymentTokens();

        if (config.mockUsd != address(0)) {
            // Local: add MockUSD
            address[] memory tokens = new address[](1);
            string[] memory symbols = new string[](1);
            tokens[0] = config.mockUsd;
            symbols[0] = "MUSD";
            addTokens.addPaymentTokens(address(presale), tokens, symbols, config.deployerKey);
        } else {
            // BSC: add USDT
            address[] memory tokens = new address[](1);
            string[] memory symbols = new string[](1);
            tokens[0] = config.usdt;
            symbols[0] = "USDT";
            addTokens.addPaymentTokens(address(presale), tokens, symbols, config.deployerKey);
        }
    }
}
