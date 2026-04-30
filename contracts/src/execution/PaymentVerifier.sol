// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AgentRegistry} from "../registry/AgentRegistry.sol";
import {ReputationManager} from "../registry/ReputationManager.sol";

/// @title PaymentVerifier
/// @notice Verifies x402 payment proofs onchain.
///         When an execution agent pays a signal agent via x402,
///         the signal agent submits the payment proof here for
///         reputation update and settlement verification.
contract PaymentVerifier is ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidPaymentProof();
    error PaymentAlreadyVerified(bytes32 paymentId);
    error AgentNotRegistered(address account);
    error ZeroAddress();
    error ExpiredPayment(uint256 deadline);
    error InsufficientAmount(uint256 sent, uint256 required);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event PaymentVerified(
        bytes32 indexed paymentId,
        address indexed payer, // exec agent
        address indexed payee, // signal agent
        uint256 amount,
        address token,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    AgentRegistry public immutable registry;
    ReputationManager public immutable reputation;

    // paymentId => verified
    mapping(bytes32 => bool) public verifiedPayments;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _registry, address _reputation) {
        if (_registry == address(0) || _reputation == address(0)) revert ZeroAddress();
        registry = AgentRegistry(_registry);
        reputation = ReputationManager(_reputation);
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verify an x402 payment proof onchain
    /// @dev Called by the signal agent after receiving x402 payment from exec agent
    /// @param paymentId   Unique payment ID (from x402 payment header)
    /// @param payer       Execution agent's DoloXAccount address
    /// @param amount      Amount paid in USDC (6 decimals)
    /// @param token       Payment token address (USDC)
    /// @param deadline    Payment expiry timestamp
    /// @param signature   Payer's signature over (paymentId, payer, payee, amount, deadline)
    function verifyPayment(
        bytes32 paymentId,
        address payer,
        uint256 amount,
        address token,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (verifiedPayments[paymentId]) revert PaymentAlreadyVerified(paymentId);
        if (block.timestamp > deadline) revert ExpiredPayment(deadline);
        if (!registry.isRegistered(payer)) revert AgentNotRegistered(payer);
        if (!registry.isRegistered(msg.sender)) revert AgentNotRegistered(msg.sender);

        // Reconstruct and verify payment signature
        bytes32 paymentHash = keccak256(abi.encodePacked(paymentId, payer, msg.sender, amount, token, deadline));
        bytes32 ethHash = paymentHash.toEthSignedMessageHash();
        address recovered = ethHash.recover(signature);

        // Signature must come from payer's account owner
        AgentRegistry.Agent memory payerAgent = registry.getAgent(payer);
        if (recovered != payerAgent.owner) revert InvalidPaymentProof();

        verifiedPayments[paymentId] = true;

        // Update reputation for signal agent (payee = msg.sender)
        reputation.recordEvent(msg.sender, ReputationManager.ReputationEvent.SIGNAL_FULFILLED);

        emit PaymentVerified(paymentId, payer, msg.sender, amount, token, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function isPaymentVerified(bytes32 paymentId) external view returns (bool) {
        return verifiedPayments[paymentId];
    }
}
