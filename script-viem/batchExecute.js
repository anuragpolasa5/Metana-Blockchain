import { createWalletClient, createPublicClient, http, parseEther, encodeFunctionData, defineChain } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';

dotenv.config();

// --- ABIs ---
const batchCallerAbi = [
  {
    name: 'execute',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      {
        name: 'calls',
        type: 'tuple[]',
        components: [
          { name: 'to', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'data', type: 'bytes' },
        ],
      },
    ],
    outputs: [],
  },
];

const tokenAbi = [
  {
    name: 'transfer',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
];

const counterAbi = [
  {
    name: 'increment',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'number',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
];

async function main() {
  // --- Configuration ---
  const privateKey = process.env.PRIVATE_KEY;
  const rpcUrl = process.env.RPC_URL;
  const batchCallerAddress = process.env.BATCH_CALLER_ADDRESS;
  const counterAddress = process.env.COUNTER_ADDRESS;
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const recipientAddress = process.env.RECIPIENT_ADDRESS;

  if (!privateKey || !rpcUrl || !batchCallerAddress || !counterAddress || !tokenAddress || !recipientAddress) {
    console.error('Missing environment variables. Please check your .env file.');
    process.exit(1);
  }

  // --- Setup clients ---
  const account = privateKeyToAccount(privateKey);

  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http(rpcUrl),
  });

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl),
  });

  console.log(`EOA Address: ${account.address}`);
  console.log(`Batch Caller: ${batchCallerAddress}`);
  console.log(`Counter: ${counterAddress}`);
  console.log(`Token: ${tokenAddress}`);
  console.log(`Recipient: ${recipientAddress}`);
  console.log('---');

  // --- Step 1: Sign EIP-7702 Authorization ---
  // The EOA authorizes the BatchCallDelegation7702 contract as its delegate
  console.log('Signing EIP-7702 authorization...');

  const authorization = await walletClient.signAuthorization({
    contractAddress: batchCallerAddress,
  });

  console.log('Authorization signed.');

  // --- Step 2: Build batch calls ---
  // Action 1: Send 0.01 ETH to recipient
  const ethTransferCall = {
    to: recipientAddress,
    value: parseEther('0.01'),
    data: '0x',
  };

  // Action 2: Transfer 100 tokens to recipient
  // (Tokens must already be in the EOA's balance)
  const tokenTransferData = encodeFunctionData({
    abi: tokenAbi,
    functionName: 'transfer',
    args: [recipientAddress, parseEther('100')], // 100 tokens (18 decimals)
  });

  const tokenTransferCall = {
    to: tokenAddress,
    value: 0n,
    data: tokenTransferData,
  };

  // Action 3: Call increment() on Counter twice
  const incrementData = encodeFunctionData({
    abi: counterAbi,
    functionName: 'increment',
  });

  const incrementCall1 = {
    to: counterAddress,
    value: 0n,
    data: incrementData,
  };

  const incrementCall2 = {
    to: counterAddress,
    value: 0n,
    data: incrementData,
  };

  // --- Step 3: Execute batch via EIP-7702 ---
  // The EOA sends a transaction to itself (since it's delegated to BatchCallDelegation7702)
  // calling execute() with all the batched calls
  const calls = [ethTransferCall, tokenTransferCall, incrementCall1, incrementCall2];

  const executeData = encodeFunctionData({
    abi: batchCallerAbi,
    functionName: 'execute',
    args: [calls],
  });

  console.log('Sending EIP-7702 batch transaction...');
  console.log(`  Action 1: Send 0.01 ETH to ${recipientAddress}`);
  console.log(`  Action 2: Transfer 100 tokens to ${recipientAddress}`);
  console.log(`  Action 3: Call increment() on Counter (twice)`);

  const txHash = await walletClient.sendTransaction({
    to: account.address, // Send to self (delegated EOA)
    data: executeData,
    authorizationList: [authorization],
    gas: 500000n, // Explicit gas to avoid estimation issues with 7702
  });

  console.log(`\nTransaction sent! Hash: ${txHash}`);
  console.log(`Waiting for confirmation...`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

  console.log(`\nTransaction confirmed!`);
  console.log(`  Block: ${receipt.blockNumber}`);
  console.log(`  Gas Used: ${receipt.gasUsed}`);
  console.log(`  Status: ${receipt.status}`);
  console.log(`\nEtherscan URL: https://sepolia.etherscan.io/tx/${txHash}`);
}

main().catch((error) => {
  console.error('Error:', error);
  process.exit(1);
});
