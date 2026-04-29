// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DoloXAccount} from "./DoloXAccount.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @title DoloXAccountFactory
/// @notice Deploys DoloXAccount instances deterministically via CREATE2.
///         Same owner + salt = same address across deployments.
contract DoloXAccountFactory {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgentAccountCreated(address indexed account, address indexed owner, uint256 salt);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public immutable entryPoint;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _entryPoint) {
        if (_entryPoint == address(0)) revert ZeroAddress();
        entryPoint = _entryPoint;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new DoloXAccount for an agent
    /// @param owner The agent's owner (EOA or contract)
    /// @param salt Unique salt — allows same owner to have multiple agents
    function createAccount(address owner, uint256 salt) external returns (DoloXAccount account) {
        address predicted = getAddress(owner, salt);

        // Return existing account if already deployed (idempotent)
        if (predicted.code.length > 0) {
            return DoloXAccount(payable(predicted));
        }

        bytes memory bytecode = abi.encodePacked(type(DoloXAccount).creationCode, abi.encode(entryPoint, owner));

        account = DoloXAccount(payable(Create2.deploy(0, bytes32(salt), bytecode)));

        emit AgentAccountCreated(address(account), owner, salt);
    }

    /// @notice Predict the address of an agent account before deployment
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(type(DoloXAccount).creationCode, abi.encode(entryPoint, owner));
        return Create2.computeAddress(bytes32(salt), keccak256(bytecode));
    }

    /// @notice Generate initCode for ERC-4337 counterfactual deployment
    /// @dev Used in UserOperation.initCode field
    function getInitCode(address owner, uint256 salt) external view returns (bytes memory) {
        return abi.encodePacked(address(this), abi.encodeCall(this.createAccount, (owner, salt)));
    }
}
