// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/registry/AgentRegistry.sol";
import {MockERC8004Registry} from "../src/mocks/MockERC8004Registry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry registry;
    MockERC8004Registry erc8004;

    address owner = makeAddr("owner");
    address agent1 = makeAddr("agent1");
    address agent2 = makeAddr("agent2");
    address stranger = makeAddr("stranger");

    function setUp() public {
        erc8004 = new MockERC8004Registry();
        registry = new AgentRegistry(address(erc8004), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function test_registerAgent_success() public {
        vm.prank(owner);
        uint256 id = registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        assertEq(id, 1);
        assertEq(registry.totalAgents(), 1);
        assertTrue(registry.isRegistered(agent1));
    }

    function test_registerAgent_incrementsId() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(owner);
        uint256 id2 = registry.registerAgent(agent2, "exec-dolox.base.eth", AgentRegistry.AgentType.EXECUTION);

        assertEq(id2, 2);
        assertEq(registry.totalAgents(), 2);
    }

    function test_registerAgent_storesCorrectData() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.account, agent1);
        assertEq(a.owner, owner);
        assertEq(a.ensName, "signal-dolox.base.eth");
        assertTrue(a.active);
        assertEq(uint8(a.agentType), uint8(AgentRegistry.AgentType.SIGNAL));
    }

    function test_registerAgent_revertDuplicate() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentAlreadyRegistered.selector, agent1));
        registry.registerAgent(agent1, "signal-dolox-2.base.eth", AgentRegistry.AgentType.SIGNAL);
    }

    function test_registerAgent_revertDuplicateEnsName() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(owner);
        vm.expectRevert();
        registry.registerAgent(agent2, "signal-dolox.base.eth", AgentRegistry.AgentType.EXECUTION);
    }

    function test_registerAgent_revertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AgentRegistry.ZeroAddress.selector);
        registry.registerAgent(address(0), "test.base.eth", AgentRegistry.AgentType.SIGNAL);
    }

    function test_registerAgent_revertEmptyEnsName() public {
        vm.prank(owner);
        vm.expectRevert(AgentRegistry.EmptyENSName.selector);
        registry.registerAgent(agent1, "", AgentRegistry.AgentType.SIGNAL);
    }

    /*//////////////////////////////////////////////////////////////
                            DEACTIVATION
    //////////////////////////////////////////////////////////////*/

    function test_deactivateAgent() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(owner);
        registry.deactivateAgent(agent1);

        assertFalse(registry.isRegistered(agent1));
    }

    function test_deactivateAgent_revertNotOwner() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(stranger);
        vm.expectRevert();
        registry.deactivateAgent(agent1);
    }

    function test_deactivateAgent_revertNotRegistered() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, agent1));
        registry.deactivateAgent(agent1);
    }

    /*//////////////////////////////////////////////////////////////
                           ENS NAME UPDATE
    //////////////////////////////////////////////////////////////*/

    function test_updateEnsName() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(owner);
        registry.updateEnsName(agent1, "signal-v2.base.eth");

        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.ensName, "signal-v2.base.eth");
    }

    function test_updateEnsName_clearsOldMapping() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        vm.prank(owner);
        registry.updateEnsName(agent1, "signal-v2.base.eth");

        // Old name should resolve to zero
        assertEq(registry.ensNameToAccount("signal-dolox.base.eth"), address(0));
        // New name should resolve to agent1
        assertEq(registry.ensNameToAccount("signal-v2.base.eth"), agent1);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_getOwnerAgents() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);
        vm.prank(owner);
        registry.registerAgent(agent2, "exec-dolox.base.eth", AgentRegistry.AgentType.EXECUTION);

        address[] memory agents = registry.getOwnerAgents(owner);
        assertEq(agents.length, 2);
        assertEq(agents[0], agent1);
        assertEq(agents[1], agent2);
    }

    function test_resolveEnsToAccount() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        assertEq(registry.resolveEnsToAccount("signal-dolox.base.eth"), agent1);
    }

    function test_getAgent_revertNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, agent1));
        registry.getAgent(agent1);
    }

    function test_agentIdToAccount() public {
        vm.prank(owner);
        registry.registerAgent(agent1, "signal-dolox.base.eth", AgentRegistry.AgentType.SIGNAL);

        assertEq(registry.agentIdToAccount(1), agent1);
    }

    /*//////////////////////////////////////////////////////////////
                           FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_registerMultipleAgents(uint8 count) public {
        vm.assume(count > 0 && count < 20);
        for (uint8 i = 0; i < count; i++) {
            address a = makeAddr(string(abi.encodePacked("agent", i)));
            string memory name = string(abi.encodePacked("agent-", vm.toString(i), ".base.eth"));
            vm.prank(owner);
            registry.registerAgent(a, name, AgentRegistry.AgentType.SIGNAL);
        }
        assertEq(registry.totalAgents(), count);
    }
}
