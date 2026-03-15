// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {StoneFormPresaleAdvanced} from "../src/StoneFormPresaleAdvanced.sol";
import {StoneFormToken} from "../src/StoneFormToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SetPresaleToken is Script {
    function setPresaleToken(address presale, address token, uint256 deployerKey) public {
        vm.startBroadcast(deployerKey);
        StoneFormPresaleAdvanced(payable(presale)).setPresaleToken(token);
        vm.stopBroadcast();
    }
}

contract AddPaymentTokens is Script {
    function addPaymentTokens(
        address presale,
        address[] memory tokens,
        string[] memory symbols,
        uint256 deployerKey
    ) public {
        vm.startBroadcast(deployerKey);
        StoneFormPresaleAdvanced(payable(presale)).addNewPaymentToken(tokens, symbols);
        vm.stopBroadcast();
    }
}

contract InitPresale is Script {
    function initPresale(address presale, uint256 startTime, uint256 deployerKey) public {
        vm.startBroadcast(deployerKey);
        StoneFormPresaleAdvanced(payable(presale)).initPresale(startTime);
        vm.stopBroadcast();
    }
}

contract FundPresale is Script {
    function fundPresale(address presale, address token, uint256 amount, uint256 deployerKey) public {
        vm.startBroadcast(deployerKey);
        IERC20(token).transfer(presale, amount);
        vm.stopBroadcast();
    }
}

contract FinalizePresale is Script {
    function finalizePresale(address presale, uint40 tgeTimestamp, uint256 deployerKey) public {
        vm.startBroadcast(deployerKey);
        StoneFormPresaleAdvanced(payable(presale)).finalizePresale(tgeTimestamp);
        vm.stopBroadcast();
    }
}
