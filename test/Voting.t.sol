// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VVToken} from "../src/VVToken.sol";
import {VoteResultNFT} from "../src/VoteResultNFT.sol";
import {Voting} from "../src/Voting.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VotingTest is Test {
    using SafeERC20 for IERC20;
    VVToken token;
    VoteResultNFT nft;
    Voting voting;

    address owner = address(0xA11CE);
    address alice = address(0xB0B);
    address bob = address(0xCAFE);
    address charlie = address(0xD00D);

    function setUp() public {
        vm.prank(owner);
        token = new VVToken(owner, 1_000_000 ether);

        vm.prank(owner);
        nft = new VoteResultNFT(owner);

        vm.prank(owner);
        voting = new Voting(owner, token, nft);

        vm.prank(owner);
        nft.setMinter(address(voting));

        vm.startPrank(owner);
        token.transfer(alice, 1_000 ether);
        token.transfer(bob, 1_000 ether);
        token.transfer(charlie, 1_000 ether);
        vm.stopPrank();
    }

    function testCreateVoteOnlyOwner() public {
        bytes32 voteId = keccak256("vote-1");

        vm.prank(alice);
        vm.expectRevert();
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 100 ether, "Question");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 100 ether, "Question");
    }

    function testCreateVoteValidationErrors() public {
        vm.startPrank(owner);

        vm.expectRevert(Voting.InvalidVoteId.selector);
        voting.createVote(bytes32(0), uint64(block.timestamp + 1 days), 100 ether, "Q");

        vm.expectRevert(Voting.InvalidDeadline.selector);
        voting.createVote(keccak256("past"), uint64(block.timestamp), 100 ether, "Q");

        vm.expectRevert(Voting.InvalidThreshold.selector);
        voting.createVote(keccak256("threshold"), uint64(block.timestamp + 1 days), 0, "Q");

        vm.stopPrank();
    }

    function testStakeVoteAndFinalizeEarly() public {
        bytes32 voteId = keccak256("vote-2");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 1_500 ether, "Pass with yes threshold");

        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 4);
        voting.vote(voteId, true);
        vm.stopPrank();

        (, , , , uint256 yesVotes, , bool finalized, bool passed, ) = voting.getVote(voteId);
        assertTrue(finalized);
        assertTrue(passed);
        assertGt(yesVotes, 0);

        uint256 tokenId = uint256(voteId);
        VoteResultNFT.ResultData memory result = nft.resultOf(tokenId);
        assertEq(result.yesVotes, yesVotes);
        assertTrue(result.passed);
    }

    function testVoteByTwoAddresses() public {
        bytes32 voteId = keccak256("vote-3");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 3_200 ether, "Two-address demo");

        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 4);
        voting.vote(voteId, true);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 4);
        voting.vote(voteId, true);
        vm.stopPrank();

        (, , , , uint256 yesVotes, uint256 noVotes, bool finalized, bool passed, ) = voting.getVote(voteId);
        assertTrue(finalized);
        assertTrue(passed);
        assertEq(noVotes, 0);
        assertGt(yesVotes, 0);
    }

    function testCannotDoubleVote() public {
        bytes32 voteId = keccak256("double-vote");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 10_000 ether, "No double vote");

        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 2);
        voting.vote(voteId, true);

        vm.expectRevert(abi.encodeWithSelector(Voting.AlreadyVoted.selector, voteId, alice));
        voting.vote(voteId, true);
        vm.stopPrank();
    }

    function testFinalizeAfterDeadlineByFinalizer() public {
        bytes32 voteId = keccak256("finalize-after-deadline");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 10_000 ether, "Finalize by deadline");

        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 2);
        voting.vote(voteId, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(owner);
        voting.finalizeVote(voteId);

        (, , , , , , bool finalized, , ) = voting.getVote(voteId);
        assertTrue(finalized);
    }

    function testNonFinalizerCannotFinalize() public {
        bytes32 voteId = keccak256("forbidden-finalize");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 10_000 ether, "Auth check");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Voting.NotFinalizer.selector, alice));
        voting.finalizeVote(voteId);
    }

    function testOwnerCanGrantFinalizer() public {
        bytes32 voteId = keccak256("new-finalizer");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 10_000 ether, "Grant finalizer");

        vm.prank(owner);
        voting.setFinalizer(charlie, true);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(charlie);
        voting.finalizeVote(voteId);

        (, , , , , , bool finalized, , ) = voting.getVote(voteId);
        assertTrue(finalized);
    }


    function testGetStakeAndVoteCountHelpers() public {
        bytes32 voteId = keccak256("helpers");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 1 ether, "helpers");

        vm.startPrank(alice);
        token.approve(address(voting), 50 ether);
        uint256 stakeId = voting.stake(50 ether, 2);
        vm.stopPrank();

        Voting.StakePosition memory st = voting.getStake(alice, stakeId);
        assertEq(st.amount, 50 ether);
        assertFalse(st.withdrawn);
        assertEq(voting.getVoteCount(), 1);
        assertEq(voting.voteIdAt(0), voteId);
    }

    function testWithdrawAfterUnlock() public {
        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        uint256 stakeId = voting.stake(100 ether, 1);
        vm.stopPrank();

        vm.expectRevert();
        vm.prank(alice);
        voting.withdraw(stakeId);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        voting.withdraw(stakeId);
        uint256 balanceAfter = token.balanceOf(alice);

        assertEq(balanceAfter, balanceBefore + 100 ether);
    }

    function testVotingPowerDecaysOverTime() public {
        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 4);
        vm.stopPrank();

        uint256 powerNow = voting.currentVotingPower(alice);
        vm.warp(block.timestamp + 1 days);
        uint256 powerLater = voting.currentVotingPower(alice);

        assertGt(powerNow, powerLater);
    }


    function testResultNftEnumerable() public {
        bytes32 voteId = keccak256("nft-enumerable");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 1_000 ether, "Nft enum");

        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);
        voting.stake(100 ether, 4);
        voting.vote(voteId, true);
        vm.stopPrank();

        uint256 tokenId = nft.tokenOfOwnerByIndex(owner, 0);
        assertEq(tokenId, uint256(voteId));

        string memory uri = nft.tokenURI(tokenId);
        assertGt(bytes(uri).length, 10);
    }

    function testPauseBlocksStakeAndVote() public {
        bytes32 voteId = keccak256("paused-vote");

        vm.prank(owner);
        voting.createVote(voteId, uint64(block.timestamp + 1 days), 1 ether, "Paused");

        vm.prank(owner);
        voting.pause();

        vm.startPrank(alice);
        token.approve(address(voting), 100 ether);

        vm.expectRevert();
        voting.stake(100 ether, 1);

        vm.expectRevert();
        voting.vote(voteId, true);
        vm.stopPrank();
    }
}
