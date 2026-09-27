# PriorityQueue — bounded on-chain priority queue (32 entries)

A standalone Foundry project delivering `PriorityQueue`, a queue holding at most 32 live entries.
Each entry has a caller-chosen `bytes32` ID, an owner (the address that enqueued it), a `uint32`
priority and a contract-assigned, strictly increasing `uint64` insertion sequence.

Toolchain: Solidity **0.8.24** (pinned by version in `foundry.toml`), `evm_version = "paris"`,
optimizer on (200 runs), `bytecode_hash = "none"`, fully offline (`offline = true`, `ffi = false`,
`fs_permissions = []`). The only dependency is `forge-std`, vendored as ordinary files under
`lib/forge-std/` (no submodule, no remote fetch).

## Exact behaviour

| Operation | Who | Effect | Reverts with |
|---|---|---|---|
| `enqueue(bytes32 id, uint32 priority) → uint64 sequence` | anyone | Adds an entry owned by `msg.sender`; assigns `sequence = last + 1` (first ever is `1`). | `QueueFull()` if 32 entries are live (checked first); `DuplicateId(id)` if `id` is live. |
| `cancel(bytes32 id)` | entry owner only | Removes the live entry. | `UnknownId(id)` if not live; `NotOwner(id, owner, caller)` otherwise. |
| `pop() → Entry` | anyone | Removes and returns the live entry with the highest priority. Among equal priorities the lowest sequence (the oldest) wins, so ties are FIFO. | `QueueEmpty()` |
| `peek() → Entry` | view | The entry `pop` would return next. | `QueueEmpty()` |

Further rules:

- **Capacity** is a compile-time constant `CAPACITY = 32`. Any pop or cancel frees a slot immediately.
- **Duplicate IDs** are rejected only while the ID is live. After a pop or cancel the same ID may be
  enqueued again by anyone; it gets a fresh, larger sequence and whichever owner enqueues it.
- **Any `bytes32` value is a valid ID, including zero.**
- **Priority `0` is valid** and is the lowest priority; `type(uint32).max` is the highest.
- **Sequences are never reused** and always increase by exactly one per successful enqueue. They
  are per-contract, not per-ID. `nextSequence()` returns the value the next enqueue will receive.
- **Ties are FIFO by sequence**, not by storage position. Internal storage is an unordered array
  with swap-remove, so `entryAt(i)` order is *not* pop order. Use `ordered()` for pop order.
- There is **no owner, admin, pause, upgrade or fee** anywhere in the contract. Nothing is payable.
  The contract never calls out to another contract, so there is no reentrancy surface.

### Views

| Function | Returns |
|---|---|
| `size()` | number of live entries |
| `isLive(bytes32 id)` | whether `id` is live |
| `getEntry(bytes32 id)` | the live entry; reverts `UnknownId` |
| `entryAt(uint256 i)` | live entry at raw storage index `i` (unordered) |
| `ordered()` | all live entries in pop order (O(n²), n ≤ 32; for off-chain reads) |
| `nextSequence()` | the sequence the next enqueue receives |
| `CAPACITY()` | 32 |

### Events

```
Enqueued(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence)
Cancelled(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence)
Popped(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence, address indexed caller)
```

### Entry struct (ABI tuple)

```
struct Entry { bytes32 id; address owner; uint32 priority; uint64 sequence; }
```

ABI exports: `docs/abi/PriorityQueue.json`, `docs/abi/LaunchToken.json`.

## Repository layout

```
src/PriorityQueue.sol            the deliverable
src/LaunchToken.sol              fixed-supply ERC-20 required by the IdentityMD launch floor (see Assumptions)
script/Deploy.s.sol              operator-only deploy script (reads only EXPECTED_CHAIN_ID)
test/PriorityQueue.t.sol         unit tests: capacity, ties, duplicates, cancel in every position, reverts
test/PriorityQueueModel.t.sol    fuzzed arbitrary operation sequences vs a naive sorted-array model
test/PriorityQueueInvariant.t.sol stateful invariant test with a model-tracking handler
test/LaunchToken.t.sol           token floor: supply, transfer exactness, no mint path, no escape opcodes
test/Deploy.t.sol                deploy script gating (local / Sepolia only), runtime size and opcodes
test/utils/SortedModel.sol       the naive model: array sorted by priority desc, insertion order asc
docs/abi/*.json                  ABI exports
docs/launch-parameters.md        constructor arguments and manifest identifiers for the network deployer
REVIEW.md                        independent-style review: findings, disposition, what was re-run
lib/forge-std/                   vendored forge-std 1.16.2 (src only)
```

## Reproduce offline

Requires Foundry (developed against forge 1.7.1) with solc 0.8.24 in the local svm cache. No network
access is needed for any of these commands.

```sh
forge build --offline
forge test --offline
forge fmt --check
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline   # local dry run, chain 31337
```

Useful variants:

```sh
forge test --offline -vvv --match-contract PriorityQueueModelTest   # fuzzed op sequences vs model
forge test --offline --match-contract PriorityQueueInvariantTest    # stateful invariants
forge build --offline --sizes                                       # runtime 4,067 B, well under EIP-170
```

Test configuration (`foundry.toml`): 512 fuzz runs, 64 invariant runs × depth 128 with
`fail_on_revert = true` (every handler call must succeed or hit exactly the revert the model predicted).

## What the tests cover

- **Capacity**: the 33rd enqueue reverts `QueueFull`; a pop or cancel frees exactly one slot; three
  fill/drain rounds keep sequences contiguous (1…96).
- **Cancellation in every position**: for each of the 32 pop positions, and separately for each of
  the 32 raw storage slots, a full queue with deliberate ties has that entry cancelled and the remaining
  pop order is compared with the model. This exercises swap-remove for the first, middle and last slot.
- **Ties**: equal priorities pop in insertion order, including after storage was reordered by removals
  and when a removed ID is re-enqueued at the same priority (it goes to the back of its tie group).
- **Duplicates and reuse**: a live ID is refused for any caller and never overwritten; after removal
  the ID is accepted again with a larger sequence and a possibly different owner.
- **Authorisation**: non-owner cancel reverts with `NotOwner`; unknown, already cancelled and already
  popped IDs revert with `UnknownId`; anyone can pop.
- **Empty queue**: `pop` and `peek` revert `QueueEmpty`; `ordered()` is empty.
- **Arbitrary operation sequences**: `testFuzz_arbitraryOperationSequenceMatchesModel(bytes)` decodes
  fuzzed bytes into enqueue/cancel/pop by four actors over 40 IDs and 4 priorities, predicts the exact
  outcome (success or specific custom error) from the naive model, and checks size, peek, liveness of
  every ID and full `ordered()` equality after every step, then drains both.
- **Invariants**: size equals model length and ≤ 32, `ordered()` equals the model, the id→slot map is
  consistent with storage (no duplicate live IDs or sequences), `nextSequence()` equals last assigned + 1.
- **Deploy script**: deploys with an explicit config on 31337 and 11155111, refuses a mismatched or
  unsupported chain (including mainnet), deployed runtime is under 24,576 bytes and contains no
  `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.
- **LaunchToken**: exact fixed supply to deployer, exact transfers, allowance semantics, no mint or admin
  selector changes supply, no escape opcodes.

Tests never read or set environment variables; the script's `run()` reads `EXPECTED_CHAIN_ID` and hands a
`Config` to `deployWith`, which the tests call directly.

## Deployment (Sepolia, chain ID 11155111)

Deployment is **ON**. This contributor task holds no keys and broadcasts nothing; the network's
deployer performs the transaction after review. The record below is filled by the deployer.

| Item | Value |
|---|---|
| Contract | `PriorityQueue` (`src/PriorityQueue.sol`) |
| Network | Sepolia, chain ID 11155111 |
| Constructor arguments | **none** (capacity is the constant 32) |
| Deployer key / RPC | never in this repository; supplied by the network's deployer |
| Contract address | *to be recorded by the network deployer* |
| Deployment tx hash | *to be recorded by the network deployer* |
| Explorer link | `https://sepolia.etherscan.io/address/<contract address>` |

Operator-only deploy command (the operator supplies the RPC URL and signer out of band; nothing in
the repo reads them):

```sh
EXPECTED_CHAIN_ID=11155111 forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --verify   # signer flags per the operator's own policy
```

The script refuses to run unless `EXPECTED_CHAIN_ID` equals the connected chain and is either `31337`
or `11155111`. Exactly one contract is created between `vm.startBroadcast()` and `vm.stopBroadcast()`.
Mainnet is rejected by construction (`UnsupportedChain(1)`).

Manifest identifiers and constructor parameters for the IdentityMD ProjectFactory launch are in
`docs/launch-parameters.md`. The manifest node writes `launch.json`; this task does not.

### Demo parameters and test accounts

The tests use deterministic labelled accounts from `makeAddr` (`alice`, `bob`, `carol`, handler
actors `h0…h3`, model actors `a0…a3`). They hold no funds and are not needed on Sepolia. A manual demo
on Sepolia is:

```sh
# enqueue id 0x01 with priority 5 (from any funded account), then pop from any account
cast send <queue> "enqueue(bytes32,uint32)" 0x0000000000000000000000000000000000000000000000000000000000000001 5 --rpc-url ...
cast call <queue> "peek()((bytes32,address,uint32,uint64))" --rpc-url ...
cast send <queue> "pop()" --rpc-url ...
```

## Assumptions

- **Fixed capacity of 32** is a constant, not a constructor argument. The task fixed the bound; making
  it configurable would add an argument to document and a way to misconfigure.
- **ID type is `bytes32`.** The task did not fix the type; `bytes32` accommodates hashes, `uint256`
  keys and short strings.
- **Priority ordering**: higher `uint32` pops first. Priority `0` is allowed.
- **Sequence**: `uint64`, contract-global, starts at 1, increments by one per successful enqueue.
  It cannot realistically overflow (2⁶⁴ enqueues); if it did, checked arithmetic reverts.
- **"Do not create a token"** is read as: the queue must not be, mint or hold a token. `LaunchToken`
  exists only because the IdentityMD `evm_project` launch floor (the protected Project/Token tests) deploys
  a fixed-supply ERC-20 alongside every application contract. It has no constructor arguments, no mint,
  no admin, 18 decimals and 10²⁷ minor units minted to `msg.sender`. The queue does not reference it. If
  the network supplies its own launch token, `LaunchToken` can be dropped from the manifest unchanged.
- **Popping is permissionless by design** (task requirement). Anyone, including a bot, can drain the
  queue; there is no fee or incentive model. Applications that need a consumer role should wrap the queue.
- **Enqueueing is permissionless and free** apart from gas. Because the queue is bounded, 32 cheap
  entries from one address block everyone else until they are popped or cancelled. This is inherent in
  the specified design and is documented as an operational responsibility, not mitigated.

## Incomplete checks and limitations

- The fuzz/invariant tests draw IDs from a small space (40–48 values) and priorities from 4–5 values to
  force collisions and ties. They do not exercise the full `bytes32`/`uint32` ranges in combination;
  `testFuzz_enqueueThenPopRoundTrips` and `testFuzz_higherPriorityAlwaysPopsFirst` cover the ranges for
  single operations.
- The naive model orders ties by insertion position only and never looks at the contract's sequence
  numbers, so sequence *values* are checked separately (contiguity in the handler and the fill/drain test).
- No gas benchmarks are asserted. `pop` scans up to 32 entries; measured worst-case gas is in the test
  output (`forge test --offline --gas-report`).
- Tests are not a security audit. The contract has no external calls, no value handling and no
  privileged role, which removes the usual classes; the remaining risk is the denial-of-service by
  filling described above.
- The Sepolia deployment record (address, tx hash) is not in this commit: the contributor task cannot
  broadcast. The network deployer records it after review.

## Operational responsibilities

- **Network deployer**: run the operator command above with `EXPECTED_CHAIN_ID=11155111`, keep the
  signer and RPC URL out of the repo, record address, tx hash and explorer link, and verify source with
  the pinned settings (solc 0.8.24, paris, optimizer 200 runs, `bytecode_hash = "none"`).
- **Integrators**: treat `ordered()` and `entryAt` as off-chain reads; use `peek`/`pop` on-chain.
  Expect `QueueFull` and plan for the queue being filled by third parties.
- **Nobody** holds an admin role. There is nothing to rotate, pause or upgrade.
