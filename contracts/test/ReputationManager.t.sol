// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReputationManager} from "../src/registry/ReputationManager.sol";
import {AgentRegistry} from "../src/registry/AgentRegistry.sol";
import {MockERC8004Registry} from "../src/mocks/MockERC8004Registry.sol";

contract ReputationManagerTest is Test {
    ReputationManager reputation;
    AgentRegistry registry;
    MockERC8004Registry erc8004;

    address owner = makeAddr("owner");
    address agent = makeAddr("agent");
    address authorizedCaller = makeAddr("authorizedCaller");
    address stranger = makeAddr("stranger");

    function setUp() public {
        erc8004 = new MockERC8004Registry();
        registry = new AgentRegistry(address(erc8004), owner);
        reputation = new ReputationManager(address(registry), owner);

        // Register agent
        vm.prank(owner);
        registry.registerAgent(agent, "dolox-signal.base.eth", AgentRegistry.AgentType.SIGNAL);

        // Authorize caller
        vm.prank(owner);
        reputation.addAuthorizedCaller(authorizedCaller);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_initializeAgent() public {
        vm.prank(authorizedCaller);
        reputation.initializeAgent(agent);

        assertEq(reputation.getScore(agent), 100);
    }

    function test_initializeAgent_onlyAuthorized() public {
        vm.prank(stranger);
        vm.expectRevert(ReputationManager.NotAuthorized.selector);
        reputation.initializeAgent(agent);
    }

    function test_initializeAgent_revertIfNotRegistered() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(ReputationManager.AgentNotRegistered.selector, stranger));
        reputation.initializeAgent(stranger);
    }

    function test_initializeAgent_idempotent() public {
        vm.prank(authorizedCaller);
        reputation.initializeAgent(agent);

        // Second call should not reset score
        vm.prank(authorizedCaller);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);

        uint256 scoreAfterSwap = reputation.getScore(agent);

        vm.prank(authorizedCaller);
        reputation.initializeAgent(agent); // call again

        assertEq(reputation.getScore(agent), scoreAfterSwap); // not reset
    }

    /*//////////////////////////////////////////////////////////////
                          RECORD EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_recordEvent_swapSuccess() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        vm.stopPrank();

        assertEq(reputation.getScore(agent), 110); // 100 + 10
    }

    function test_recordEvent_signalFulfilled() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SIGNAL_FULFILLED);
        vm.stopPrank();

        assertEq(reputation.getScore(agent), 105); // 100 + 5
    }

    function test_recordEvent_swapFailed() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_FAILED);
        vm.stopPrank();

        assertEq(reputation.getScore(agent), 95); // 100 - 5
    }

    function test_recordEvent_signalInvalid() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SIGNAL_INVALID);
        vm.stopPrank();

        assertEq(reputation.getScore(agent), 97); // 100 - 3
    }

    function test_recordEvent_scoreFloorIsZero() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        // Drain score below 0 by repeated failures
        for (uint256 i = 0; i < 25; i++) {
            reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_FAILED);
        }
        vm.stopPrank();

        assertEq(reputation.getScore(agent), 0); // never goes negative
    }

    function test_recordEvent_scoreCappedAtMax() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        // Pump score past MAX_SCORE (1000)
        for (uint256 i = 0; i < 100; i++) {
            reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        }
        vm.stopPrank();

        assertEq(reputation.getScore(agent), 1000); // capped at MAX_SCORE
    }

    function test_recordEvent_onlyAuthorized() public {
        vm.prank(authorizedCaller);
        reputation.initializeAgent(agent);

        vm.prank(stranger);
        vm.expectRevert(ReputationManager.NotAuthorized.selector);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
    }

    /*//////////////////////////////////////////////////////////////
                           STATS TRACKING
    //////////////////////////////////////////////////////////////*/

    function test_stats_swapSuccessTracked() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_FAILED);
        vm.stopPrank();

        ReputationManager.ReputationScore memory score = reputation.getFullScore(agent);
        assertEq(score.totalSwaps, 3);
        assertEq(score.successfulSwaps, 2);
    }

    function test_stats_signalTracked() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SIGNAL_FULFILLED);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SIGNAL_INVALID);
        vm.stopPrank();

        ReputationManager.ReputationScore memory score = reputation.getFullScore(agent);
        assertEq(score.totalSignals, 2);
        assertEq(score.fulfilledSignals, 1);
    }

    function test_getSuccessRate_perfect() public {
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        vm.stopPrank();

        assertEq(reputation.getSuccessRate(agent), 100);
    }

    function test_getSuccessRate_noSwaps() public view {
        assertEq(reputation.getSuccessRate(agent), 100); // default 100% with no swaps
    }

    /*//////////////////////////////////////////////////////////////
                         AUTHORIZED CALLERS
    //////////////////////////////////////////////////////////////*/

    function test_addAuthorizedCaller_onlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(ReputationManager.NotAuthorized.selector);
        reputation.addAuthorizedCaller(stranger);
    }

    function test_removeAuthorizedCaller() public {
        vm.prank(owner);
        reputation.removeAuthorizedCaller(authorizedCaller);

        vm.prank(authorizedCaller);
        vm.expectRevert(ReputationManager.NotAuthorized.selector);
        reputation.initializeAgent(agent);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_scoreNeverNegative(uint8 failures) public {
        vm.assume(failures > 0);
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        for (uint8 i = 0; i < failures; i++) {
            reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_FAILED);
        }
        vm.stopPrank();
        assertGe(reputation.getScore(agent), 0);
    }

    function testFuzz_scoreNeverExceedsMax(uint8 successes) public {
        vm.assume(successes > 0);
        vm.startPrank(authorizedCaller);
        reputation.initializeAgent(agent);
        for (uint8 i = 0; i < successes; i++) {
            reputation.recordEvent(agent, ReputationManager.ReputationEvent.SWAP_SUCCESS);
        }
        vm.stopPrank();
        assertLe(reputation.getScore(agent), 1000);
    }
}
