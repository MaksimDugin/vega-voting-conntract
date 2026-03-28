// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {VVToken} from "../src/VVToken.sol";
import {VoteResultNFT} from "../src/VoteResultNFT.sol";
import {Voting} from "../src/Voting.sol";

contract Deploy is Script {
    function run() external returns (VVToken token, VoteResultNFT nft, Voting voting) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 ether));

        require(deployer != address(0), "bad private key");

        vm.startBroadcast(deployerPk);

        token = new VVToken(deployer, initialSupply);
        nft = new VoteResultNFT(deployer);
        voting = new Voting(deployer, token, nft);

        nft.setMinter(address(voting));

        vm.stopBroadcast();

        console2.log("Deployer:", deployer);
        console2.log("VVToken:", address(token));
        console2.log("VoteResultNFT:", address(nft));
        console2.log("Voting:", address(voting));
    }
}
