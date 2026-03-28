// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Voting} from "../src/Voting.sol";
import {VoteResultNFT} from "../src/VoteResultNFT.sol";

/// @notice End-to-end script: create vote -> fund two users -> both vote -> print summary and NFT result.
contract RunTwoPartyFlow is Script {
    function run() external {
        address votingAddr = vm.envAddress("VOTING_ADDRESS");
        address tokenAddr = vm.envAddress("VV_TOKEN_ADDRESS");
        address nftAddr = vm.envAddress("RESULT_NFT_ADDRESS");

        uint256 adminPk = vm.envUint("ADMIN_PRIVATE_KEY");
        uint256 voter1Pk = vm.envUint("VOTER1_PRIVATE_KEY");
        uint256 voter2Pk = vm.envUint("VOTER2_PRIVATE_KEY");

        address voter1 = vm.addr(voter1Pk);
        address voter2 = vm.addr(voter2Pk);

        bytes32 voteId = vm.envBytes32("VOTE_ID");
        uint64 deadline = uint64(block.timestamp + vm.envOr("DEADLINE_OFFSET", uint64(1 days)));
        uint256 stakeAmount = vm.envOr("STAKE_AMOUNT", uint256(100 ether));
        uint256 lockDays = vm.envOr("LOCK_DAYS", uint256(4));
        uint256 threshold = vm.envOr("VOTING_POWER_THRESHOLD", uint256(2 * stakeAmount * lockDays * lockDays));
        string memory description = vm.envOr("DESCRIPTION", string("Should the proposal pass?"));

        Voting voting = Voting(votingAddr);
        IERC20 token = IERC20(tokenAddr);
        VoteResultNFT nft = VoteResultNFT(nftAddr);

        vm.startBroadcast(adminPk);
        voting.createVote(voteId, deadline, threshold, description);
        token.transfer(voter1, stakeAmount);
        token.transfer(voter2, stakeAmount);
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

        (
            ,
            ,
            uint64 voteDeadline,
            uint256 voteThreshold,
            uint256 yesVotes,
            uint256 noVotes,
            bool finalized,
            bool passed,
            string memory voteDescription
        ) = voting.getVote(voteId);

        console2.log("Description:", voteDescription);

        console2.log("Vote id:", uint256(voteId));
        console2.log("Deadline:", voteDeadline);
        console2.log("Threshold:", voteThreshold);
        console2.log("Yes votes:", yesVotes);
        console2.log("No votes:", noVotes);
        console2.log("Finalized:", finalized);
        console2.log("Passed:", passed);

        if (finalized) {
            VoteResultNFT.ResultData memory result = nft.resultOf(uint256(voteId));
            console2.log("Result NFT tokenId:", uint256(voteId));
            console2.log("Result NFT yes:", result.yesVotes);
            console2.log("Result NFT no:", result.noVotes);
            console2.log("Result NFT passed:", result.passed);
        }
    }
}
