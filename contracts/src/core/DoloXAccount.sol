// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEntryPoint, PackedUserOperation} from "./EntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DoloXAccount
/// @notice ERC-4337 smart account for a DoloX agent.
///         Each agent owns its funds, signs UserOps, pays its own gas.
contract DoloXAccount {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotEntryPoint();
    error NotOwner();
    error NotEntryPointOrOwner();
    error InvalidSignature();
    error CallFailed(bytes reason);
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AgentExecuted(address indexed target, uint256 value, bytes data);
    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);
    event Deposit(address indexed sender, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint public immutable entryPoint;
    address public owner;

    // ERC-4337 validation constants
    uint256 private constant SIG_VALIDATION_SUCCESS = 0;
    uint256 private constant SIG_VALIDATION_FAILED = 1;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _entryPoint, address _owner) {
        if (_entryPoint == address(0) || _owner == address(0)) revert ZeroAddress();
        entryPoint = IEntryPoint(_entryPoint);
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyEntryPointOrOwner() {
        if (msg.sender != address(entryPoint) && msg.sender != owner) {
            revert NotEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-4337 CORE
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates a UserOperation — called by EntryPoint
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        onlyEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /// @notice Execute a call from this agent account
    /// @dev Called by EntryPoint after successful validation
    function execute(address target, uint256 value, bytes calldata data) external onlyEntryPointOrOwner {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) revert CallFailed(result);
        emit AgentExecuted(target, value, data);
    }

    /// @notice Execute a batch of calls atomically
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas)
        external
        onlyEntryPointOrOwner
    {
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(datas[i]);
            if (!success) revert CallFailed(result);
            emit AgentExecuted(targets[i], values[i], datas[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Withdraw ERC20 tokens from this agent account
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    /// @notice Withdraw native ETH
    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        if (!success) revert CallFailed("");
        emit Withdrawn(address(0), to, amount);
    }

    /// @notice Deposit ETH to EntryPoint for gas prefunding
    function depositToEntryPoint() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256)
    {
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        address recovered = ethHash.recover(userOp.signature);
        if (recovered != owner) return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds > 0) {
            (bool success,) = payable(address(entryPoint)).call{value: missingAccountFunds}("");
            (success);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              RECEIVE
    //////////////////////////////////////////////////////////////*/
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
}
