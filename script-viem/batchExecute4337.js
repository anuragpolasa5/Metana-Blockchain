import { createWalletClient, createPublicClient, http, parseEther, encodeFunctionData, encodeAbiParameters, parseAbiParameters } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';

dotenv.config();

// --- ABIs ---
const mockEntryPointAbi = [
  {
    name: 'handleOps',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      {
        name: 'ops',
        type: 'tuple[]',
        components: [
          { name: 'sender', type: 'address' },
          { name: 'nonce', type: 'uint256' },
          { name: 'initCode', type: 'bytes' },
          { name: 'callData', type: 'bytes' },
          { name: 'callGasLimit', type: 'uint256' },
          { name: 'verificationGasLimit', type: 'uint256' },
          { name: 'preVerificationGas', type: 'uint256' },
          { name: 'maxFeePerGas', type: 'uint256' },
          { name: 'maxPriorityFeePerGas', type: 'uint256' },
          { name: 'paymasterAndData', type: 'bytes' },
          { name: 'signature', type: 'bytes' },
        ],
      },
      { name: 'beneficiary', type: 'address' },
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
];

const counterAbi = [
  {
    name: 'increment',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
];

async function main() {
  // --- Configuration ---
  const privateKey = process.env.PRIVATE_KEY;
  const rpcUrl = process.env.RPC_URL;
  const entryPointAddress = process.env.ENTRY_POINT_ADDRESS;
  const accountAddress = process.env.ACCOUNT_4337_ADDRESS;
  const counterAddress = process.env.COUNTER_ADDRESS;
  const tokenAddress = process.env.TOKEN_ADDRESS;
  const recipientAddress = process.env.RECIPIENT_ADDRESS;

  if (!privateKey || !rpcUrl || !entryPointAddress || !accountAddress || !counterAddress || !tokenAddress || !recipientAddress) {
    console.error('Missing environment variables. Please check your .env file.');
    console.error('Required: PRIVATE_KEY, RPC_URL, ENTRY_POINT_ADDRESS, ACCOUNT_4337_ADDRESS, COUNTER_ADDRESS, TOKEN_ADDRESS, RECIPIENT_ADDRESS');
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

  console.log(`Sender EOA: ${account.address}`);
  console.log(`EntryPoint: ${entryPointAddress}`);
  console.log(`4337 Account: ${accountAddress}`);
  console.log(`Counter: ${counterAddress}`);
  console.log(`Token: ${tokenAddress}`);
  console.log(`Recipient: ${recipientAddress}`);
  console.log('---');

  // --- Build batch calls ---
  // Action 1: Send 0.01 ETH to recipient
  const ethTransferCall = {
    to: recipientAddress,
    value: parseEther('0.01'),
    data: '0x',
  };

  // Action 2: Transfer 100 tokens to recipient
  const tokenTransferData = encodeFunctionData({
    abi: tokenAbi,
    functionName: 'transfer',
    args: [recipientAddress, parseEther('100')],
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

  // --- Encode calls as UserOp callData ---
  const calls = [ethTransferCall, tokenTransferCall, incrementCall1, incrementCall2];

  // Encode the Call[] array for the UserOp's callData field
  const callData = encodeAbiParameters(
    parseAbiParameters('(address to, uint256 value, bytes data)[]'),
    [calls.map(c => ({ to: c.to, value: c.value, data: c.data }))]
  );

  // --- Build UserOperation ---
  const userOp = {
    sender: accountAddress,
    nonce: 0n,
    initCode: '0x',
    callData: callData,
    callGasLimit: 1000000n,
    verificationGasLimit: 1000000n,
    preVerificationGas: 21000n,
    maxFeePerGas: 1000000000n, // 1 gwei
    maxPriorityFeePerGas: 1000000000n, // 1 gwei
    paymasterAndData: '0x',
    signature: '0x',
  };

  console.log('Sending UserOperation via MockEntryPoint.handleOps...');
  console.log(`  Action 1: Send 0.01 ETH to ${recipientAddress}`);
  console.log(`  Action 2: Transfer 100 tokens to ${recipientAddress}`);
  console.log(`  Action 3: Call increment() on Counter (twice)`);

  // --- Send transaction to EntryPoint ---
  const txHash = await walletClient.writeContract({
    address: entryPointAddress,
    abi: mockEntryPointAbi,
    functionName: 'handleOps',
    args: [[userOp], account.address],
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
