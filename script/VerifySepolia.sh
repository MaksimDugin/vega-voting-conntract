#!/usr/bin/env bash
set -euo pipefail

# Separate verification script for already deployed VegaVoting contracts on Sepolia.
#
# Required env vars:
#   ETHERSCAN_API_KEY
#   DEPLOYER_ADDRESS
#   VV_TOKEN_ADDRESS
#   RESULT_NFT_ADDRESS
#   VOTING_ADDRESS
# Optional:
#   INITIAL_SUPPLY (defaults to 1_000_000 ether)
#   CHAIN (defaults to sepolia)
#   VERIFIER (defaults to etherscan)
#
# Example:
#   export ETHERSCAN_API_KEY="..."
#   export DEPLOYER_ADDRESS="0x..."
#   export VV_TOKEN_ADDRESS="0x..."
#   export RESULT_NFT_ADDRESS="0x..."
#   export VOTING_ADDRESS="0x..."
#   bash script/VerifySepolia.sh

: "${ETHERSCAN_API_KEY:?ETHERSCAN_API_KEY is required}"
: "${DEPLOYER_ADDRESS:?DEPLOYER_ADDRESS is required}"
: "${VV_TOKEN_ADDRESS:?VV_TOKEN_ADDRESS is required}"
: "${RESULT_NFT_ADDRESS:?RESULT_NFT_ADDRESS is required}"
: "${VOTING_ADDRESS:?VOTING_ADDRESS is required}"

CHAIN="${CHAIN:-sepolia}"
VERIFIER="${VERIFIER:-etherscan}"
INITIAL_SUPPLY="${INITIAL_SUPPLY:-1000000000000000000000000}"

echo "== Verifying VVToken =="
VV_ARGS=$(cast abi-encode "constructor(address,uint256)" "$DEPLOYER_ADDRESS" "$INITIAL_SUPPLY")
forge verify-contract \
  --chain "$CHAIN" \
  --verifier "$VERIFIER" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$VV_ARGS" \
  --watch \
  "$VV_TOKEN_ADDRESS" \
  src/VVToken.sol:VVToken

echo "== Verifying VoteResultNFT =="
NFT_ARGS=$(cast abi-encode "constructor(address)" "$DEPLOYER_ADDRESS")
forge verify-contract \
  --chain "$CHAIN" \
  --verifier "$VERIFIER" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$NFT_ARGS" \
  --watch \
  "$RESULT_NFT_ADDRESS" \
  src/VoteResultNFT.sol:VoteResultNFT

echo "== Verifying Voting =="
VOTING_ARGS=$(cast abi-encode "constructor(address,address,address)" "$DEPLOYER_ADDRESS" "$VV_TOKEN_ADDRESS" "$RESULT_NFT_ADDRESS")
forge verify-contract \
  --chain "$CHAIN" \
  --verifier "$VERIFIER" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$VOTING_ARGS" \
  --watch \
  "$VOTING_ADDRESS" \
  src/Voting.sol:Voting

echo "✅ Verification requests submitted."
