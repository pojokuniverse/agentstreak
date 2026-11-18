// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentStreak} from "../contracts/AgentStreak.sol";

/// @notice Minimal cheatcode interface — no forge-std dependency.
interface Vm {
    function prank(address msgSender) external;
    function expectRevert() external;
    function skip(bool skipTest) external;
}

/// @notice Fork tests against BSC mainnet using the REAL Agent ID contract.
/// @dev Run with: forge test --match-contract AgentStreakFork \
///        --fork-url https://bsc-dataseed.bnbchain.org
///      Without a fork the real Agent ID address has no code in the local EVM,
///      so every test here skips itself and plain `forge test` still passes.
contract AgentStreakForkTest {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address internal constant REAL_AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    /// @dev Verified Agent ID holder (balanceOf = 1).
    address internal constant HOLDER = 0x52A0a5b71F586087b248e5f9EC04D989212096eC;
    /// @dev Verified non-holder (balanceOf = 0).
    address internal constant NON_HOLDER = 0xC1C069E3Ff11f60F9e7a0e6ACd5F5Ebbbf0C9E22;

    function _deployOrSkip() internal returns (AgentStreak streak) {
        if (REAL_AGENT_ID.code.length == 0) {
            vm.skip(true);
            // vm.skip reverts internally when it actually skips; the lines
            // below are only reached in environments where skip is a no-op.
            return AgentStreak(address(0));
        }
        return new AgentStreak(REAL_AGENT_ID);
    }

    function testForkRealGateReads() public {
        AgentStreak streak = _deployOrSkip();
        if (address(streak) == address(0)) return;
        require(streak.hasAgentID(HOLDER), "fork: holder should pass the gate");
        require(!streak.hasAgentID(NON_HOLDER), "fork: non-holder should fail the gate");
    }

    function testForkHolderCheckInSucceeds() public {
        AgentStreak streak = _deployOrSkip();
        if (address(streak) == address(0)) return;

        vm.prank(HOLDER);
        streak.checkIn();

        (uint256 total, uint256 current,,,,) = streak.statsOf(HOLDER);
        require(total == 1, "fork: holder totalCheckIns should be 1");
        require(current == 1, "fork: holder currentStreak should be 1");
    }

    function testForkNonHolderCheckInReverts() public {
        AgentStreak streak = _deployOrSkip();
        if (address(streak) == address(0)) return;

        vm.prank(NON_HOLDER);
        vm.expectRevert();
        streak.checkIn();
    }
}
