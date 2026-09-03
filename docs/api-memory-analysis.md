# API memory analysis — @actual-app/api consumption

> Branch: `pr/api-memory-analysis`. Date: 2026-09-03.
> Status: **not implemented** — pending review.

## Context

Production host: Oracle Cloud Ampere A1 (`aarch64`), Docker via Dokploy.
Memory limit: 512 MB. At `-mx=9 -md=32m` the 7z process peaks at ~168 MB,
but the full container reaches ~315 MB. The **7z compression is not the
dominant consumer — the API is**.

## What the script does

`s.download-actual-budget.js` calls `@actual-app/api` in this order:

```js
await api.init({ dataDir, serverURL, password });   // line 54
await api.downloadBudget(syncId, ...);             // line 57 — loads entire budget into memory
await api.getAccounts();                            // line 59 — RETRIEVES ALL ACCOUNTS, result DISCARDED
await api.shutdown();
```

The `getAccounts()` call on line 59 returns an array of `Account` objects,
**which is immediately discarded**. This call loads account data into the
API's internal state and allocates memory for the full array — for nothing.

## Memory breakdown (aarch64, production)

| Component | Approximate peak |
|---|---|
| `@actual-app/api` internal state (budget load) | ~140–150 MB |
| `getAccounts()` allocation (discarded) | ~10–50 MB |
| 7z compression at `-mx=9 -md=32m` | ~168 MB |
| Node.js runtime overhead | ~20–30 MB |
| **Total (observed)** | **~315 MB** |

The 7z process alone peaks at 168 MB inside the container. The remaining
~150 MB comes from the API loading the budget, not from compression.

## Quick wins

### 1. Remove the useless `getAccounts()` call

**File:** `scripts/download-actual-budget.js`, line 59.

```diff
- await api.getAccounts();
```

Savings: ~10–50 MB (account data that is loaded and immediately discarded).
Risk: none — the result is not used anywhere.

### 2. Lower the zip compression level (if using zip format)

**File:** `scripts/download-actual-budget.js`, line 34.

```diff
- return `cd ${sourceDir} && 7z a -tzip -mx=9 ${pwFlag} "${zipPath}" .`;
+ return `cd ${sourceDir} && 7z a -tzip -mx=5 ${pwFlag} "${zipPath}" .`;
```

Savings: similar to the 7z fix — ~20–30 MB on peak RSS.
Risk: slightly larger archives (typically <5% size difference at level 5 vs 9
for LZMA2). The main savings are in the API, not the compressor.

### 3. Combine both quick wins

Both changes together save ~30–80 MB. Not enough to reach 256 MB,
but adds margin to the 512 MB limit and reduces OOM risk.

## Architectural solution: offload download to rclone

The root cause is that `@actual-app/api.downloadBudget()` loads the entire
budget into the container's memory. A proper fix would eliminate the API
from the backup container entirely.

### Concept

The Actual server itself exposes an HTTP API. Instead of using `@actual-app/api`
inside the backup container, the container could:

1. Call the Actual server's internal HTTP API to trigger an export
   (or use the Actual HTTP API directly if exposed externally).
2. Have `rclone copy` pull the exported file from the server.

This would move the entire budget download out of the backup container,
eliminating ~140–150 MB of API memory usage from the container entirely.

### Requirements to investigate

- Is the Actual server's HTTP API accessible from the backup container?
  (internal Docker network or external URL)
- Does Actual have a REST endpoint to export a budget file directly?
  (`exportBudget()` returns `Uint8Array` in the JS API — no native file
  streaming)
- Could the budget be exported to a file on the Actual server's host
  and retrieved via `rclone`?
- Authentication: the Actual HTTP API uses the same password as the web UI.

### Difficulty

This is a **medium-to-large change**: it requires understanding the Actual
server's HTTP API surface, the network topology between containers, and
 potentially adding new environment variables (`ACTUAL_SERVER_URL`,
 `ACTUAL_BUDGET_PASSWORD` for HTTP auth, etc.).

It is the correct long-term solution if the goal is to run the backup
container at 256 MB or below.

## Summary

| Action | Effort | RAM savings | Status |
|---|---|---|---|
| Remove `getAccounts()` call | 1 line | ~10–50 MB | Pending review |
| Lower zip `-mx` to 5 | 1 line | ~20–30 MB | Pending review |
| Both quick wins combined | 2 lines | ~30–80 MB | Pending review |
| Offload download to rclone | Medium–Large | ~140–150 MB | Needs investigation |

The quick wins are worth doing regardless — they cost nothing and reduce
memory pressure. The rclone approach is the real solution for a 256 MB
target.
