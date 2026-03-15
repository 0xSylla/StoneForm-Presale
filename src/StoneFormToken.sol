// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*
 * @title STONEFORM TEST TOKEN
 * @author Djomoro
 * @notice STONEFORM is StoneForm's native ERC20 token.
 * @dev It has a max supply of 1,000,000,000 STOF
 */
contract StoneFormToken is ERC20("STONEFORM Test Token", "STOF Test") {
    uint256 public constant MAX_SUPPLY = 100e8 ether;

    constructor(address _distributor) {
        _mint(_distributor, MAX_SUPPLY);
    }

    /**
     * @dev Burns "amount" of OOGA by sending it to BURN_ADDRESS
     */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}

contract StoneFormMockUSD is ERC20("STONEFORM Mock USD", "STONEMOCKUSD") {
    uint256 public constant MAX_SUPPLY = 100e5 ether;

    constructor(address _distributor) {
        _mint(_distributor, MAX_SUPPLY);
    }

    /**
     * @dev Burns "amount" of OOGA by sending it to BURN_ADDRESS
     */
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}
