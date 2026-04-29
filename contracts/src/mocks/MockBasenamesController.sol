// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal mock for Basenames RegistrarController — Anvil only
contract MockBasenamesController {
    event NameRegistered(string name, address owner, uint256 duration);

    struct RegisterRequest {
        string name;
        address owner;
        uint256 duration;
        address resolver;
        bytes[] data;
        bool reverseRecord;
    }

    function register(RegisterRequest calldata req) external payable {
        emit NameRegistered(req.name, req.owner, req.duration);
    }

    function rentPrice(string calldata, uint256) external pure returns (uint256) {
        return 0.001 ether;
    }
}
