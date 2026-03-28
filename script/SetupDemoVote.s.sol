// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Voting} from "../src/Voting.sol";

contract SetupDemoVote is Script {
    using SafeERC20 for IERC20;
    function run() external {
        address votingAddr = vm.envAddress("VOTING_ADDRESS");
        address tokenAddr = vm.envAddress("VV_TOKEN_ADDRESS");

        uint256 adminPk = vm.envUint("ADMIN_PRIVATE_KEY");
        uint256 voter1Pk = vm.envUint("VOTER1_PRIVATE_KEY");
        uint256 voter2Pk = vm.envUint("VOTER2_PRIVATE_KEY");

        address voter1 = vm.addr(voter1Pk);
        address voter2 = vm.addr(voter2Pk);

        Voting voting = Voting(votingAddr);
        IERC20 token = IERC20(tokenAddr);

        bytes32 voteId = vm.envBytes32("VOTE_ID");
        uint64 deadline = uint64(block.timestamp + vm.envOr("DEADLINE_OFFSET", uint64(1 days)));
        uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", uint256(100 ether));
        uint256 lockDays = vm.envOr("LOCK_DAYS", uint256(4));

        uint256 defaultThreshold = 2 * stakeAmount * lockDays * lockDays;
        uint256 threshold = vm.envOr("VOTING_POWER_THRESHOLD", defaultThreshold);

        vm.startBroadcast(adminPk);

        voting.createVote(
            voteId,
            deadline,
            threshold,
            vm.envOr("DESCRIPTION", string("Should the proposal pass?"))
        );

        token.safeTransfer(voter1, stakeAmount);
        token.safeTransfer(voter2, stakeAmount);

        vm.stopBroadcast();

        vm.startBroadcast(voter1Pk);
        token.approve(votingAddr, stakeAmount);
        voting.stake(stakeAmount, lockDays);
        voting.vote(voteId, true);
        vm.stopBroadcast();

        vm.startBroadcast(voter2Pk);
        token.approve(votingAddr, stakeAmount);
        voting.stake(stakeAmount, lockDays);
        voting.vote(voteId, true);
        vm.stopBroadcast();

        console2.log("Voter 1:", voter1);
        console2.log("Voter 2:", voter2);
        console2.log("Vote ID:", uint256(voteId));
    }
}
