// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// NOTE: This is the legacy deploy script for StoneForm_ICO_V2 (StoneFormPresale.sol).
// For the advanced presale with tiers + vesting, use DeployStoneFormAdvanced.s.sol.

import {Script, console2} from "forge-std/Script.sol";
import {StoneForm_ICO_V2} from "../src/StoneFormPresale.sol";
import {StoneFormToken, StoneFormMockUSD} from "../src/StoneFormToken.sol";

contract DeployStoneForm is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address signerAddr = vm.envAddress("SIGNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        StoneFormToken token = new StoneFormToken(admin);

        StoneForm_ICO_V2 ico = new StoneForm_ICO_V2(
            admin,
            signerAddr,
            IERC20(address(token)),
            1e18 // tokenPerUSD
        );

        vm.stopBroadcast();

        console2.log("StoneFormToken deployed at:", address(token));
        console2.log("StoneForm_ICO_V2 deployed at:", address(ico));
    }
}

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
