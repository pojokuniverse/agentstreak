// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentStreak, IAgentID} from "../contracts/AgentStreak.sol";

/// @notice Minimal cheatcode interface — avoids a forge-std dependency so the
///         project builds with zero external libraries.
interface Vm {
    function warp(uint256 newTimestamp) external;
    function prank(address msgSender) external;
    function expectRevert() external;
    function skip(bool skipTest) external;
}

/// @notice Tiny Agent ID stand-in: mint() grants a balance of 1.
contract MockAgentID is IAgentID {
    mapping(address => uint256) private _balances;

    function mint(address to) external {
        _balances[to] = 1;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return _balances[owner];
    }
}

contract AgentStreakTest {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    MockAgentID internal mock;
    AgentStreak internal streak;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);
    address internal nobody = address(0xDEAD);

    uint256 internal constant T0 = 1_700_000_000; // fixed start time

    function setUp() public {
        vm.warp(T0);
        mock = new MockAgentID();
        streak = new AgentStreak(address(mock));
        mock.mint(alice);
        mock.mint(bob);
        mock.mint(carol);
        // `nobody` intentionally holds no Agent ID.
    }

    // ------------------------------------------------------------ assertions

    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        if (a != b) {
            revert(string(abi.encodePacked("assertEq failed: ", what)));
        }
    }

    function assertTrue(bool cond, string memory what) internal pure {
        if (!cond) revert(string(abi.encodePacked("assertTrue failed: ", what)));
    }

    function assertFalse(bool cond, string memory what) internal pure {
        if (cond) revert(string(abi.encodePacked("assertFalse failed: ", what)));
    }

    // -------------------------------------------------------------- check-in

    function testNonHolderCheckInReverts() public {
        vm.prank(nobody);
        vm.expectRevert();
        streak.checkIn();
    }

    function testHolderCheckInWorks() public {
        vm.prank(alice);
        streak.checkIn();

        (uint256 total, uint256 current, uint256 best, uint256 points, uint256 vouches, uint256 lastDay) =
            streak.statsOf(alice);
        assertEq(total, 1, "totalCheckIns");
        assertEq(current, 1, "currentStreak");
        assertEq(best, 1, "bestStreak");
        assertEq(points, 10, "points");
        assertEq(vouches, 0, "vouchesReceived");
        assertEq(lastDay, T0 / 86400, "lastDay");
        assertEq(streak.userCount(), 1, "userCount");
        assertEq(streak.totalCheckInsGlobal(), 1, "totalCheckInsGlobal");
        assertTrue(streak.users(0) == alice, "users[0] is alice");
        assertTrue(streak.hasAgentID(alice), "hasAgentID(alice)");
        assertFalse(streak.hasAgentID(nobody), "hasAgentID(nobody)");
    }

    function testSecondCheckInSameDayReverts() public {
        vm.prank(alice);
        streak.checkIn();

        vm.prank(alice);
        vm.expectRevert();
        streak.checkIn();
    }

    function testNextDayCheckInIncrementsStreak() public {
        vm.prank(alice);
        streak.checkIn();

        vm.warp(T0 + 86400);
        vm.prank(alice);
        streak.checkIn();

        (uint256 total, uint256 current, uint256 best, uint256 points,,) = streak.statsOf(alice);
        assertEq(total, 2, "totalCheckIns");
        assertEq(current, 2, "currentStreak");
        assertEq(best, 2, "bestStreak");
        assertEq(points, 20, "points");
        // Second check-in on a later day must not duplicate the users entry.
        assertEq(streak.userCount(), 1, "userCount still 1");
    }

    function testMissedDayResetsStreakKeepsTotalAndBest() public {
        vm.prank(alice);
        streak.checkIn(); // day 0: streak 1

        vm.warp(T0 + 86400);
        vm.prank(alice);
        streak.checkIn(); // day 1: streak 2

        vm.warp(T0 + 3 * 86400); // skip day 2 entirely
        vm.prank(alice);
        streak.checkIn(); // day 3: streak resets to 1

        (uint256 total, uint256 current, uint256 best, uint256 points,,) = streak.statsOf(alice);
        assertEq(total, 3, "totalCheckIns kept");
        assertEq(current, 1, "currentStreak reset");
        assertEq(best, 2, "bestStreak kept");
        assertEq(points, 30, "points kept accumulating");
    }

    function testMilestonePointsAtStreak3() public {
        vm.prank(alice);
        streak.checkIn(); // 10 pts, streak 1

        vm.warp(T0 + 86400);
        vm.prank(alice);
        streak.checkIn(); // 20 pts, streak 2

        vm.warp(T0 + 2 * 86400);
        vm.prank(alice);
        streak.checkIn(); // +10 base +20 milestone = 50 pts, streak 3

        (,, uint256 best, uint256 points,,) = streak.statsOf(alice);
        assertEq(best, 3, "bestStreak 3");
        assertEq(points, 50, "points include streak-3 milestone bonus");
    }

    function testMilestonePointsAtStreak7() public {
        for (uint256 i = 0; i < 7; i++) {
            vm.warp(T0 + i * 86400);
            vm.prank(alice);
            streak.checkIn();
        }
        // 7*10 base + 20 (day 3) + 50 (day 7) = 140
        (uint256 total, uint256 current,, uint256 points,,) = streak.statsOf(alice);
        assertEq(total, 7, "totalCheckIns 7");
        assertEq(current, 7, "currentStreak 7");
        assertEq(points, 140, "points include streak-7 milestone bonus");
    }

    // ----------------------------------------------------------------- vouch

    function testVouchWorksAndPaysReceiver() public {
        vm.prank(alice);
        streak.vouch(bob);

        (uint256 total, , , uint256 points, uint256 vouches,) = streak.statsOf(bob);
        assertEq(total, 0, "receiver need not have checked in");
        assertEq(vouches, 1, "vouchesReceived");
        assertEq(points, 5, "receiver points +5");
        assertEq(streak.totalVouchesGlobal(), 1, "totalVouchesGlobal");
    }

    function testVouchNonHolderCallerReverts() public {
        vm.prank(nobody);
        vm.expectRevert();
        streak.vouch(bob);
    }

    function testVouchNonHolderTargetReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        streak.vouch(nobody);
    }

    function testSelfVouchReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        streak.vouch(alice);
    }

    function testDuplicateVouchReverts() public {
        vm.prank(alice);
        streak.vouch(bob);

        vm.prank(alice);
        vm.expectRevert();
        streak.vouch(bob);
    }

    function testDifferentCallersCanVouchSameTarget() public {
        vm.prank(alice);
        streak.vouch(bob);
        vm.prank(carol);
        streak.vouch(bob);

        (,,, uint256 points, uint256 vouches,) = streak.statsOf(bob);
        assertEq(vouches, 2, "two distinct vouches");
        assertEq(points, 10, "points 2 x 5");
        assertEq(streak.totalVouchesGlobal(), 2, "totalVouchesGlobal 2");
    }

    // ----------------------------------------------------------------- badge

    function testBadgeLevelThresholds() public {
        assertEq(streak.badgeLevel(alice), 0, "no streak = level 0");

        // Walk a 30-day streak, checking each threshold as it is crossed.
        for (uint256 i = 0; i < 30; i++) {
            vm.warp(T0 + i * 86400);
            vm.prank(alice);
            streak.checkIn();

            uint256 day = i + 1;
            if (day == 2) assertEq(streak.badgeLevel(alice), 0, "streak 2 still level 0");
            if (day == 3) assertEq(streak.badgeLevel(alice), 1, "streak 3 = Bronze");
            if (day == 7) assertEq(streak.badgeLevel(alice), 2, "streak 7 = Silver");
            if (day == 14) assertEq(streak.badgeLevel(alice), 3, "streak 14 = Gold");
            if (day == 30) assertEq(streak.badgeLevel(alice), 4, "streak 30 = Diamond");
        }

        // Points: 30*10 base + 20 + 50 + 100 + 250 milestones = 720.
        (,,, uint256 points,,) = streak.statsOf(alice);
        assertEq(points, 720, "points across all milestones");
    }

    function testBadgeSurvivesStreakReset() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(T0 + i * 86400);
            vm.prank(alice);
            streak.checkIn();
        }
        assertEq(streak.badgeLevel(alice), 1, "Bronze at streak 3");

        vm.warp(T0 + 10 * 86400); // long gap: current streak resets, best stays
        vm.prank(alice);
        streak.checkIn();

        (uint256 total, uint256 current, uint256 best,,,) = streak.statsOf(alice);
        assertEq(current, 1, "current reset");
        assertEq(best, 3, "best kept");
        assertEq(total, 4, "total kept");
        assertEq(streak.badgeLevel(alice), 1, "badge kept from best streak");
    }
}
