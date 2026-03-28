// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title VegaVoting token (VV)
/// @notice Simple mintable ERC20 used as the staking asset for voting.
contract VVToken is ERC20, Ownable {
    constructor(address initialOwner, uint256 initialSupply) ERC20("VegaVoting", "VV") Ownable(initialOwner) {
        _mint(initialOwner, initialSupply);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
