// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriorityQueue} from "../src/PriorityQueue.sol";
import {SortedModel} from "./utils/SortedModel.sol";

contract PriorityQueueTest is Test {
    using SortedModel for SortedModel.Item[];

    PriorityQueue internal queue;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    SortedModel.Item[] internal model;

    event Enqueued(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence);
    event Cancelled(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence);
    event Popped(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence, address indexed caller);

    function setUp() public {
        queue = new PriorityQueue();
    }

    function id(uint256 n) internal pure returns (bytes32) {
        return bytes32(n);
    }

    // ---------------------------------------------------------------------------------------------
    // Basic success paths
    // ---------------------------------------------------------------------------------------------

    function test_capacityConstant() public view {
        assertEq(queue.CAPACITY(), 32);
        assertEq(queue.size(), 0);
        assertEq(queue.nextSequence(), 1);
    }

    function test_enqueueRecordsOwnerPriorityAndSequence() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Enqueued(id(7), alice, 5, 1);
        uint64 seq = queue.enqueue(id(7), 5);

        assertEq(seq, 1);
        assertEq(queue.size(), 1);
        assertTrue(queue.isLive(id(7)));
        assertEq(queue.nextSequence(), 2);

        PriorityQueue.Entry memory e = queue.getEntry(id(7));
        assertEq(e.id, id(7));
        assertEq(e.owner, alice);
        assertEq(e.priority, 5);
        assertEq(e.sequence, 1);
    }

    function test_zeroIdIsAllowed() public {
        vm.prank(alice);
        queue.enqueue(bytes32(0), 1);
        assertTrue(queue.isLive(bytes32(0)));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.DuplicateId.selector, bytes32(0)));
        queue.enqueue(bytes32(0), 1);
        PriorityQueue.Entry memory e = queue.pop();
        assertEq(e.id, bytes32(0));
        assertFalse(queue.isLive(bytes32(0)));
    }

    function test_popReturnsHighestPriority() public {
        vm.prank(alice);
        queue.enqueue(id(1), 10);
        vm.prank(bob);
        queue.enqueue(id(2), 30);
        vm.prank(carol);
        queue.enqueue(id(3), 20);

        PriorityQueue.Entry memory top = queue.peek();
        assertEq(top.id, id(2));

        vm.expectEmit(true, true, true, true);
        emit Popped(id(2), bob, 30, 2, address(this));
        PriorityQueue.Entry memory e = queue.pop();
        assertEq(e.id, id(2));
        assertEq(e.owner, bob);
        assertEq(e.priority, 30);
        assertEq(e.sequence, 2);

        assertEq(queue.pop().id, id(3));
        assertEq(queue.pop().id, id(1));
        assertEq(queue.size(), 0);
    }

    function test_anyoneMayPop() public {
        vm.prank(alice);
        queue.enqueue(id(1), 1);
        vm.prank(bob);
        PriorityQueue.Entry memory e = queue.pop();
        assertEq(e.owner, alice);
        assertEq(queue.size(), 0);
    }

    function test_maxPriorityAndMinPriority() public {
        vm.prank(alice);
        queue.enqueue(id(1), 0);
        vm.prank(alice);
        queue.enqueue(id(2), type(uint32).max);
        vm.prank(alice);
        queue.enqueue(id(3), type(uint32).max - 1);
        assertEq(queue.pop().id, id(2));
        assertEq(queue.pop().id, id(3));
        assertEq(queue.pop().id, id(1));
    }

    // ---------------------------------------------------------------------------------------------
    // Ties are FIFO
    // ---------------------------------------------------------------------------------------------

    function test_equalPrioritiesPopInInsertionOrder() public {
        for (uint256 i = 1; i <= 10; ++i) {
            vm.prank(i % 2 == 0 ? alice : bob);
            queue.enqueue(id(i), 7);
        }
        for (uint256 i = 1; i <= 10; ++i) {
            PriorityQueue.Entry memory e = queue.pop();
            assertEq(e.id, id(i), "tie must pop FIFO");
            assertEq(e.sequence, uint64(i));
        }
    }

    function test_tiesRemainFifoAfterRemovalsReorderStorage() public {
        // Fill with mixed priorities so swap-removes move entries around in storage.
        vm.startPrank(alice);
        queue.enqueue(id(1), 5);
        queue.enqueue(id(2), 9);
        queue.enqueue(id(3), 5);
        queue.enqueue(id(4), 9);
        queue.enqueue(id(5), 5);
        queue.cancel(id(1)); // swap-remove moves id(5) into slot 0
        vm.stopPrank();

        assertEq(queue.pop().id, id(2));
        assertEq(queue.pop().id, id(4));
        assertEq(queue.pop().id, id(3), "older tie must still win after storage reorder");
        assertEq(queue.pop().id, id(5));
    }

    function test_reusedIdWithSamePriorityGoesToTheBackOfItsTieGroup() public {
        vm.startPrank(alice);
        queue.enqueue(id(1), 3);
        queue.enqueue(id(2), 3);
        queue.cancel(id(1));
        queue.enqueue(id(1), 3); // re-enqueued: newer sequence, so behind id(2)
        vm.stopPrank();

        assertEq(queue.pop().id, id(2));
        PriorityQueue.Entry memory e = queue.pop();
        assertEq(e.id, id(1));
        assertEq(e.sequence, 3);
    }

    // ---------------------------------------------------------------------------------------------
    // Capacity
    // ---------------------------------------------------------------------------------------------

    function test_capacityIsExactlyThirtyTwo() public {
        for (uint256 i = 1; i <= 32; ++i) {
            vm.prank(alice);
            queue.enqueue(id(i), uint32(i));
        }
        assertEq(queue.size(), 32);

        vm.prank(alice);
        vm.expectRevert(PriorityQueue.QueueFull.selector);
        queue.enqueue(id(33), 1);

        // A duplicate is also refused while full, and the full check comes first.
        vm.prank(alice);
        vm.expectRevert(PriorityQueue.QueueFull.selector);
        queue.enqueue(id(1), 1);
    }

    function test_capacityFreesAfterPop() public {
        for (uint256 i = 1; i <= 32; ++i) {
            vm.prank(alice);
            queue.enqueue(id(i), 1);
        }
        queue.pop();
        assertEq(queue.size(), 31);
        vm.prank(bob);
        uint64 seq = queue.enqueue(id(33), 1);
        assertEq(seq, 33);
        assertEq(queue.size(), 32);
        vm.prank(bob);
        vm.expectRevert(PriorityQueue.QueueFull.selector);
        queue.enqueue(id(34), 1);
    }

    function test_capacityFreesAfterCancel() public {
        for (uint256 i = 1; i <= 32; ++i) {
            vm.prank(alice);
            queue.enqueue(id(i), 1);
        }
        vm.prank(alice);
        queue.cancel(id(16));
        vm.prank(alice);
        queue.enqueue(id(99), 1);
        assertEq(queue.size(), 32);
    }

    function test_fillDrainRefillKeepsSequencesMonotonic() public {
        for (uint256 round = 0; round < 3; ++round) {
            for (uint256 i = 1; i <= 32; ++i) {
                vm.prank(alice);
                uint64 seq = queue.enqueue(id(i), uint32(i % 4));
                assertEq(seq, uint64(round * 32 + i));
            }
            for (uint256 i = 0; i < 32; ++i) {
                queue.pop();
            }
            assertEq(queue.size(), 0);
        }
        assertEq(queue.nextSequence(), 97);
    }

    // ---------------------------------------------------------------------------------------------
    // Duplicate and reused IDs
    // ---------------------------------------------------------------------------------------------

    function test_duplicateLiveIdRejectedForAnyCaller() public {
        vm.prank(alice);
        queue.enqueue(id(1), 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.DuplicateId.selector, id(1)));
        queue.enqueue(id(1), 9);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.DuplicateId.selector, id(1)));
        queue.enqueue(id(1), 9);

        assertEq(queue.size(), 1);
        assertEq(queue.getEntry(id(1)).priority, 1, "duplicate must not overwrite");
    }

    function test_removedIdMayBeReusedWithNewSequenceAndOwner() public {
        vm.prank(alice);
        uint64 first = queue.enqueue(id(1), 1);
        queue.pop();
        assertFalse(queue.isLive(id(1)));

        vm.prank(bob);
        uint64 second = queue.enqueue(id(1), 2);
        assertGt(second, first);
        PriorityQueue.Entry memory e = queue.getEntry(id(1));
        assertEq(e.owner, bob);
        assertEq(e.priority, 2);
        assertEq(e.sequence, second);

        vm.prank(bob);
        queue.cancel(id(1));
        vm.prank(carol);
        uint64 third = queue.enqueue(id(1), 3);
        assertEq(third, second + 1);
    }

    // ---------------------------------------------------------------------------------------------
    // Cancellation
    // ---------------------------------------------------------------------------------------------

    function test_ownerCanCancel() public {
        vm.prank(alice);
        queue.enqueue(id(1), 4);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Cancelled(id(1), alice, 4, 1);
        queue.cancel(id(1));
        assertEq(queue.size(), 0);
        assertFalse(queue.isLive(id(1)));
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.UnknownId.selector, id(1)));
        queue.getEntry(id(1));
    }

    function test_nonOwnerCannotCancel() public {
        vm.prank(alice);
        queue.enqueue(id(1), 4);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.NotOwner.selector, id(1), alice, bob));
        queue.cancel(id(1));
        assertTrue(queue.isLive(id(1)));
    }

    function test_cancelUnknownIdReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.UnknownId.selector, id(1)));
        queue.cancel(id(1));
    }

    function test_cancelTwiceReverts() public {
        vm.startPrank(alice);
        queue.enqueue(id(1), 4);
        queue.cancel(id(1));
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.UnknownId.selector, id(1)));
        queue.cancel(id(1));
        vm.stopPrank();
    }

    function test_cancelAfterPopReverts() public {
        vm.prank(alice);
        queue.enqueue(id(1), 4);
        queue.pop();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.UnknownId.selector, id(1)));
        queue.cancel(id(1));
    }

    /// @dev Fill to capacity with tied and untied priorities, cancel the entry sitting at every
    /// pop position in turn, and check that the remaining pop order equals the naive model's.
    function test_cancelInEveryPopPosition() public {
        for (uint256 pos = 0; pos < 32; ++pos) {
            PriorityQueue q = new PriorityQueue();
            delete model;
            for (uint256 i = 1; i <= 32; ++i) {
                address owner = i % 3 == 0 ? alice : (i % 3 == 1 ? bob : carol);
                uint32 priority = uint32((i * 7) % 5); // ties on purpose
                vm.prank(owner);
                q.enqueue(id(i), priority);
                model.insert(SortedModel.Item({id: id(i), owner: owner, priority: priority}));
            }

            SortedModel.Item memory victim = model[pos];
            vm.prank(victim.owner);
            q.cancel(victim.id);
            model.removeAt(pos);

            assertEq(q.size(), 31);
            assertFalse(q.isLive(victim.id));
            _assertOrderedMatchesModel(q);
            _drainAndCompare(q);
        }
    }

    /// @dev Same as above but the cancelled entry is chosen by raw storage index, which exercises
    /// the swap-remove path for every slot including the last.
    function test_cancelInEveryStorageSlot() public {
        for (uint256 slot = 0; slot < 32; ++slot) {
            PriorityQueue q = new PriorityQueue();
            delete model;
            for (uint256 i = 1; i <= 32; ++i) {
                uint32 priority = uint32(i % 3);
                vm.prank(alice);
                q.enqueue(id(i), priority);
                model.insert(SortedModel.Item({id: id(i), owner: alice, priority: priority}));
            }
            PriorityQueue.Entry memory victim = q.entryAt(slot);
            vm.prank(alice);
            q.cancel(victim.id);
            (bool found, uint256 idx) = model.indexOf(victim.id);
            assertTrue(found);
            model.removeAt(idx);

            // The moved entry (previously last) must still be reachable by ID at its new slot.
            if (slot != 31) {
                PriorityQueue.Entry memory moved = q.entryAt(slot);
                assertEq(q.getEntry(moved.id).sequence, moved.sequence);
            }
            _drainAndCompare(q);
        }
    }

    function test_cancelAllThenReuseEveryId() public {
        for (uint256 i = 1; i <= 32; ++i) {
            vm.prank(alice);
            queue.enqueue(id(i), 1);
        }
        for (uint256 i = 32; i >= 1; --i) {
            vm.prank(alice);
            queue.cancel(id(i));
        }
        assertEq(queue.size(), 0);
        for (uint256 i = 1; i <= 32; ++i) {
            vm.prank(bob);
            assertEq(queue.enqueue(id(i), 1), uint64(32 + i));
        }
        assertEq(queue.size(), 32);
    }

    // ---------------------------------------------------------------------------------------------
    // Empty queue
    // ---------------------------------------------------------------------------------------------

    function test_popEmptyReverts() public {
        vm.expectRevert(PriorityQueue.QueueEmpty.selector);
        queue.pop();
    }

    function test_peekEmptyReverts() public {
        vm.expectRevert(PriorityQueue.QueueEmpty.selector);
        queue.peek();
    }

    function test_popUntilEmptyThenReverts() public {
        vm.prank(alice);
        queue.enqueue(id(1), 1);
        queue.pop();
        vm.expectRevert(PriorityQueue.QueueEmpty.selector);
        queue.pop();
    }

    function test_orderedOnEmptyIsEmpty() public view {
        assertEq(queue.ordered().length, 0);
    }

    function test_entryAtOutOfRangeReverts() public {
        vm.expectRevert();
        queue.entryAt(0);
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: single-operation properties
    // ---------------------------------------------------------------------------------------------

    function testFuzz_enqueueThenPopRoundTrips(bytes32 anyId, uint32 priority, address owner) public {
        vm.prank(owner);
        uint64 seq = queue.enqueue(anyId, priority);
        PriorityQueue.Entry memory e = queue.pop();
        assertEq(e.id, anyId);
        assertEq(e.owner, owner);
        assertEq(e.priority, priority);
        assertEq(e.sequence, seq);
        assertEq(queue.size(), 0);
    }

    function testFuzz_onlyOwnerCancels(bytes32 anyId, uint32 priority, address owner, address other) public {
        vm.assume(owner != other);
        vm.prank(owner);
        queue.enqueue(anyId, priority);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(PriorityQueue.NotOwner.selector, anyId, owner, other));
        queue.cancel(anyId);
        vm.prank(owner);
        queue.cancel(anyId);
        assertFalse(queue.isLive(anyId));
    }

    function testFuzz_higherPriorityAlwaysPopsFirst(uint32 a, uint32 b) public {
        vm.assume(a != b);
        vm.prank(alice);
        queue.enqueue(id(1), a);
        vm.prank(alice);
        queue.enqueue(id(2), b);
        PriorityQueue.Entry memory e = queue.pop();
        assertEq(e.priority, a > b ? a : b);
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    function _assertOrderedMatchesModel(PriorityQueue q) internal view {
        PriorityQueue.Entry[] memory got = q.ordered();
        assertEq(got.length, model.length, "ordered length");
        for (uint256 i = 0; i < got.length; ++i) {
            assertEq(got[i].id, model[i].id, "ordered id");
            assertEq(got[i].owner, model[i].owner, "ordered owner");
            assertEq(got[i].priority, model[i].priority, "ordered priority");
        }
    }

    function _drainAndCompare(PriorityQueue q) internal {
        uint64 lastSeqInTie;
        uint32 lastPriority = type(uint32).max;
        while (model.length > 0) {
            SortedModel.Item memory expected = model.popFront();
            PriorityQueue.Entry memory got = q.pop();
            assertEq(got.id, expected.id, "pop id");
            assertEq(got.owner, expected.owner, "pop owner");
            assertEq(got.priority, expected.priority, "pop priority");
            // Sequence monotonic within a tie group, priority non-increasing overall.
            assertLe(got.priority, lastPriority);
            if (got.priority == lastPriority) assertGt(got.sequence, lastSeqInTie);
            lastPriority = got.priority;
            lastSeqInTie = got.sequence;
        }
        assertEq(q.size(), 0);
        vm.expectRevert(PriorityQueue.QueueEmpty.selector);
        q.pop();
    }
}
