// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PaymentVerifier} from "../src/execution/PaymentVerifier.sol";
import {AgentRegistry} from "../src/registry/AgentRegistry.sol";
import {ReputationManager} from "../src/registry/ReputationManager.sol";
import {MockERC8004Registry} from "../src/mocks/MockERC8004Registry.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract PaymentVerifierTest is Test {
    using MessageHashUtils for bytes32;

    PaymentVerifier verifier;
    AgentRegistry registry;
    ReputationManager reputation;
    MockERC8004Registry erc8004;

    // Payer = exec agent owner
    address payerOwner;
    uint256 payerKey;

    // Payee = signal agent account (msg.sender in verifyPayment)
    address signalAgent;
    address execAgent;

    address owner = makeAddr("owner");

    function setUp() public {
        (payerOwner, payerKey) = makeAddrAndKey("payerOwner");

        erc8004 = new MockERC8004Registry();
        registry = new AgentRegistry(address(erc8004), owner);
        reputation = new ReputationManager(address(registry), owner);
        verifier = new PaymentVerifier(address(registry), address(reputation));

        // Authorize verifier in reputation
        vm.prank(owner);
        reputation.addAuthorizedCaller(address(verifier));

        // Deploy agent smart accounts (simple EOAs for test simplicity)
        execAgent = makeAddr("execAgent");
        signalAgent = makeAddr("signalAgent");

        // Register both agents — execAgent owned by payerOwner
        vm.prank(payerOwner);
        registry.registerAgent(execAgent, "dolox-exec.base.eth", AgentRegistry.AgentType.EXECUTION);

        vm.prank(owner);
        registry.registerAgent(signalAgent, "dolox-signal.base.eth", AgentRegistry.AgentType.SIGNAL);

        // Initialize reputation for signalAgent
        vm.prank(owner);
        reputation.addAuthorizedCaller(owner);
        vm.prank(owner);
        reputation.initializeAgent(signalAgent);
    }

    /*//////////////////////////////////////////////////////////////
                          VERIFY PAYMENT
    //////////////////////////////////////////////////////////////*/

    function test_verifyPayment_success() public {
        (bytes32 paymentId, uint256 amount, address token, uint256 deadline, bytes memory sig) = _buildValidPayment();

        vm.prank(signalAgent);
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);

        assertTrue(verifier.isPaymentVerified(paymentId));
    }

    function test_verifyPayment_updatesSignalReputation() public {
        uint256 scoreBefore = reputation.getScore(signalAgent);

        (bytes32 paymentId, uint256 amount, address token, uint256 deadline, bytes memory sig) = _buildValidPayment();

        vm.prank(signalAgent);
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);

        assertEq(reputation.getScore(signalAgent), scoreBefore + 5); // SIGNAL_FULFILLED +5
    }

    function test_verifyPayment_revertReplay() public {
        (bytes32 paymentId, uint256 amount, address token, uint256 deadline, bytes memory sig) = _buildValidPayment();

        vm.prank(signalAgent);
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);

        // Try again with same paymentId
        vm.prank(signalAgent);
        vm.expectRevert(abi.encodeWithSelector(PaymentVerifier.PaymentAlreadyVerified.selector, paymentId));
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);
    }

    function test_verifyPayment_revertExpired() public {
        bytes32 paymentId = keccak256("expired_payment");
        uint256 amount = 1e6;
        address token = makeAddr("usdc");
        uint256 deadline = block.timestamp - 1; // already expired

        bytes32 hash = keccak256(abi.encodePacked(paymentId, execAgent, signalAgent, amount, token, deadline))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(signalAgent);
        vm.expectRevert(abi.encodeWithSelector(PaymentVerifier.ExpiredPayment.selector, deadline));
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);
    }

    function test_verifyPayment_revertInvalidSignature() public {
        bytes32 paymentId = keccak256("bad_sig_payment");
        uint256 amount = 1e6;
        address token = makeAddr("usdc");
        uint256 deadline = block.timestamp + 1 hours;

        // Sign with wrong key
        (, uint256 wrongKey) = makeAddrAndKey("wrongSigner");
        bytes32 hash = keccak256(abi.encodePacked(paymentId, execAgent, signalAgent, amount, token, deadline))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(signalAgent);
        vm.expectRevert(PaymentVerifier.InvalidPaymentProof.selector);
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);
    }

    function test_verifyPayment_revertPayerNotRegistered() public {
        address unregisteredPayer = makeAddr("unregistered");
        bytes32 paymentId = keccak256("unregistered_payer");
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(signalAgent);
        vm.expectRevert(abi.encodeWithSelector(PaymentVerifier.AgentNotRegistered.selector, unregisteredPayer));
        verifier.verifyPayment(paymentId, unregisteredPayer, 1e6, makeAddr("usdc"), deadline, "");
    }

    function test_verifyPayment_revertPayeeNotRegistered() public {
        (bytes32 paymentId, uint256 amount, address token, uint256 deadline, bytes memory sig) = _buildValidPayment();

        address unregisteredPayee = makeAddr("unregisteredPayee");
        vm.prank(unregisteredPayee);
        vm.expectRevert(abi.encodeWithSelector(PaymentVerifier.AgentNotRegistered.selector, unregisteredPayee));
        verifier.verifyPayment(paymentId, execAgent, amount, token, deadline, sig);
    }

    /*//////////////////////////////////////////////////////////////
                           FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_uniquePaymentIds(bytes32 id1, bytes32 id2) public {
        vm.assume(id1 != id2);

        uint256 amount = 1e6;
        address token = makeAddr("usdc");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash1 =
            keccak256(abi.encodePacked(id1, execAgent, signalAgent, amount, token, deadline)).toEthSignedMessageHash();
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(payerKey, hash1);

        bytes32 hash2 =
            keccak256(abi.encodePacked(id2, execAgent, signalAgent, amount, token, deadline)).toEthSignedMessageHash();
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(payerKey, hash2);

        vm.prank(signalAgent);
        verifier.verifyPayment(id1, execAgent, amount, token, deadline, abi.encodePacked(r1, s1, v1));

        vm.prank(signalAgent);
        verifier.verifyPayment(id2, execAgent, amount, token, deadline, abi.encodePacked(r2, s2, v2));

        assertTrue(verifier.isPaymentVerified(id1));
        assertTrue(verifier.isPaymentVerified(id2));
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _buildValidPayment()
        internal
        returns (bytes32 paymentId, uint256 amount, address token, uint256 deadline, bytes memory sig)
    {
        paymentId = keccak256("payment_001");
        amount = 1e6; // 1 USDC
        token = makeAddr("usdc");
        deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(abi.encodePacked(paymentId, execAgent, signalAgent, amount, token, deadline))
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, hash);
        sig = abi.encodePacked(r, s, v);
    }
}
