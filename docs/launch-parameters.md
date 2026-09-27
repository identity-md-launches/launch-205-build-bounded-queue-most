# Launch parameters (IdentityMD ProjectFactory, Sepolia 11155111)

This task does not write `launch.json`; the manifest node does. These are the values it needs.

## Launch token

| Field | Value |
|---|---|
| Contract | `LaunchToken` (`src/LaunchToken.sol`) |
| Constructor arguments | none |
| Decimals | 18 |
| Total supply | 1,000,000,000 tokens = `1000000000000000000000000000` (10²⁷) minor units, minted to `msg.sender` |
| Admin / mint / upgrade | none |

## Application contracts (dependency order)

| Identifier | Contract | Constructor arguments | Notes |
|---|---|---|---|
| `PriorityQueue` | `src/PriorityQueue.sol` | none | no owner, no `$owner`, no `$token` reference; capacity is the constant 32 |

Constructors are nonpayable, take no arguments and make no external calls. The runtime contains no
`DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` and is 4,067 bytes (EIP-170 limit 24,576).

## Pool (no hook)

Per current Sepolia policy: pair against native ETH (zero address), fee 3000, tickSpacing 60,
sqrtPriceX96 `79228162514264337593543950336`. The deployer derives the effective opening price from the
pinned policy.

## Compiler settings for source verification

| Setting | Value |
|---|---|
| solc | 0.8.24 |
| evm_version | paris |
| optimizer | true, 200 runs |
| bytecode_hash | none |
| cbor_metadata | false |

## Deployment record (filled by the network deployer after review)

| Item | Value |
|---|---|
| PriorityQueue address | *pending* |
| Deployment tx hash | *pending* |
| Explorer | `https://sepolia.etherscan.io/address/<PriorityQueue address>` |
