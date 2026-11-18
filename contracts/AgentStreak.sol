// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface for the SPACE ID Agent ID contract (ERC-721, non-transferable).
/// @dev Agent ID contract on BNB Chain: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentStreak
/// @notice A daily check-in streak and peer-vouching board gated entirely by Binance
///         Wallet Agent ID. Every state-changing function requires the caller (and,
///         for vouches, the target) to hold an Agent ID.
///
///         The contract has NO owner and NO admin functions: no pause, no withdraw,
///         no mint, no tax, no upgrade path. It holds no funds, moves no tokens, and
///         never asks for approvals. Points and badges are non-transferable reputation
///         records only — they are not tokens and carry no monetary value.
contract AgentStreak {
    /// @notice The Agent ID contract used for the holder gate.
    IAgentID public immutable agentID;

    struct UserStats {
        uint256 lastDay; // UTC day number of the last check-in (block.timestamp / 86400); 0 = never
        uint256 currentStreak; // consecutive days, including the most recent check-in day
        uint256 bestStreak; // longest streak ever reached
        uint256 totalCheckIns; // lifetime check-in count
        uint256 points; // reputation points (check-ins, milestones, vouches received)
        uint256 vouchesReceived; // number of distinct peers who vouched for this user
        bool registered; // true once the user has checked in at least once
    }

    mapping(address => UserStats) private _stats;
    mapping(address => mapping(address => bool)) private _hasVouched; // caller => target => done

    /// @notice Every address that has ever checked in, in first-check-in order.
    address[] public users;

    uint256 private _totalCheckInsGlobal;
    uint256 private _totalVouchesGlobal;

    event CheckedIn(address indexed user, uint256 day, uint256 currentStreak, uint256 totalCheckIns, uint256 points);
    event Vouched(address indexed from, address indexed to, uint256 receiverVouchCount);

    constructor(address agentID_) {
        require(agentID_ != address(0), "AgentStreak: zero agent id");
        agentID = IAgentID(agentID_);
    }

    // ------------------------------------------------------------------ views

    /// @notice True if `account` holds at least one Agent ID.
    function hasAgentID(address account) public view returns (bool) {
        return agentID.balanceOf(account) > 0;
    }

    /// @notice Full stats for a user, in a stable field order for the frontend.
    function statsOf(address account)
        external
        view
        returns (
            uint256 totalCheckIns,
            uint256 currentStreak,
            uint256 bestStreak,
            uint256 points,
            uint256 vouchesReceived,
            uint256 lastDay
        )
    {
        UserStats storage s = _stats[account];
        return (s.totalCheckIns, s.currentStreak, s.bestStreak, s.points, s.vouchesReceived, s.lastDay);
    }

    /// @notice Badge level from best streak: 0 none, 1 Bronze (>=3), 2 Silver (>=7),
    ///         3 Gold (>=14), 4 Diamond (>=30).
    function badgeLevel(address account) external view returns (uint8) {
        uint256 best = _stats[account].bestStreak;
        if (best >= 30) return 4;
        if (best >= 14) return 3;
        if (best >= 7) return 2;
        if (best >= 3) return 1;
        return 0;
    }

    function userCount() external view returns (uint256) {
        return users.length;
    }

    function totalCheckInsGlobal() external view returns (uint256) {
        return _totalCheckInsGlobal;
    }

    function totalVouchesGlobal() external view returns (uint256) {
        return _totalVouchesGlobal;
    }

    // ----------------------------------------------------------------- writes

    /// @notice Check in for today (UTC). One check-in per address per UTC day.
    /// @dev Points: +10 per check-in, plus a one-time-per-streak milestone bonus
    ///      when the current streak reaches 3 (+20), 7 (+50), 14 (+100), 30 (+250).
    function checkIn() external {
        require(hasAgentID(msg.sender), "AgentStreak: no Agent ID");

        uint256 today = block.timestamp / 86400;
        UserStats storage s = _stats[msg.sender];

        require(s.lastDay != today, "AgentStreak: already checked in today");

        if (!s.registered) {
            s.registered = true;
            users.push(msg.sender);
        }

        // Consecutive day extends the streak; any gap restarts it at 1.
        // (lastDay == 0 can only mean "never checked in", because a real
        // check-in day is always > 0.)
        if (s.lastDay != 0 && today == s.lastDay + 1) {
            s.currentStreak += 1;
        } else {
            s.currentStreak = 1;
        }
        s.lastDay = today;

        if (s.currentStreak > s.bestStreak) {
            s.bestStreak = s.currentStreak;
        }

        s.totalCheckIns += 1;
        _totalCheckInsGlobal += 1;

        uint256 gained = 10;
        if (s.currentStreak == 3) gained += 20;
        else if (s.currentStreak == 7) gained += 50;
        else if (s.currentStreak == 14) gained += 100;
        else if (s.currentStreak == 30) gained += 250;
        s.points += gained;

        emit CheckedIn(msg.sender, today, s.currentStreak, s.totalCheckIns, s.points);
    }

    /// @notice Vouch for another Agent ID holder. One vouch per (caller, target) pair.
    /// @dev The receiver earns +5 points and +1 vouchesReceived. The caller earns nothing,
    ///      which keeps vouching an honest signal rather than a farming loop.
    function vouch(address target) external {
        require(hasAgentID(msg.sender), "AgentStreak: no Agent ID");
        require(target != msg.sender, "AgentStreak: cannot vouch for yourself");
        require(hasAgentID(target), "AgentStreak: target has no Agent ID");
        require(!_hasVouched[msg.sender][target], "AgentStreak: already vouched");

        _hasVouched[msg.sender][target] = true;

        UserStats storage t = _stats[target];
        t.vouchesReceived += 1;
        t.points += 5;
        _totalVouchesGlobal += 1;

        emit Vouched(msg.sender, target, t.vouchesReceived);
    }
}
