# AgentStreak

**Show up every day.** AgentStreak is a daily check-in streak and peer-vouching
board for Binance Wallet **Agent ID** holders, built for the Agent ID Hackathon
on BNB Chain.

Every day (UTC), an Agent ID holder can check in once. Consecutive days build a
streak; streaks earn reputation points, milestone bonuses, and badges
(Bronze → Silver → Gold → Diamond). Holders can also **vouch** for each other —
one vouch per pair of agents, ever — as a lightweight on-chain trust signal
between agents.

Points and badges are reputation records stored in the contract. They are
**not tokens**: they cannot be transferred, traded, or redeemed, and this
project makes no promise of any return or reward for participating.

## How Agent ID is integrated

Agent ID is the SPACE ID Agent ID ERC-721 on BNB Chain
(`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`, non-transferable, one per user).
AgentStreak takes that contract address as a constructor argument and gates
**every** state-changing function on it:

- `checkIn()` — reverts unless `balanceOf(msg.sender) > 0` on the Agent ID contract.
- `vouch(target)` — reverts unless the **caller** holds an Agent ID, the
  **target** holds an Agent ID, target ≠ caller, and this caller has not
  already vouched for this target.
- `hasAgentID(address)` exposes the same gate as a view for the frontend and
  other contracts.

There is no other way in: no allowlist, no signatures, no admin override.

## Contract design

`contracts/AgentStreak.sol` is a single, dependency-free Solidity
(`^0.8.20`) contract:

- **No owner.** There is no owner address stored and no admin function of any
  kind — no pause, no withdraw, no mint, no tax setting, no upgrade path.
- **No funds.** The contract has no payable functions and never receives,
  holds, or moves BNB or tokens.
- **No transfers or approvals.** The contract never calls `transfer`,
  `transferFrom`, or `approve` on anything. It only *reads* `balanceOf` from
  the Agent ID contract.
- **No token.** Points and badges exist only as numbers in contract storage.

### Mechanics

| Action | Effect |
| --- | --- |
| Check in (once per UTC day) | +10 points; streak +1 if yesterday, otherwise streak resets to 1 |
| Streak milestone 3 / 7 / 14 / 30 | +20 / +50 / +100 / +250 bonus points (once per streak run) |
| Receive a vouch | +5 points, +1 vouches received |
| Badge (from best streak) | Bronze ≥ 3, Silver ≥ 7, Gold ≥ 14, Diamond ≥ 30 |

Views: `statsOf`, `badgeLevel`, `userCount`, `totalCheckInsGlobal`,
`totalVouchesGlobal`, `hasAgentID`, and the public `users` array
(first-check-in order) that powers the leaderboard.

## Repository layout

```
contracts/AgentStreak.sol        the contract (no imports, no owner)
test/AgentStreak.t.sol           unit tests with a mock Agent ID
test/AgentStreakFork.t.sol       fork tests against the real Agent ID contract
script/Deploy.s.sol              deployment script (key from env only)
frontend/index.html              single-page dApp (plain CSS, dark theme)
frontend/app.js                  vanilla JS + ethers v6 via CDN
```

## Build and test locally

Requires [Foundry](https://book.getfoundry.sh/) (forge 1.5.x used in development).

```bash
forge build
forge test            # 15 unit tests; fork tests skip themselves without a fork
```

Fork tests against BSC mainnet and the real Agent ID contract:

```bash
forge test --match-contract AgentStreakFork \
  --fork-url https://bsc-dataseed.bnbchain.org
```

The fork tests verify that a known real Agent ID holder can check in through
the deployed-gate contract and that a known non-holder is rejected.

## Frontend

No build step. Serve the `frontend/` folder with any static server:

```bash
cd frontend && python3 -m http.server 8000
```

Wallet connection uses the standard injected provider (`window.ethereum`)
only — there is intentionally **no QR-code or pairing-code login**. The app
asks the wallet to switch to BNB Smart Chain (chainId 56), shows the connected
wallet's Agent ID status and stats, and provides check-in, vouching, global
stats, and a points leaderboard.

## Deployment

> **Deployed on BNB Smart Chain (chainId 56) — 2026-11-18.**
>
> - **AgentStreak:** `0x3AFDC52cAeB3440f085F7A35F6423F23adE34Ce2`
> - Deploy tx: `0x146bb7c4069f0c264336a5988424cc698a4fbca8dabb13a05bf032236f9db9f2`
> - Wired to the real Agent ID contract
>   (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`); `hasAgentID` gate verified
>   live on-chain after deployment.
> - BscScan: https://bscscan.com/address/0x3AFDC52cAeB3440f085F7A35F6423F23adE34Ce2
>   (source verified on BscScan 2026-11-18 — "Pass - Verified" via Etherscan API V2,
  GUID s8subfhzw7vq4yduy3lznmcge33kbukpdjnma4fixtlfgahw2p; also Sourcify exact_match)

To redeploy (e.g. a fresh instance):

1. Set the deployer key in the environment (never commit it):
   `export PRIVATE_KEY=<deployer private key>`
2. Simulate first (no broadcast):
   `forge script script/Deploy.s.sol --fork-url https://bsc-dataseed.bnbchain.org`
3. Broadcast when ready:
   `forge script script/Deploy.s.sol --rpc-url https://bsc-dataseed.bnbchain.org --broadcast`
4. Verify the source on BscScan and record the deployed address here.
5. Put the deployed address into `CONFIG.contractAddress` at the top of
   `frontend/app.js`.

## License

MIT — see [LICENSE](LICENSE).
