// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentRegistry} from "./AgentRegistry.sol";

/// @title ReputationManager
/// @notice Tracks on-chain reputation for DoloX agents.
///         Score increases on successful swaps + fulfilled x402 requests.
///         Score decreases on failed execution attempts.
contract ReputationManager {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error NotAuthorized();
    error AgentNotRegistered(address account);
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event ReputationUpdated(
        address indexed account, uint256 indexed agentId, int256 delta, uint256 newScore, ReputationEvent eventType
    );
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/
    enum ReputationEvent {
        SWAP_SUCCESS, // +10 — agent executed a successful Uniswap swap
        SIGNAL_FULFILLED, // +5  — signal agent fulfilled an x402 request
        SWAP_FAILED, // -5  — agent attempted swap but failed
        SIGNAL_INVALID, // -3  — signal agent returned bad data
        MANUAL_ADJUSTMENT // admin adjustment
    }

    struct ReputationScore {
        uint256 score; // current score (starts at 100)
        uint256 totalSwaps;
        uint256 successfulSwaps;
        uint256 totalSignals;
        uint256 fulfilledSignals;
        uint256 lastUpdated;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Reputation points per event
    int256 public constant SWAP_SUCCESS_POINTS = 10;
    int256 public constant SIGNAL_FULFILLED_POINTS = 5;
    int256 public constant SWAP_FAILED_POINTS = -5;
    int256 public constant SIGNAL_INVALID_POINTS = -3;
    uint256 public constant INITIAL_SCORE = 100;
    uint256 public constant MAX_SCORE = 1000;

    AgentRegistry public immutable registry;
    address public owner;

    // account => reputation score
    mapping(address => ReputationScore) public scores;

    // Only these contracts can update reputation (SwapExecutor, x402 verifier)
    mapping(address => bool) public authorizedCallers;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _registry, address _owner) {
        if (_registry == address(0) || _owner == address(0)) revert ZeroAddress();
        registry = AgentRegistry(_registry);
        owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize reputation for a newly registered agent
    /// @dev Called by AgentRegistry after registration (or manually)
    function initializeAgent(address account) external onlyAuthorized {
        if (!registry.isRegistered(account)) revert AgentNotRegistered(account);
        if (scores[account].lastUpdated == 0) {
            scores[account] = ReputationScore({
                score: INITIAL_SCORE,
                totalSwaps: 0,
                successfulSwaps: 0,
                totalSignals: 0,
                fulfilledSignals: 0,
                lastUpdated: block.timestamp
            });
        }
    }

    /// @notice Record a reputation event for an agent
    /// @param account The DoloXAccount address
    /// @param eventType The type of event (swap success, signal fulfilled, etc.)
    function recordEvent(address account, ReputationEvent eventType) external onlyAuthorized {
        if (!registry.isRegistered(account)) revert AgentNotRegistered(account);

        ReputationScore storage rep = scores[account];
        if (rep.lastUpdated == 0) {
            rep.score = INITIAL_SCORE;
        }

        int256 delta = _getDelta(eventType);
        _updateStats(rep, eventType);
        _applyDelta(rep, delta);

        AgentRegistry.Agent memory agent = registry.getAgent(account);
        emit ReputationUpdated(account, agent.agentId, delta, rep.score, eventType);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN
    //////////////////////////////////////////////////////////////*/

    function addAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function getScore(address account) external view returns (uint256) {
        return scores[account].lastUpdated == 0 ? INITIAL_SCORE : scores[account].score;
    }

    function getFullScore(address account) external view returns (ReputationScore memory) {
        return scores[account];
    }

    function getSuccessRate(address account) external view returns (uint256) {
        ReputationScore memory rep = scores[account];
        if (rep.totalSwaps == 0) return 100;
        return (rep.successfulSwaps * 100) / rep.totalSwaps;
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _getDelta(ReputationEvent eventType) internal pure returns (int256) {
        if (eventType == ReputationEvent.SWAP_SUCCESS) return SWAP_SUCCESS_POINTS;
        if (eventType == ReputationEvent.SIGNAL_FULFILLED) return SIGNAL_FULFILLED_POINTS;
        if (eventType == ReputationEvent.SWAP_FAILED) return SWAP_FAILED_POINTS;
        if (eventType == ReputationEvent.SIGNAL_INVALID) return SIGNAL_INVALID_POINTS;
        return 0;
    }

    function _updateStats(ReputationScore storage rep, ReputationEvent eventType) internal {
        if (eventType == ReputationEvent.SWAP_SUCCESS) {
            rep.totalSwaps++;
            rep.successfulSwaps++;
        } else if (eventType == ReputationEvent.SWAP_FAILED) {
            rep.totalSwaps++;
        } else if (eventType == ReputationEvent.SIGNAL_FULFILLED) {
            rep.totalSignals++;
            rep.fulfilledSignals++;
        } else if (eventType == ReputationEvent.SIGNAL_INVALID) {
            rep.totalSignals++;
        }
        rep.lastUpdated = block.timestamp;
    }

    function _applyDelta(ReputationScore storage rep, int256 delta) internal {
        int256 current = int256(rep.score);
        int256 updated = current + delta;
        // Floor at 0, cap at MAX_SCORE
        if (updated < 0) updated = 0;
        if (updated > int256(MAX_SCORE)) updated = int256(MAX_SCORE);
        rep.score = uint256(updated);
    }
}
