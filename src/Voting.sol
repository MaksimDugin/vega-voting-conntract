// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VoteResultNFT} from "./VoteResultNFT.sol";

/// @title Vega Voting MVP
/// @notice Staking-based voting system with early finalization and NFT result minting.
contract Voting is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Vote {
        bytes32 id;
        address creator;
        uint64 deadline;
        uint256 votingPowerThreshold;
        uint256 yesVotes;
        uint256 noVotes;
        bool finalized;
        bool passed;
        string description;
    }

    struct StakePosition {
        uint256 amount;
        uint64 unlockAt;
        bool withdrawn;
    }

    // NOTE: kept as explicit immutable state vars to avoid constructor assignment issues.
    IERC20 public immutable vvToken;
    VoteResultNFT public immutable resultNFT;

    mapping(bytes32 => Vote) private _votes;
    bytes32[] private _voteIds;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    mapping(address => StakePosition[]) private _stakes;
    mapping(address => bool) public isFinalizer;

    event VoteCreated(bytes32 indexed id, address indexed creator, uint64 deadline, uint256 votingPowerThreshold, string description);
    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint64 unlockAt);
    event Withdrawn(address indexed user, uint256 indexed stakeId, uint256 amount);
    event Voted(bytes32 indexed voteId, address indexed voter, bool support, uint256 votingPower);
    event VoteFinalized(bytes32 indexed voteId, bool passed, uint256 yesVotes, uint256 noVotes, uint256 nftTokenId);
    event FinalizerUpdated(address indexed account, bool allowed);

    error VoteAlreadyExists(bytes32 id);
    error VoteNotFound(bytes32 id);
    error VoteAlreadyFinalized(bytes32 id);
    error VoteNotOpen(bytes32 id);
    error InvalidVoteId();
    error InvalidDeadline();
    error InvalidThreshold();
    error InvalidAmount();
    error InvalidDuration();
    error AlreadyVoted(bytes32 id, address voter);
    error NoActiveVotingPower(address voter);
    error StakeNotFound(address user, uint256 stakeId);
    error StakeLocked(uint64 unlockAt);
    error StakeAlreadyWithdrawn(address user, uint256 stakeId);
    error NotFinalizable(bytes32 id);
    error NotFinalizer(address caller);
    error VoteIndexOutOfBounds(uint256 index);

    constructor(address initialOwner, IERC20 _vvToken, VoteResultNFT _resultNFT) Ownable(initialOwner) {
        vvToken = _vvToken;
        resultNFT = _resultNFT;

        isFinalizer[initialOwner] = true;
        emit FinalizerUpdated(initialOwner, true);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFinalizer(address account, bool allowed) external onlyOwner {
        isFinalizer[account] = allowed;
        emit FinalizerUpdated(account, allowed);
    }

    function createVote(
        bytes32 id,
        uint64 deadline,
        uint256 votingPowerThreshold,
        string calldata description
    ) external onlyOwner whenNotPaused {
        if (id == bytes32(0)) revert InvalidVoteId();
        if (_votes[id].deadline != 0) revert VoteAlreadyExists(id);
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (votingPowerThreshold == 0) revert InvalidThreshold();

        _votes[id] = Vote({
            id: id,
            creator: msg.sender,
            deadline: deadline,
            votingPowerThreshold: votingPowerThreshold,
            yesVotes: 0,
            noVotes: 0,
            finalized: false,
            passed: false,
            description: description
        });

        _voteIds.push(id);
        emit VoteCreated(id, msg.sender, deadline, votingPowerThreshold, description);
    }

    function stake(uint256 amount, uint256 lockDays) external whenNotPaused nonReentrant returns (uint256 stakeId) {
        if (amount == 0) revert InvalidAmount();
        if (lockDays < 1 || lockDays > 4) revert InvalidDuration();

        vvToken.safeTransferFrom(msg.sender, address(this), amount);

        uint64 unlockAt = uint64(block.timestamp + (lockDays * 1 days));
        _stakes[msg.sender].push(StakePosition({amount: amount, unlockAt: unlockAt, withdrawn: false}));

        stakeId = _stakes[msg.sender].length - 1;
        emit Staked(msg.sender, stakeId, amount, unlockAt);
    }

    function withdraw(uint256 stakeId) external nonReentrant {
        StakePosition storage stakePosition = _getStake(msg.sender, stakeId);

        if (stakePosition.withdrawn) revert StakeAlreadyWithdrawn(msg.sender, stakeId);
        if (block.timestamp < stakePosition.unlockAt) revert StakeLocked(stakePosition.unlockAt);

        stakePosition.withdrawn = true;
        vvToken.safeTransfer(msg.sender, stakePosition.amount);

        emit Withdrawn(msg.sender, stakeId, stakePosition.amount);
    }

    function stakeCount(address user) external view returns (uint256) {
        return _stakes[user].length;
    }

    function getStake(address user, uint256 stakeId) external view returns (StakePosition memory) {
        return _getStake(user, stakeId);
    }

    function getVoteCount() external view returns (uint256) {
        return _voteIds.length;
    }

    function voteIdAt(uint256 index) external view returns (bytes32) {
        if (index >= _voteIds.length) revert VoteIndexOutOfBounds(index);
        return _voteIds[index];
    }

    function vote(bytes32 voteId, bool support) external whenNotPaused nonReentrant {
        Vote storage v = _getVote(voteId);

        if (v.finalized) revert VoteAlreadyFinalized(voteId);
        if (block.timestamp >= v.deadline) revert VoteNotOpen(voteId);
        if (hasVoted[voteId][msg.sender]) revert AlreadyVoted(voteId, msg.sender);

        uint256 power = _currentVotingPower(msg.sender);
        if (power == 0) revert NoActiveVotingPower(msg.sender);

        hasVoted[voteId][msg.sender] = true;

        if (support) {
            v.yesVotes += power;
        } else {
            v.noVotes += power;
        }

        emit Voted(voteId, msg.sender, support, power);

        if (v.yesVotes >= v.votingPowerThreshold) {
            _finalize(voteId);
        }
    }

    function finalizeVote(bytes32 voteId) external nonReentrant {
        if (!isFinalizer[msg.sender]) revert NotFinalizer(msg.sender);

        Vote storage v = _getVote(voteId);

        if (v.finalized) revert VoteAlreadyFinalized(voteId);
        if (block.timestamp < v.deadline && v.yesVotes < v.votingPowerThreshold) {
            revert NotFinalizable(voteId);
        }

        _finalize(voteId);
    }

    function getVote(bytes32 voteId)
        external
        view
        returns (
            bytes32 id,
            address creator,
            uint64 deadline,
            uint256 votingPowerThreshold,
            uint256 yesVotes,
            uint256 noVotes,
            bool finalized,
            bool passed,
            string memory description
        )
    {
        Vote storage v = _getVote(voteId);
        return (
            v.id,
            v.creator,
            v.deadline,
            v.votingPowerThreshold,
            v.yesVotes,
            v.noVotes,
            v.finalized,
            v.passed,
            v.description
        );
    }

    function currentVotingPower(address user) external view returns (uint256) {
        return _currentVotingPower(user);
    }

    function canFinalize(bytes32 voteId) external view returns (bool) {
        Vote storage v = _getVote(voteId);
        return (!v.finalized) && (block.timestamp >= v.deadline || v.yesVotes >= v.votingPowerThreshold);
    }

    function _finalize(bytes32 voteId) internal {
        Vote storage v = _getVote(voteId);

        if (v.finalized) revert VoteAlreadyFinalized(voteId);

        bool passed = v.yesVotes >= v.votingPowerThreshold ? true : v.yesVotes > v.noVotes;

        v.finalized = true;
        v.passed = passed;

        uint256 nftTokenId = resultNFT.mintResult(v.creator, v.id, v.description, v.yesVotes, v.noVotes, passed, v.deadline);

        emit VoteFinalized(voteId, passed, v.yesVotes, v.noVotes, nftTokenId);
    }

    function _currentVotingPower(address user) internal view returns (uint256 power) {
        StakePosition[] storage userStakes = _stakes[user];

        for (uint256 i = 0; i < userStakes.length; i++) {
            StakePosition storage s = userStakes[i];
            if (s.withdrawn || block.timestamp >= s.unlockAt) continue;

            uint256 remaining = s.unlockAt - block.timestamp;
            uint256 normalized = Math.mulDiv(remaining, remaining, 1 days * 1 days);
            power += Math.mulDiv(s.amount, normalized, 1);
        }
    }

    function _getVote(bytes32 voteId) internal view returns (Vote storage v) {
        v = _votes[voteId];
        if (v.deadline == 0) revert VoteNotFound(voteId);
    }

    function _getStake(address user, uint256 stakeId) internal view returns (StakePosition storage s) {
        StakePosition[] storage userStakes = _stakes[user];
        if (stakeId >= userStakes.length) revert StakeNotFound(user, stakeId);
        s = userStakes[stakeId];
    }
}
