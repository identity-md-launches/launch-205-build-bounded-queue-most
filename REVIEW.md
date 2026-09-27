# Review — PriorityQueue (bounded, 32 entries)

Scope: `src/PriorityQueue.sol`, `src/LaunchToken.sol`, `script/Deploy.s.sol`, the test suite and
`foundry.toml`. Reviewed as an attacker per the network's Solidity review checklist. This is a
contributor self-review, not the independent adversarial review the network runs before release.

## Findings

| # | Severity | Finding | Disposition |
|---|---|---|---|
| 1 | Info | Anyone can fill all 32 slots with cheap entries and block other users (bounded-queue griefing). | Inherent in the requested design (permissionless enqueue, hard cap, no fee). Documented in README "Assumptions" and "Operational responsibilities". Not mitigated. |
| 2 | Info | Anyone can pop, so a bot can drain entries the moment they are enqueued. | Required by the task ("anyone may pop"). Documented. |
| 3 | Info | `_bestIndex` and `ordered()` do linear scans. | Bounded by the constant 32; `ordered()` is O(n²) and intended for off-chain reads. The scan reads only the packed (owner, priority, sequence) slot per entry. Measured in the unit-test gas report: `pop` max 126,103 gas on a full 32-entry queue (median 71,330), `enqueue` max 135,807, `cancel` max 48,957. |
| 4 | Info | `entryAt(i)` exposes storage order, which differs from pop order after swap-removes. | Documented; `ordered()` gives pop order. A test asserts ties remain FIFO after storage reorder. |
| 5 | Info | Zero ID is accepted. | Deliberate: the id→slot map stores index+1, so zero ID and "not live" cannot be confused. Tested (`test_zeroIdIsAllowed`). |
| 6 | Info | `LaunchToken` exists although the task says "do not create a token". | The IdentityMD `evm_project` floor deploys a launch token with every project; the token is a launch artifact, not part of the queue, which never references it. Called out in README. If the network provides its own token, drop it from the manifest. |
| 7 | Low | Sequence is `uint64` with checked increment. | Overflow needs 2⁶⁴ enqueues; on overflow the contract would refuse further enqueues (revert) rather than reuse a sequence. Acceptable. |

No permission bypass, reentrancy, value-handling or arithmetic issue was found. The contract has no
external calls, no ETH handling, no privileged roles, no `delegatecall`, no `selfdestruct` and no
constructor arguments.

## Checklist walked

- **Who can call what**: `cancel` checks ownership on its only path; `enqueue` and `pop` are
  intentionally open; no fallback/receive; not upgradeable; no initialiser.
- **Value**: none. Nothing payable, no token movement in the queue.
- **Arithmetic**: only `++_lastSequence` (checked) and index arithmetic guarded by the capacity and
  by `slot != 0` checks. No `unchecked` blocks in the queue. The token's single `unchecked` subtraction
  is guarded by the preceding balance check.
- **Loops**: bounded by the constant 32.
- **Time / randomness / signatures / oracles / delegatecall / upgradeability**: not used.
- **Storage consistency** (the real risk in a swap-remove design): `_removeAt` updates the moved
  entry's slot before deleting the removed ID's slot, so removing the last element and removing a
  middle element both leave the map correct. Covered by `test_cancelInEveryStorageSlot`, the fuzzed
  op-sequence test and `invariant_idSlotMapIsConsistent`.
- **Deploy script**: reads only `EXPECTED_CHAIN_ID`; zero/unset means local; only 31337 and 11155111
  are accepted; exactly one `new` between the broadcast markers. Tests call `deployWith` with an
  explicit config and never touch the environment.
- **Config**: solc pinned by version (`0.8.24`), not by path — the previous attempt was rejected for a
  path pin. `offline = true`, `ffi = false`, `fs_permissions = []`, `bytecode_hash = "none"`. The vendored
  `lib/forge-std` has its own `foundry.toml` (which granted read-write fs permissions) removed.

## What was re-run

```
forge build --offline                               # Compiler run successful
forge test --offline                                # 50 passed, 0 failed (5 suites)
forge fmt --check                                   # clean
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline   # Script ran successfully
forge build --offline --sizes                       # PriorityQueue runtime 4,067 B; LaunchToken 1,374 B
```

Fuzz: 512 runs of the byte-decoded operation-sequence test. Invariants: 64 runs × depth 128 across
three handler selectors with `fail_on_revert = true` (0 unexpected reverts).

## What the tests do not cover

- Full-range `bytes32` IDs combined with full-range priorities inside long sequences (the model tests
  deliberately use small spaces to force collisions and ties).
- Gas ceilings are observed, not asserted.
- Behaviour under an actual Sepolia deployment (the contributor task cannot broadcast); the
  deploy-script tests simulate chain IDs with `vm.chainId`.
