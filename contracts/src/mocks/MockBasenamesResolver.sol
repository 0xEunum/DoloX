// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal mock for Basenames L2Resolver — Anvil only
contract MockBasenamesResolver {
    mapping(bytes32 => address) private _addrs;
    mapping(bytes32 => mapping(string => string)) private _texts;

    function setAddr(bytes32 node, address addre) external {
        _addrs[node] = addre;
    }

    function addr(bytes32 node) external view returns (address) {
        return _addrs[node];
    }

    function setText(bytes32 node, string calldata key, string calldata value) external {
        _texts[node][key] = value;
    }

    function text(bytes32 node, string calldata key) external view returns (string memory) {
        return _texts[node][key];
    }
}
