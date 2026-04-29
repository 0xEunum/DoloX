// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal mock for ERC-8004 Identity Registry — Anvil only
contract MockERC8004Registry {
    event AgentRegistered(address account, uint256 agentId, string ensName);

    function register(address account, uint256 agentId, string calldata ensName) external {
        emit AgentRegistered(account, agentId, ensName);
    }
}
