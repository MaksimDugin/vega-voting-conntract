// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Vote Result NFT
/// @notice Mints one NFT per finalized vote. The token URI stores the result metadata on-chain.
contract VoteResultNFT is ERC721Enumerable, Ownable {
    using Strings for uint256;

    struct ResultData {
        bytes32 voteId;
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        bool passed;
        uint64 deadline;
        address creator;
    }

    address public minter;
    mapping(uint256 => ResultData) private _results;

    error NotMinter();
    error UnknownToken();

    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    constructor(address initialOwner) ERC721("Vote Result NFT", "VRNFT") Ownable(initialOwner) {}

    function setMinter(address newMinter) external onlyOwner {
        emit MinterUpdated(minter, newMinter);
        minter = newMinter;
    }

    function mintResult(
        address to,
        bytes32 voteId,
        string calldata description,
        uint256 yesVotes,
        uint256 noVotes,
        bool passed,
        uint64 deadline
    ) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert NotMinter();

        tokenId = uint256(voteId);
        _safeMint(to, tokenId);

        _results[tokenId] = ResultData({
            voteId: voteId,
            description: description,
            yesVotes: yesVotes,
            noVotes: noVotes,
            passed: passed,
            deadline: deadline,
            creator: to
        });
    }

    function resultOf(uint256 tokenId) external view returns (ResultData memory) {
        if (_ownerOf(tokenId) == address(0)) revert UnknownToken();
        return _results[tokenId];
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert UnknownToken();

        ResultData memory r = _results[tokenId];

        string memory json = string(
            abi.encodePacked(
                '{"name":"Vote Result #',
                tokenId.toString(),
                '","description":"On-chain voting result NFT","attributes":[',
                    '{"trait_type":"voteId","value":"0x',
                    Strings.toHexString(uint256(r.voteId), 32),
                    '"},',
                    '{"trait_type":"description","value":"',
                    _escapeJson(r.description),
                    '"},',
                    '{"trait_type":"yesVotes","value":"',
                    r.yesVotes.toString(),
                    '"},',
                    '{"trait_type":"noVotes","value":"',
                    r.noVotes.toString(),
                    '"},',
                    '{"trait_type":"passed","value":"',
                    r.passed ? "true" : "false",
                    '"},',
                    '{"trait_type":"deadline","value":"',
                    uint256(r.deadline).toString(),
                    '"},',
                    '{"trait_type":"creator","value":"',
                    Strings.toHexString(uint256(uint160(r.creator)), 20),
                    '"}',
                ']}'
            )
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {        return super.supportsInterface(interfaceId);
    }

    function _escapeJson(string memory input) internal pure returns (string memory) {
        bytes memory b = bytes(input);
        bytes memory out = new bytes(b.length * 2);
        uint256 j = 0;

        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c == '"' || c == '\\') {
                out[j++] = '\\';
                out[j++] = c;
            } else if (c == '\n') {
                out[j++] = '\\';
                out[j++] = 'n';
            } else if (c == '\r') {
                out[j++] = '\\';
                out[j++] = 'r';
            } else if (c == '\t') {
                out[j++] = '\\';
                out[j++] = 't';
            } else {
                out[j++] = c;
            }
        }

        bytes memory trimmed = new bytes(j);
        for (uint256 k = 0; k < j; k++) {
            trimmed[k] = out[k];
        }
        return string(trimmed);
    }
}
