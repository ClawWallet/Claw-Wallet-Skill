---
name: claw-wallet-explorer
description: "Use public chain explorers as a visual fallback for wallet activity, balances, and transaction inspection when RPC/indexer data is slow or incomplete."
---

## Use this skill when...

Use this skill when the user wants a human-readable view of wallet activity while sandbox RPC refresh is still in progress.

Use this skill when the user wants to verify a specific address, token, or transaction on a public explorer.

Use this skill when the user wants an explanation based on explorer pages, rather than raw RPC fields.

## Positioning

This skill is a fallback and augmentation layer.

- Primary source for machine decisions remains the local sandbox API and its cached wallet state.
- Explorer data is best for visual confirmation, investigation, and user-facing drill-down.
- Do not rely on explorer scraping alone for signing, policy checks, or transaction authorization.

## Preferred flow

1. Query the local sandbox first:
   - `GET {CLAY_SANDBOX_URL}/api/v1/wallet/status`
   - `GET {CLAY_SANDBOX_URL}/api/v1/wallet/assets`
   - `GET {CLAY_SANDBOX_URL}/api/v1/wallet/history`
2. If `asset_refresh_state` shows a slow chain is still refreshing, tell the user that cached data is being shown.
3. Offer the explorer link for the chain/address/tx so the user can inspect the latest on-chain state visually.
4. When the sandbox refresh completes, prefer sandbox data again.

## Explorer map

- `ethereum`
  - address: `https://etherscan.io/address/<address>`
  - tx: `https://etherscan.io/tx/<hash>`
- `base`
  - address: `https://basescan.org/address/<address>`
  - tx: `https://basescan.org/tx/<hash>`
- `bsc`
  - address: `https://bscscan.com/address/<address>`
  - tx: `https://bscscan.com/tx/<hash>`
- `arbitrum`
  - address: `https://arbiscan.io/address/<address>`
  - tx: `https://arbiscan.io/tx/<hash>`
- `optimism`
  - address: `https://optimistic.etherscan.io/address/<address>`
  - tx: `https://optimistic.etherscan.io/tx/<hash>`
- `polygon`
  - address: `https://polygonscan.com/address/<address>`
  - tx: `https://polygonscan.com/tx/<hash>`
- `0g`
  - address: `https://chainscan.0g.ai/address/<address>`
  - tx: `https://chainscan.0g.ai/tx/<hash>`
- `monad`
  - address: `https://monadvision.com/address/<address>`
  - tx: `https://monadvision.com/tx/<hash>`
- `solana`
  - address: `https://solscan.io/account/<address>`
  - tx: `https://solscan.io/tx/<hash>`
- `sui`
  - address: `https://suivision.xyz/account/<address>`
  - tx: `https://suivision.xyz/txblock/<hash>`
- `bitcoin`
  - address: `https://mempool.space/address/<address>`
  - tx: `https://mempool.space/tx/<hash>`

## Agent guidance

- If the user asks "why is this taking so long", check `asset_refresh_state` first.
- If a slow chain is inflight, say so directly and provide the explorer URL.
- If sandbox history is empty but the explorer clearly shows recent activity, report that the explorer has newer visible data and the sandbox cache is still catching up.
- If the user wants a confirmation before signing or transferring, never substitute explorer data for policy enforcement.

## Suggested user-facing wording

- `0g is still refreshing in the background, so I'm showing cached wallet data for now.`
- `If you want the latest visible state immediately, open this explorer page: <url>.`
- `Once the sandbox refresh finishes, I can re-check the cached balances/history and compare them.`
