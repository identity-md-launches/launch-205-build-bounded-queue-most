// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriorityQueue} from "../src/PriorityQueue.sol";
import {SortedModel} from "./utils/SortedModel.sol";

/// @notice Arbitrary operation sequences, decoded from fuzzed bytes, replayed against both the
/// contract and the naive sorted-array model. The ID space and priority space are kept small so
/// duplicates, reuse after removal, ties and full-capacity rejections all happen often.
contract PriorityQueueModelTest is Test {
    using SortedModel for SortedModel.Item[];

    PriorityQueue internal queue;
    SortedModel.Item[] internal model;
    address[4] internal actors;

    uint256 internal constant ID_SPACE = 40; // > CAPACITY so the queue can fill; small enough to collide
    uint256 internal constant PRIORITY_SPACE = 4; // few distinct priorities => many ties

    function setUp() public {
        queue = new PriorityQueue();
        actors = [makeAddr("a0"), makeAddr("a1"), makeAddr("a2"), makeAddr("a3")];
    }

    /// @dev Each operation consumes three bytes: kind/actor, id, priority.
    function testFuzz_arbitraryOperationSequenceMatchesModel(bytes calldata ops) public {
        uint64 expectedNextSeq = 1;
        uint256 i = 0;
        while (i + 3 <= ops.length) {
            uint8 k = uint8(ops[i]);
            bytes32 id = bytes32(uint256(uint8(ops[i + 1])) % ID_SPACE);
            uint32 priority = uint32(uint8(ops[i + 2]) % PRIORITY_SPACE);
            address actor = actors[k % 4];
            uint8 kind = (k / 4) % 5; // 0,1,2 enqueue  3 cancel  4 pop
            i += 3;

            if (kind <= 2) {
                expectedNextSeq = _enqueue(actor, id, priority, expectedNextSeq);
            } else if (kind == 3) {
                _cancel(actor, id);
            } else {
                _pop();
            }
            _checkState();
        }
        _drain();
    }

    function _enqueue(address actor, bytes32 id, uint32 priority, uint64 expectedNextSeq) internal returns (uint64) {
        (bool live,) = model.indexOf(id);
        vm.prank(actor);
        if (model.length == 32) {
            vm.expectRevert(PriorityQueue.QueueFull.selector);
            queue.enqueue(id, priority);
            return expectedNextSeq;
        }
        if (live) {
            vm.expectRevert(abi.encodeWithSelector(PriorityQueue.DuplicateId.selector, id));
            queue.enqueue(id, priority);
            return expectedNextSeq;
        }
        uint64 seq = queue.enqueue(id, priority);
        assertEq(seq, expectedNextSeq, "sequence must be strictly increasing by one");
        model.insert(SortedModel.Item({id: id, owner: actor, priority: priority}));
        return expectedNextSeq + 1;
    }

    function _cancel(address actor, bytes32 id) internal {
        (bool live, uint256 idx) = model.indexOf(id);
        vm.prank(actor);
        if (!live) {
            vm.expectRevert(abi.encodeWithSelector(PriorityQueue.UnknownId.selector, id));
            queue.cancel(id);
            return;
        }
        if (model[idx].owner != actor) {
            vm.expectRevert(abi.encodeWithSelector(PriorityQueue.NotOwner.selector, id, model[idx].owner, actor));
            queue.cancel(id);
            return;
        }
        queue.cancel(id);
        model.removeAt(idx);
    }

    function _pop() internal {
        if (model.length == 0) {
            vm.expectRevert(PriorityQueue.QueueEmpty.selector);
            queue.pop();
            return;
        }
        SortedModel.Item memory expected = model.popFront();
        PriorityQueue.Entry memory got = queue.pop();
        assertEq(got.id, expected.id, "pop id");
        assertEq(got.owner, expected.owner, "pop owner");
        assertEq(got.priority, expected.priority, "pop priority");
    }

    function _checkState() internal view {
        assertEq(queue.size(), model.length, "size");
        assertLe(queue.size(), 32, "capacity");
        if (model.length > 0) {
            PriorityQueue.Entry memory top = queue.peek();
            assertEq(top.id, model[0].id, "peek id");
            assertEq(top.priority, model[0].priority, "peek priority");
        }
        PriorityQueue.Entry[] memory ordered = queue.ordered();
        assertEq(ordered.length, model.length, "ordered length");
        for (uint256 j = 0; j < ordered.length; ++j) {
            assertEq(ordered[j].id, model[j].id, "ordered id");
            assertEq(ordered[j].owner, model[j].owner, "ordered owner");
            assertEq(ordered[j].priority, model[j].priority, "ordered priority");
            assertTrue(queue.isLive(model[j].id), "model entry must be live");
        }
        // Every ID outside the model must be dead.
        for (uint256 n = 0; n < ID_SPACE; ++n) {
            (bool live,) = model.indexOf(bytes32(n));
            assertEq(queue.isLive(bytes32(n)), live, "liveness");
        }
    }

    function _drain() internal {
        while (model.length > 0) {
            _pop();
        }
        assertEq(queue.size(), 0);
        vm.expectRevert(PriorityQueue.QueueEmpty.selector);
        queue.pop();
    }
}
