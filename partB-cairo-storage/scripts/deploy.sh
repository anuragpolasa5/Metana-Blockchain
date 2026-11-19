#!/bin/bash
# Deployment script for SimpleStorage on Starknet Sepolia Testnet (L2-8)
#
# Prerequisites:
#   - scarb installed (https://docs.swmansion.com/scarb/)
#   - starkli installed (https://github.com/xJonathanLEI/starkli)
#   - Account and keystore configured for Starknet Sepolia
#
# Environment variables required:
#   STARKNET_ACCOUNT - Path to account file
#   STARKNET_KEYSTORE - Path to keystore file
#   STARKNET_RPC - RPC URL (default: https://starknet-sepolia.public.blastapi.io)

set -e

# Default RPC URL for Starknet Sepolia
RPC_URL="${STARKNET_RPC:-https://starknet-sepolia.public.blastapi.io}"

echo "=== Building the contract ==="
scarb build

echo ""
echo "=== Declaring the contract class ==="
# Declare the contract (upload the class to the network)
CLASS_HASH=$(starkli declare \
  --rpc "$RPC_URL" \
  target/dev/simple_storage_SimpleStorage.contract_class.json \
  2>&1 | grep -oP '0x[0-9a-fA-F]+' | head -1)

echo "Class Hash: $CLASS_HASH"

echo ""
echo "=== Deploying the contract ==="
# Deploy an instance of the contract (no constructor args needed)
CONTRACT_ADDRESS=$(starkli deploy \
  --rpc "$RPC_URL" \
  "$CLASS_HASH" \
  2>&1 | grep -oP '0x[0-9a-fA-F]+' | head -1)

echo ""
echo "=== Deployment Complete ==="
echo "Contract Address: $CONTRACT_ADDRESS"
echo "Explorer: https://sepolia.starkscan.co/contract/$CONTRACT_ADDRESS"
echo ""
echo "To interact with the contract:"
echo "  # Set value to 42"
echo "  starkli invoke --rpc $RPC_URL $CONTRACT_ADDRESS set 42"
echo ""
echo "  # Get current value"
echo "  starkli call --rpc $RPC_URL $CONTRACT_ADDRESS get"
