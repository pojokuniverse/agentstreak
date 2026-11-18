// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentStreak} from "../contracts/AgentStreak.sol";

/// @notice Minimal script interface — no forge-std dependency.
/// @dev forge provides the Script base behaviour through the cheatcode/runtime
///      layer for `forge script`; to stay dependency-free this file uses the
///      Vm cheatcodes directly for broadcasting.
interface Vm {
    function envUint(string calldata name) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys AgentStreak wired to the REAL Agent ID contract on BNB Chain.
///
/// Usage (deployment is NOT part of the build task — run manually when ready):
///   PRIVATE_KEY=<deployer key> forge script script/Deploy.s.sol \
///     --rpc-url https://bsc-dataseed.bnbchain.org --broadcast
///
/// The deployer key is read from the PRIVATE_KEY environment variable only.
/// It is never hardcoded, never committed, and never printed.
contract Deploy {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev SPACE ID Agent ID on BNB Chain (ERC-721, non-transferable).
    address internal constant AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external returns (AgentStreak streak) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        streak = new AgentStreak(AGENT_ID);
        vm.stopBroadcast();
        return streak;
    }
}
