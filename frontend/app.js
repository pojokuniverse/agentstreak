// ============================================================
// AgentStreak frontend — vanilla JS + ethers v6, no build step.
// Wallet access uses the standard injected provider
// (window.ethereum) only. There is NO QR-code / pairing-code
// login anywhere in this app, by design.
// ============================================================

const CONFIG = {
  // SET AFTER DEPLOY: replace this placeholder with the deployed
  // AgentStreak contract address on BNB Chain (chainId 56).
  contractAddress: "0x3AFDC52cAeB3440f085F7A35F6423F23adE34Ce2",
  chainId: 56,
  chainIdHex: "0x38",
  chainName: "BNB Smart Chain",
  rpcUrl: "https://bsc-dataseed.bnbchain.org",
  explorer: "https://bscscan.com",
};

const AGENT_STREAK_ABI = [
  "function checkIn()",
  "function vouch(address target)",
  "function hasAgentID(address account) view returns (bool)",
  "function statsOf(address account) view returns (uint256 totalCheckIns, uint256 currentStreak, uint256 bestStreak, uint256 points, uint256 vouchesReceived, uint256 lastDay)",
  "function badgeLevel(address account) view returns (uint8)",
  "function userCount() view returns (uint256)",
  "function totalCheckInsGlobal() view returns (uint256)",
  "function totalVouchesGlobal() view returns (uint256)",
  "function users(uint256 index) view returns (address)",
];

const BADGES = ["None", "Bronze", "Silver", "Gold", "Diamond"];

let provider = null;
let signer = null;
let account = null;
let contract = null;

const $ = (id) => document.getElementById(id);

function setStatus(msg, kind) {
  const el = $("status");
  el.textContent = msg || "";
  el.className = kind || "";
}

function shortAddr(a) {
  return a ? a.slice(0, 6) + "…" + a.slice(-4) : "";
}

function isConfigured() {
  return CONFIG.contractAddress !== "0x0000000000000000000000000000000000000000";
}

async function ensureBscNetwork() {
  const current = await window.ethereum.request({ method: "eth_chainId" });
  if (current === CONFIG.chainIdHex) return;
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: CONFIG.chainIdHex }],
    });
  } catch (err) {
    // 4902 = chain not added to the wallet yet.
    if (err && err.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: CONFIG.chainIdHex,
          chainName: CONFIG.chainName,
          rpcUrls: [CONFIG.rpcUrl],
          nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
          blockExplorerUrls: [CONFIG.explorer],
        }],
      });
    } else {
      throw err;
    }
  }
}

async function connect() {
  if (!window.ethereum) {
    setStatus("No injected wallet found. Install a Web3 wallet extension or open this page in a wallet browser, then reload.", "err");
    return;
  }
  try {
    setStatus("Connecting…");
    await ensureBscNetwork();
    provider = new ethers.BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    if (!accounts || accounts.length === 0) {
      setStatus("No account was shared by the wallet.", "err");
      return;
    }
    signer = await provider.getSigner();
    account = await signer.getAddress();
    contract = new ethers.Contract(CONFIG.contractAddress, AGENT_STREAK_ABI, signer);

    $("connectBtn").textContent = shortAddr(account);
    $("walletLine").innerHTML =
      'Connected: <span class="mono">' + account + "</span> on BNB Smart Chain (56).";

    if (!isConfigured()) {
      setStatus("Wallet connected, but the contract address is still the placeholder. Set CONFIG.contractAddress in app.js after deployment.", "err");
    } else {
      setStatus("Wallet connected.", "ok");
    }
    await refresh();
  } catch (err) {
    console.error(err);
    setStatus("Connection failed: " + (err.shortMessage || err.message || String(err)), "err");
  }
}

async function todayUtcDay() {
  // Use the chain's latest block timestamp so "today" matches the contract.
  const block = await provider.getBlock("latest");
  return Math.floor(Number(block.timestamp) / 86400);
}

async function refresh() {
  if (!contract || !account) return;
  try {
    const [holds, stats, badge] = await Promise.all([
      contract.hasAgentID(account),
      contract.statsOf(account),
      contract.badgeLevel(account),
    ]);

    const pill = $("agentIdPill");
    pill.textContent = holds ? "Agent ID held ✓" : "No Agent ID";
    pill.className = "pill " + (holds ? "ok" : "no");

    const total = Number(stats.totalCheckIns);
    const current = Number(stats.currentStreak);
    const best = Number(stats.bestStreak);
    const points = Number(stats.points);
    const vouches = Number(stats.vouchesReceived);
    const lastDay = Number(stats.lastDay);

    $("statStreak").textContent = current;
    $("statBest").textContent = best;
    $("statTotal").textContent = total;
    $("statPoints").textContent = points;
    $("statVouches").textContent = vouches;
    const badgeEl = $("statBadge");
    badgeEl.textContent = BADGES[Number(badge)] || "None";
    badgeEl.className = "value badge-" + Number(badge);

    // Check-in button state, with an explicit reason when disabled.
    const btn = $("checkInBtn");
    const reason = $("checkInReason");
    const today = await todayUtcDay();
    if (!isConfigured()) {
      btn.disabled = true;
      reason.textContent = "Contract address not set yet (see CONFIG in app.js).";
    } else if (!holds) {
      btn.disabled = true;
      reason.textContent = "You need an Agent ID to check in. Agent IDs are claimed inside the Binance app (Wallet → Agent ID banner).";
    } else if (lastDay === today && total > 0) {
      btn.disabled = true;
      reason.textContent = "Already checked in today — come back tomorrow (UTC) to extend your streak.";
    } else {
      btn.disabled = false;
      reason.textContent = current > 0 && lastDay === today - 1
        ? "Checking in today extends your streak to " + (current + 1) + "."
        : "";
    }

    $("vouchBtn").disabled = !holds || !isConfigured();
    $("vouchReason").textContent = holds
      ? ""
      : "You need an Agent ID to vouch for someone.";

    await refreshGlobals();
    await refreshLeaderboard();
  } catch (err) {
    console.error(err);
    setStatus("Could not read the contract: " + (err.shortMessage || err.message || String(err)), "err");
  }
}

async function refreshGlobals() {
  const [users, checkIns, vouches] = await Promise.all([
    contract.userCount(),
    contract.totalCheckInsGlobal(),
    contract.totalVouchesGlobal(),
  ]);
  $("globalUsers").textContent = Number(users);
  $("globalCheckIns").textContent = Number(checkIns);
  $("globalVouches").textContent = Number(vouches);
}

async function refreshLeaderboard() {
  const body = $("leaderboardBody");
  const count = Number(await contract.userCount());
  const limit = Math.min(count, 100);
  if (limit === 0) {
    body.innerHTML = '<tr><td colspan="6" class="muted">No agents have checked in yet. Be the first.</td></tr>';
    return;
  }
  const rows = [];
  for (let i = 0; i < limit; i++) {
    const addr = await contract.users(i);
    const [stats, badge] = await Promise.all([
      contract.statsOf(addr),
      contract.badgeLevel(addr),
    ]);
    rows.push({
      address: addr,
      points: Number(stats.points),
      streak: Number(stats.currentStreak),
      vouches: Number(stats.vouchesReceived),
      badge: Number(badge),
    });
  }
  rows.sort((a, b) => b.points - a.points);
  body.innerHTML = rows.map((r, i) =>
    "<tr><td>" + (i + 1) + "</td>" +
    '<td class="addr">' + shortAddr(r.address) + "</td>" +
    "<td>" + r.points + "</td>" +
    "<td>" + r.streak + "</td>" +
    "<td>" + r.vouches + "</td>" +
    '<td class="badge-' + r.badge + '">' + BADGES[r.badge] + "</td></tr>"
  ).join("");
}

async function doCheckIn() {
  try {
    setStatus("Sending check-in transaction — confirm it in your wallet…");
    const tx = await contract.checkIn();
    setStatus("Transaction sent: " + tx.hash + " — waiting for confirmation…");
    await tx.wait();
    setStatus("Checked in. See you tomorrow to keep the streak alive.", "ok");
    await refresh();
  } catch (err) {
    console.error(err);
    setStatus("Check-in failed: " + (err.shortMessage || err.message || String(err)), "err");
  }
}

async function doVouch() {
  const target = $("vouchAddress").value.trim();
  if (!ethers.isAddress(target)) {
    $("vouchReason").textContent = "That does not look like a valid address.";
    return;
  }
  if (target.toLowerCase() === account.toLowerCase()) {
    $("vouchReason").textContent = "You cannot vouch for yourself.";
    return;
  }
  try {
    const targetHolds = await contract.hasAgentID(target);
    if (!targetHolds) {
      $("vouchReason").textContent = "That address does not hold an Agent ID, so it cannot receive a vouch.";
      return;
    }
    setStatus("Sending vouch transaction — confirm it in your wallet…");
    const tx = await contract.vouch(target);
    await tx.wait();
    setStatus("Vouched for " + shortAddr(target) + ". They received +5 points.", "ok");
    $("vouchAddress").value = "";
    await refresh();
  } catch (err) {
    console.error(err);
    setStatus("Vouch failed: " + (err.shortMessage || err.message || String(err)), "err");
  }
}

document.addEventListener("DOMContentLoaded", () => {
  $("connectBtn").addEventListener("click", connect);
  $("checkInBtn").addEventListener("click", doCheckIn);
  $("vouchBtn").addEventListener("click", doVouch);

  if (window.ethereum) {
    window.ethereum.on("accountsChanged", () => window.location.reload());
    window.ethereum.on("chainChanged", () => window.location.reload());
  } else {
    setStatus("No injected wallet detected on this page.", "err");
  }
});
