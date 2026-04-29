// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "../core/EntryPoint.sol";

/// @notice Minimal EntryPoint mock for Anvil local testing only
contract MockEntryPoint {
    mapping(address => uint256) public deposits;
    mapping(address => uint256) private _nonces;

    function handleOps(PackedUserOperation[] calldata, address payable beneficiary) external {
        (bool s,) = beneficiary.call{value: 0}("");
        (s);
    }

    function getUserOpHash(PackedUserOperation calldata) external pure returns (bytes32) {
        return keccak256("mock");
    }

    function getNonce(address sender, uint192) external view returns (uint256) {
        return _nonces[sender];
    }

    function depositTo(address account) external payable {
        deposits[account] += msg.value;
    }

    function balanceOf(address account) external view returns (uint256) {
        return deposits[account];
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {
        deposits[msg.sender] -= withdrawAmount;
        (bool s,) = withdrawAddress.call{value: withdrawAmount}("");
        (s);
    }

    receive() external payable {}
}
