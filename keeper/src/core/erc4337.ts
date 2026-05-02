import {
  createPublicClient,
  http,
  encodeFunctionData,
  pad,
  concat,
  toHex,
  type Address,
  type Hash,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import { entryPoint07Address } from "viem/account-abstraction";

const ENTRYPOINT_ABI = [
  {
    name: "getNonce",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "sender", type: "address" },
      { name: "key", type: "uint192" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getUserOpHash",
    type: "function",
    stateMutability: "view",
    inputs: [
      {
        name: "userOp",
        type: "tuple",
        components: [
          { name: "sender", type: "address" },
          { name: "nonce", type: "uint256" },
          { name: "initCode", type: "bytes" },
          { name: "callData", type: "bytes" },
          { name: "accountGasLimits", type: "bytes32" },
          { name: "preVerificationGas", type: "uint256" },
          { name: "gasFees", type: "bytes32" },
          { name: "paymasterAndData", type: "bytes" },
          { name: "signature", type: "bytes" },
        ],
      },
    ],
    outputs: [{ name: "", type: "bytes32" }],
  },
] as const;

const BATCH_EXECUTE_ABI = [
  {
    name: "executeBatch",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "targets", type: "address[]" },
      { name: "values", type: "uint256[]" },
      { name: "calldatas", type: "bytes[]" },
    ],
    outputs: [],
  },
] as const;

const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

const SWAP_EXECUTOR_ABI = [
  {
    name: "executeSwap",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "fee", type: "uint24" },
      { name: "amountIn", type: "uint256" },
      { name: "amountOutMinimum", type: "uint256" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
] as const;

export interface SwapParams {
  tokenIn: Address;
  tokenOut: Address;
  fee: number;
  amountIn: bigint;
  amountOutMinimum: bigint;
}

// Pack two uint128s into bytes32 — for getUserOpHash on-chain struct ONLY
function packUint128s(hi: bigint, lo: bigint): `0x${string}` {
  return concat([
    pad(toHex(hi), { size: 16 }),
    pad(toHex(lo), { size: 16 }),
  ]) as `0x${string}`;
}

export class ERC4337Client {
  private publicClient: any;
  private owner: any;
  private swapExecutorAddress: Address;

  constructor(
    private rpcUrl: string,
    private bundlerUrl: string,
    private privateKey: string,
    private accountAddress: string,
    swapExecutorAddress: string,
  ) {
    this.swapExecutorAddress = swapExecutorAddress as Address;
  }

  async init() {
    this.owner = privateKeyToAccount(this.privateKey as `0x${string}`);

    this.publicClient = createPublicClient({
      chain: baseSepolia,
      transport: http(this.rpcUrl),
    });

    console.log(`[ERC4337] Account:    ${this.accountAddress}`);
    console.log(`[ERC4337] Owner EOA:  ${this.owner.address}`);
    console.log(`[ERC4337] EntryPoint: ${entryPoint07Address}`);
  }

  async executeSwap(params: SwapParams): Promise<Hash> {
    // 1. Build callData — approve + executeSwap batched
    const approveData = encodeFunctionData({
      abi: ERC20_ABI,
      functionName: "approve",
      args: [this.swapExecutorAddress, params.amountIn],
    });

    const swapData = encodeFunctionData({
      abi: SWAP_EXECUTOR_ABI,
      functionName: "executeSwap",
      args: [
        params.tokenIn,
        params.tokenOut,
        params.fee,
        params.amountIn,
        params.amountOutMinimum,
      ],
    });

    const callData = encodeFunctionData({
      abi: BATCH_EXECUTE_ABI,
      functionName: "executeBatch",
      args: [
        [params.tokenIn, this.swapExecutorAddress],
        [0n, 0n],
        [approveData, swapData],
      ],
    });

    // 2. Nonce from EntryPoint
    const nonce = await this.publicClient.readContract({
      address: entryPoint07Address,
      abi: ENTRYPOINT_ABI,
      functionName: "getNonce",
      args: [this.accountAddress as Address, 0n],
    });

    // 3. Gas prices from Pimlico
    const gasPriceRes = await fetch(this.bundlerUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "pimlico_getUserOperationGasPrice",
        params: [],
      }),
    });
    const gasPriceData = await gasPriceRes.json();
    const fast = gasPriceData.result?.fast ?? {
      maxFeePerGas: "0x100000",
      maxPriorityFeePerGas: "0x100000",
    };
    const maxFeePerGas = BigInt(fast.maxFeePerGas);
    const maxPriorityFeePerGas = BigInt(fast.maxPriorityFeePerGas);

    const callGasLimit = 300_000n;
    const verificationGasLimit = 150_000n;
    const preVerificationGas = 60_000n;

    // 4. getUserOpHash — uses packed v0.7 struct (on-chain call only)
    const userOpForHash = {
      sender: this.accountAddress as Address,
      nonce,
      initCode: "0x" as `0x${string}`,
      callData,
      accountGasLimits: packUint128s(verificationGasLimit, callGasLimit),
      preVerificationGas,
      gasFees: packUint128s(maxPriorityFeePerGas, maxFeePerGas),
      paymasterAndData: "0x" as `0x${string}`,
      signature: "0x" as `0x${string}`,
    };

    const userOpHash = await this.publicClient.readContract({
      address: entryPoint07Address,
      abi: ENTRYPOINT_ABI,
      functionName: "getUserOpHash",
      args: [userOpForHash],
    });

    // 5. Sign the hash
    const signature = await this.owner.signMessage({
      message: { raw: userOpHash as `0x${string}` },
    });

    console.log("[ERC4337] Submitting UserOperation for swap...");

    // 6. Send to Pimlico — v0.7 JSON-RPC uses flat unpacked fields
    const sendRes = await fetch(this.bundlerUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 2,
        method: "eth_sendUserOperation",
        params: [
          {
            sender: this.accountAddress,
            nonce: toHex(nonce),
            callData,
            callGasLimit: toHex(callGasLimit),
            verificationGasLimit: toHex(verificationGasLimit),
            preVerificationGas: toHex(preVerificationGas),
            maxFeePerGas: toHex(maxFeePerGas),
            maxPriorityFeePerGas: toHex(maxPriorityFeePerGas),
            signature,
            // no factory/factoryData — account already deployed
            // no paymaster — paying from account deposit
          },
          entryPoint07Address,
        ],
      }),
    });

    const sendData = await sendRes.json();

    if (sendData.error) {
      throw new Error(
        `[ERC4337] UserOp failed: ${JSON.stringify(sendData.error)}`,
      );
    }

    const opHash: Hash = sendData.result;
    console.log(`[ERC4337] UserOp submitted: ${opHash}`);

    // 7. Poll for receipt
    for (let i = 0; i < 30; i++) {
      await new Promise((r) => setTimeout(r, 2000));
      const receiptRes = await fetch(this.bundlerUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 3,
          method: "eth_getUserOperationReceipt",
          params: [opHash],
        }),
      });
      const receiptData = await receiptRes.json();
      if (receiptData.result) {
        const txHash = receiptData.result.receipt.transactionHash as Hash;
        console.log(`[ERC4337] Swap confirmed: ${txHash}`);
        return txHash;
      }
    }

    throw new Error("[ERC4337] UserOp receipt timeout");
  }
}
