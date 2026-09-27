// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {PriorityQueue} from "../src/PriorityQueue.sol";

/// @title Deploy
/// @notice Operator-only deployment of PriorityQueue. Reads no keys and no RPC URL: the only
/// environment variable consulted is EXPECTED_CHAIN_ID, which must match the connected chain and
/// be either the local Anvil chain (31337) or Sepolia (11155111). Unset or zero means local.
///
/// Exactly one contract is deployed between the broadcast markers. The PriorityQueue has no
/// constructor arguments.
contract Deploy is Script {
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    struct Config {
        uint256 expectedChainId;
    }

    error UnsupportedChain(uint256 chainId);
    error ChainMismatch(uint256 expected, uint256 actual);

    /// @notice Entry point for `forge script`. Reads the environment and delegates to `deployWith`.
    function run() external returns (PriorityQueue queue) {
        Config memory cfg = Config({expectedChainId: vm.envOr("EXPECTED_CHAIN_ID", uint256(0))});
        queue = deployWith(cfg);
    }

    /// @notice Deploy under an explicit config. Tests call this directly instead of setting env vars.
    function deployWith(Config memory cfg) public returns (PriorityQueue queue) {
        checkChain(cfg.expectedChainId, block.chainid);
        vm.startBroadcast();
        queue = new PriorityQueue();
        vm.stopBroadcast();
    }

    /// @notice Pure gate: `expected` of zero means local; otherwise it must equal `actual` and be a
    /// supported chain.
    function checkChain(uint256 expected, uint256 actual) public pure {
        if (expected == 0) expected = LOCAL_CHAIN_ID;
        if (expected != LOCAL_CHAIN_ID && expected != SEPOLIA_CHAIN_ID) revert UnsupportedChain(expected);
        if (expected != actual) revert ChainMismatch(expected, actual);
    }
}
