// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Minimal interface for ERC-4337 EntryPoint v0.7
// Deployed on Base Sepolia: 0x0000000071727De22E5E9d8BAf0edAc6f37da032

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

interface IEntryPoint {
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;

    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);

    function getNonce(address sender, uint192 key) external view returns (uint256);

    function depositTo(address account) external payable;

    function balanceOf(address account) external view returns (uint256);

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;
}
