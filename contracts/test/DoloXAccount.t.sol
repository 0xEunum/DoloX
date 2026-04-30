// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DoloXAccount} from "../src/core/DoloXAccount.sol";
import {DoloXAccountFactory} from "../src/core/DoloXAccountFactory.sol";
import {PackedUserOperation} from "../src/core/EntryPoint.sol";
import {MockEntryPoint} from "../src/mocks/MockEntryPoint.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract DoloXAccountTest is Test {
    using MessageHashUtils for bytes32;

    DoloXAccount account;
    DoloXAccountFactory factory;
    MockEntryPoint entryPoint;
    MockERC20 token;

    address owner;
    uint256 ownerKey;
    address stranger = makeAddr("stranger");

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");

        entryPoint = new MockEntryPoint();
        factory = new DoloXAccountFactory(address(entryPoint));
        account = DoloXAccount(payable(factory.createAccount(owner, 1)));
        token = new MockERC20("Mock USDC", "mUSDC", 6, address(this));

        // Fund account
        vm.deal(address(account), 1 ether);
        token.mint(address(account), 1000e6);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test_deployedCorrectly() public view {
        assertEq(account.owner(), owner);
        assertEq(address(account.entryPoint()), address(entryPoint));
    }

    function test_create2_sameAddressForSameOwnerAndSalt() public view {
        address predicted = factory.getAddress(owner, 1);
        assertEq(predicted, address(account));
    }

    function test_create2_differentSaltGivesDifferentAddress() public view {
        address addr1 = factory.getAddress(owner, 1);
        address addr2 = factory.getAddress(owner, 2);
        assertNotEq(addr1, addr2);
    }

    function test_createAccount_idempotent() public {
        // Calling createAccount again with same params returns existing account
        address second = address(factory.createAccount(owner, 1));
        assertEq(second, address(account));
    }

    /*//////////////////////////////////////////////////////////////
                        SIGNATURE VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_validateUserOp_validSignature() public {
        bytes32 userOpHash = keccak256("test_op");
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        PackedUserOperation memory op = _buildUserOp(sig);

        vm.prank(address(entryPoint));
        uint256 result = account.validateUserOp(op, userOpHash, 0);
        assertEq(result, 0); // SIG_VALIDATION_SUCCESS
    }

    function test_validateUserOp_onlyEntryPoint() public {
        PackedUserOperation memory op = _buildUserOp("");

        vm.prank(stranger);
        vm.expectRevert(DoloXAccount.NotEntryPoint.selector);
        account.validateUserOp(op, bytes32(0), 0);
    }

    function test_validateUserOp_prefundsPayed() public {
        bytes32 userOpHash = keccak256("test_op");
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        PackedUserOperation memory op = _buildUserOp(sig);

        uint256 missingFunds = 0.01 ether;
        uint256 entryPointBefore = address(entryPoint).balance;

        vm.prank(address(entryPoint));
        account.validateUserOp(op, userOpHash, missingFunds);

        assertEq(address(entryPoint).balance, entryPointBefore + missingFunds);
    }

    /*//////////////////////////////////////////////////////////////
                              EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_execute_byOwner() public {
        address target = makeAddr("target");
        vm.deal(target, 0);

        vm.prank(owner);
        account.execute(target, 0.1 ether, "");

        assertEq(target.balance, 0.1 ether);
    }

    function test_execute_byEntryPoint() public {
        address target = makeAddr("target");

        vm.prank(address(entryPoint));
        account.execute(target, 0.1 ether, "");

        assertEq(target.balance, 0.1 ether);
    }

    function test_execute_revertIfNotAuthorized() public {
        vm.prank(stranger);
        vm.expectRevert(DoloXAccount.NotEntryPointOrOwner.selector);
        account.execute(stranger, 0, "");
    }

    function test_execute_revertOnFailedCall() public {
        // Deploy a contract that always reverts
        RevertingContract reverter = new RevertingContract();

        vm.prank(owner);
        vm.expectRevert();
        account.execute(address(reverter), 0, abi.encodeCall(RevertingContract.fail, ()));
    }

    /*//////////////////////////////////////////////////////////////
                           EXECUTE BATCH
    //////////////////////////////////////////////////////////////*/

    function test_executeBatch_multipleTargets() public {
        address t1 = makeAddr("t1");
        address t2 = makeAddr("t2");

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        targets[0] = t1;
        values[0] = 0.1 ether;
        datas[0] = "";
        targets[1] = t2;
        values[1] = 0.2 ether;
        datas[1] = "";

        vm.prank(owner);
        account.executeBatch(targets, values, datas);

        assertEq(t1.balance, 0.1 ether);
        assertEq(t2.balance, 0.2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           TOKEN OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function test_withdrawToken() public {
        uint256 amount = 100e6;
        vm.prank(owner);
        account.withdrawToken(address(token), owner, amount);
        assertEq(token.balanceOf(owner), amount);
    }

    function test_withdrawToken_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(DoloXAccount.NotOwner.selector);
        account.withdrawToken(address(token), stranger, 100e6);
    }

    function test_withdrawETH() public {
        uint256 amount = 0.5 ether;
        uint256 before = owner.balance;

        vm.prank(owner);
        account.withdrawETH(payable(owner), amount);

        assertEq(owner.balance, before + amount);
    }

    /*//////////////////////////////////////////////////////////////
                           OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_transferOwnership() public {
        vm.prank(owner);
        account.transferOwnership(stranger);
        assertEq(account.owner(), stranger);
    }

    function test_transferOwnership_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DoloXAccount.ZeroAddress.selector);
        account.transferOwnership(address(0));
    }

    function test_transferOwnership_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(DoloXAccount.NotOwner.selector);
        account.transferOwnership(stranger);
    }

    /*//////////////////////////////////////////////////////////////
                              RECEIVE
    //////////////////////////////////////////////////////////////*/

    function test_receiveETH() public {
        uint256 before = address(account).balance;
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(account).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(account).balance, before + 0.5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_execute_ethTransfer(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 1 ether);
        address target = makeAddr("fuzz_target");

        vm.prank(owner);
        account.execute(target, amount, "");
        assertEq(target.balance, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             HELPERS
    //////////////////////////////////////////////////////////////*/

    function _buildUserOp(bytes memory sig) internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: sig
        });
    }
}

contract RevertingContract {
    function fail() external pure {
        revert("always fails");
    }
}
