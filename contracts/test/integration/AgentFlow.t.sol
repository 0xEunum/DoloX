// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DoloXAccount} from "../../src/core/DoloXAccount.sol";
import {DoloXAccountFactory} from "../../src/core/DoloXAccountFactory.sol";
import {AgentRegistry} from "../../src/registry/AgentRegistry.sol";
import {ReputationManager} from "../../src/registry/ReputationManager.sol";
import {PaymentVerifier} from "../../src/execution/PaymentVerifier.sol";
import {MockEntryPoint} from "../../src/mocks/MockEntryPoint.sol";
import {MockERC8004Registry} from "../../src/mocks/MockERC8004Registry.sol";
import {MockBasenamesController} from "../../src/mocks/MockBasenamesController.sol";
import {MockBasenamesResolver} from "../../src/mocks/MockBasenamesResolver.sol";
import {PackedUserOperation} from "../../src/core/EntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @notice Full A2A integration test - manual setup, no scripts, no broadcasts
///         Mirrors the exact DoloX runtime flow:
///         Deploy -> Register agents -> x402 payment proof -> ERC-4337 UserOp execution
contract AgentFlowTest is Test {
    using MessageHashUtils for bytes32;

    /*//////////////////////////////////////////////////////////////
                            PROTOCOL CONTRACTS
    //////////////////////////////////////////////////////////////*/
    MockEntryPoint entryPoint;
    DoloXAccountFactory factory;
    AgentRegistry registry;
    ReputationManager reputation;
    PaymentVerifier paymentVerifier;
    MockERC8004Registry erc8004;
    MockBasenamesController basenamesController;
    MockBasenamesResolver basenamesResolver;

    /*//////////////////////////////////////////////////////////////
                                AGENTS
    //////////////////////////////////////////////////////////////*/
    DoloXAccount signalAccount;
    DoloXAccount execAccount;

    /*//////////////////////////////////////////////////////////////
                                 KEYS
    //////////////////////////////////////////////////////////////*/
    address protocolOwner;
    uint256 protocolOwnerKey;

    address signalOwner;
    uint256 signalOwnerKey;

    address execOwner;
    uint256 execOwnerKey;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        (protocolOwner, protocolOwnerKey) = makeAddrAndKey("protocolOwner");
        (signalOwner, signalOwnerKey) = makeAddrAndKey("signalOwner");
        (execOwner, execOwnerKey) = makeAddrAndKey("execOwner");

        vm.deal(protocolOwner, 10 ether);
        vm.deal(signalOwner, 10 ether);
        vm.deal(execOwner, 10 ether);

        // ── Step 1: Deploy all protocol contracts (no broadcast, just new) ──
        entryPoint = new MockEntryPoint();
        erc8004 = new MockERC8004Registry();
        basenamesController = new MockBasenamesController();
        basenamesResolver = new MockBasenamesResolver();

        factory = new DoloXAccountFactory(address(entryPoint));
        registry = new AgentRegistry(address(erc8004), protocolOwner);
        reputation = new ReputationManager(address(registry), protocolOwner);
        paymentVerifier = new PaymentVerifier(address(registry), address(reputation));

        // ── Step 2: Wire permissions ───────────────────────────────────────
        vm.startPrank(protocolOwner);
        reputation.addAuthorizedCaller(address(paymentVerifier));
        reputation.addAuthorizedCaller(protocolOwner);
        vm.stopPrank();

        // ── Step 3: Deploy + register Signal Agent ─────────────────────────
        address signalAddr = factory.getAddress(signalOwner, 1);
        signalAccount = DoloXAccount(payable(signalAddr));

        factory.createAccount(signalOwner, 1);

        vm.prank(signalOwner);
        registry.registerAgent(signalAddr, "dolox-signal.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(protocolOwner);
        reputation.initializeAgent(signalAddr);

        // ── Step 4: Deploy + register Exec Agent ──────────────────────────
        address execAddr = factory.getAddress(execOwner, 2);
        execAccount = DoloXAccount(payable(execAddr));

        factory.createAccount(execOwner, 2);

        vm.prank(execOwner);
        registry.registerAgent(execAddr, "dolox-exec.base.eth", AgentRegistry.AgentType.EXECUTION);

        vm.prank(protocolOwner);
        reputation.initializeAgent(execAddr);

        // ── Fund smart accounts ────────────────────────────────────────────
        vm.deal(address(signalAccount), 1 ether);
        vm.deal(address(execAccount), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 1: PROTOCOL DEPLOYED CORRECTLY
    //////////////////////////////////////////////////////////////*/
    function test_protocolDeployedCorrectly() public view {
        assertEq(address(factory.entryPoint()), address(entryPoint));
        assertEq(address(reputation.registry()), address(registry));
        assertEq(address(paymentVerifier.registry()), address(registry));
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 2: AGENTS REGISTERED CORRECTLY
    //////////////////////////////////////////////////////////////*/
    function test_agentsRegisteredCorrectly() public view {
        assertTrue(registry.isRegistered(address(signalAccount)));
        assertTrue(registry.isRegistered(address(execAccount)));

        AgentRegistry.Agent memory signal = registry.getAgent(address(signalAccount));
        AgentRegistry.Agent memory exec = registry.getAgent(address(execAccount));

        assertEq(signal.ensName, "dolox-signal.base.eth");
        assertEq(exec.ensName, "dolox-exec.base.eth");
        assertEq(signal.agentId, 1);
        assertEq(exec.agentId, 2);
        assertEq(signal.owner, signalOwner);
        assertEq(exec.owner, execOwner);
        assertEq(uint8(signal.agentType), uint8(AgentRegistry.AgentType.SIGNAL));
        assertEq(uint8(exec.agentType), uint8(AgentRegistry.AgentType.EXECUTION));
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 3: STARTING REPUTATION SCORES
    //////////////////////////////////////////////////////////////*/
    function test_startingReputationScores() public view {
        assertEq(reputation.getScore(address(signalAccount)), 100);
        assertEq(reputation.getScore(address(execAccount)), 100);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 4: CREATE2 ADDRESS PREDICTION
    //////////////////////////////////////////////////////////////*/
    function test_create2AddressPrediction() public view {
        address predictedSignal = factory.getAddress(signalOwner, 1);
        address predictedExec = factory.getAddress(execOwner, 2);

        assertEq(predictedSignal, address(signalAccount));
        assertEq(predictedExec, address(execAccount));
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 5: X402 PAYMENT PROOF (A2A PAYMENT)
    //////////////////////////////////////////////////////////////*/
    function test_x402PaymentFlow() public {
        bytes32 paymentId = keccak256("payment_001");
        uint256 amount = 1e6; // 1 USDC
        address token = makeAddr("usdc");
        uint256 deadline = block.timestamp + 1 hours;

        // ExecOwner signs the payment proof
        bytes32 hash = keccak256(
                abi.encodePacked(
                    paymentId,
                    address(execAccount), // payer
                    address(signalAccount), // payee
                    amount,
                    token,
                    deadline
                )
            ).toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(execOwnerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // SignalAgent submits payment proof -> PaymentVerifier
        vm.prank(address(signalAccount));
        paymentVerifier.verifyPayment(paymentId, address(execAccount), amount, token, deadline, sig);

        // Payment is verified
        assertTrue(paymentVerifier.isPaymentVerified(paymentId));

        // Signal agent reputation increased by +5 (SIGNAL_FULFILLED)
        assertEq(reputation.getScore(address(signalAccount)), 105);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 6: X402 REPLAY PROTECTION
    //////////////////////////////////////////////////////////////*/
    function test_x402ReplayProtection() public {
        bytes32 paymentId = keccak256("payment_replay");
        uint256 amount = 1e6;
        address token = makeAddr("usdc");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(
                abi.encodePacked(paymentId, address(execAccount), address(signalAccount), amount, token, deadline)
            ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(execOwnerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(address(signalAccount));
        paymentVerifier.verifyPayment(paymentId, address(execAccount), amount, token, deadline, sig);

        // Replay attempt
        vm.prank(address(signalAccount));
        vm.expectRevert(abi.encodeWithSelector(PaymentVerifier.PaymentAlreadyVerified.selector, paymentId));
        paymentVerifier.verifyPayment(paymentId, address(execAccount), amount, token, deadline, sig);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 7: ERC-4337 USEROP VALIDATION + EXECUTION
    //////////////////////////////////////////////////////////////*/
    function test_erc4337UserOpFlow() public {
        address callTarget = makeAddr("callTarget");
        vm.deal(callTarget, 0);

        // Build and sign UserOp for ExecAgent
        bytes32 userOpHash = keccak256("exec_swap_userop_001");
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(execOwnerKey, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        PackedUserOperation memory op = PackedUserOperation({
            sender: address(execAccount),
            nonce: 0,
            initCode: "",
            callData: abi.encodeCall(DoloXAccount.execute, (callTarget, 0.1 ether, "")),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: sig
        });

        // EntryPoint validates signature
        vm.prank(address(entryPoint));
        uint256 validation = execAccount.validateUserOp(op, userOpHash, 0);
        assertEq(validation, 0); // SIG_VALIDATION_SUCCESS

        // EntryPoint calls execute
        vm.prank(address(entryPoint));
        execAccount.execute(callTarget, 0.1 ether, "");

        assertEq(callTarget.balance, 0.1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 8: AGENT ISOLATION (CANNOT SPEND OTHER'S FUNDS)
    //////////////////////////////////////////////////////////////*/
    function test_agentIsolation_cannotControlOtherAgent() public {
        // execOwner tries to call signalAccount directly
        vm.prank(execOwner);
        vm.expectRevert(DoloXAccount.NotEntryPointOrOwner.selector);
        signalAccount.execute(execOwner, 0.5 ether, "");
    }

    function test_agentIsolation_wrongSignatureFails() public {
        bytes32 userOpHash = keccak256("wrong_sig_test");
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();

        // Sign with signalOwner's key but validate against execAccount
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signalOwnerKey, ethHash);
        bytes memory wrongSig = abi.encodePacked(r, s, v);

        PackedUserOperation memory op = PackedUserOperation({
            sender: address(execAccount),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: wrongSig
        });

        vm.prank(address(entryPoint));
        uint256 result = execAccount.validateUserOp(op, userOpHash, 0);
        assertEq(result, 1); // SIG_VALIDATION_FAILED
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 9: FULL A2A FLOW (ALL STEPS COMBINED)
    //////////////////////////////////////////////////////////////*/
    function test_fullA2AFlow() public {
        console2.log("=== Full DoloX A2A Flow ===");

        // ── Step 1: Verify both agents are live ───────────────
        assertTrue(registry.isRegistered(address(signalAccount)));
        assertTrue(registry.isRegistered(address(execAccount)));
        console2.log("Both agents registered");

        // ── Step 2: ExecAgent resolves SignalAgent via ENS ────
        // (simulated - in production this is a viem call)
        string memory resolvedName = registry.getAgent(address(signalAccount)).ensName;
        assertEq(resolvedName, "dolox-signal.base.eth");
        console2.log("SignalAgent resolved:", resolvedName);

        // ── Step 3: ExecAgent pays SignalAgent via x402 ───────
        bytes32 paymentId = keccak256("a2a_payment");
        uint256 amount = 1e6;
        address token = makeAddr("usdc");
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 hash = keccak256(
                abi.encodePacked(paymentId, address(execAccount), address(signalAccount), amount, token, deadline)
            ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(execOwnerKey, hash);

        vm.prank(address(signalAccount));
        paymentVerifier.verifyPayment(
            paymentId, address(execAccount), amount, token, deadline, abi.encodePacked(r, s, v)
        );
        console2.log("x402 payment verified");

        // ── Step 4: SignalAgent reputation updated ─────────────
        assertEq(reputation.getScore(address(signalAccount)), 105);
        console2.log("SignalAgent reputation:", reputation.getScore(address(signalAccount)));

        // ── Step 5: ExecAgent executes UserOp ─────────────────
        bytes32 userOpHash = keccak256("a2a_userop");
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(execOwnerKey, ethHash);

        vm.prank(address(entryPoint));
        uint256 validation = execAccount.validateUserOp(
            PackedUserOperation({
                sender: address(execAccount),
                nonce: 0,
                initCode: "",
                callData: "",
                accountGasLimits: bytes32(0),
                preVerificationGas: 0,
                gasFees: bytes32(0),
                paymasterAndData: "",
                signature: abi.encodePacked(r2, s2, v2)
            }),
            userOpHash,
            0
        );
        assertEq(validation, 0);
        console2.log("UserOp validated - ExecAgent authorized");

        console2.log("=== A2A Flow Complete ===");
    }
}
