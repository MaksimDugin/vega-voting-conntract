// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Voting} from "../src/Voting.sol";

/// @notice One-click voter action script: approve -> stake -> vote.
contract CastVote is Script {
    function run() external {
        uint256 voterPk = vm.envUint("VOTER_PRIVATE_KEY");
        address votingAddr = vm.envAddress("VOTING_ADDRESS");
        address tokenAddr = vm.envAddress("VV_TOKEN_ADDRESS");
        bytes32 voteId = vm.envBytes32("VOTE_ID");

        uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", uint256(100 ether));
        uint256 lockDays = vm.envOr("LOCK_DAYS", uint256(4));
        bool support = vm.envOr("SUPPORT", true);

        Voting voting = Voting(votingAddr);
        IERC20 token = IERC20(tokenAddr);

        vm.startBroadcast(voterPk);
        token.approve(votingAddr, stakeAmount);
        uint256 stakeId = voting.stake(stakeAmount, lockDays);
        voting.vote(voteId, support);
        vm.stopBroadcast();

        address voter = vm.addr(voterPk);
        uint256 currentPower = voting.currentVotingPower(voter);

        console2.log("Voter:", voter);
        console2.log("Stake id:", stakeId);
        console2.log("Current voting power:", currentPower);
    }
}
