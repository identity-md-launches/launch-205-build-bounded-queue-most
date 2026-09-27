// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriorityQueue} from "../src/PriorityQueue.sol";
import {SortedModel} from "./utils/SortedModel.sol";

/// @notice Stateful handler: every call it exposes is a legal operation whose outcome (success or
/// the specific revert) is predicted from the naive model before the call is made.
contract QueueHandler is Test {
    using SortedModel for SortedModel.Item[];

    PriorityQueue public immutable queue;
    SortedModel.Item[] public model;
    address[4] public actors;

    uint256 public enqueues;
    uint256 public cancels;
    uint256 public pops;
    uint256 public fullRejections;
    uint256 public duplicateRejections;
    uint256 public ownerRejections;
    uint64 public lastSequence;

    constructor(PriorityQueue q) {
        queue = q;
        actors = [makeAddr("h0"), makeAddr("h1"), makeAddr("h2"), makeAddr("h3")];
    }

    function modelLength() external view returns (uint256) {
        return model.length;
    }

    function enqueue(uint8 actorSeed, uint8 idSeed, uint8 prioritySeed) external {
        address actor = actors[actorSeed % 4];
        bytes32 id = bytes32(uint256(idSeed) % 48);
        uint32 priority = uint32(prioritySeed % 5);
        (bool live,) = model.indexOf(id);

        vm.prank(actor);
        if (model.length == 32) {
            vm.expectRevert(PriorityQueue.QueueFull.selector);
            queue.enqueue(id, priority);
            fullRejections++;
            return;
        }
        if (live) {
            vm.expectRevert(abi.encodeWithSelector(PriorityQueue.DuplicateId.selector, id));
            queue.enqueue(id, priority);
            duplicateRejections++;
            return;
        }
        uint64 seq = queue.enqueue(id, priority);
        require(seq == lastSequence + 1, "sequence not contiguous");
        lastSequence = seq;
        model.insert(SortedModel.Item({id: id, owner: actor, priority: priority}));
        enqueues++;
    }

    function cancel(uint8 actorSeed, uint8 idSeed) external {
        address actor = actors[actorSeed % 4];
        bytes32 id = bytes32(uint256(idSeed) % 48);
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
            ownerRejections++;
            return;
        }
        queue.cancel(id);
        model.removeAt(idx);
        cancels++;
    }

    function pop(uint8 actorSeed) external {
        vm.prank(actors[actorSeed % 4]);
        if (model.length == 0) {
            vm.expectRevert(PriorityQueue.QueueEmpty.selector);
            queue.pop();
            return;
        }
        SortedModel.Item memory expected = model.popFront();
        PriorityQueue.Entry memory got = queue.pop();
        require(got.id == expected.id, "pop id diverged from model");
        require(got.owner == expected.owner, "pop owner diverged from model");
        require(got.priority == expected.priority, "pop priority diverged from model");
        pops++;
    }
}

contract PriorityQueueInvariantTest is Test {
    PriorityQueue internal queue;
    QueueHandler internal handler;

    function setUp() public {
        queue = new PriorityQueue();
        handler = new QueueHandler(queue);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = QueueHandler.enqueue.selector;
        selectors[1] = QueueHandler.cancel.selector;
        selectors[2] = QueueHandler.pop.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_sizeMatchesModelAndNeverExceedsCapacity() public view {
        assertEq(queue.size(), handler.modelLength());
        assertLe(queue.size(), queue.CAPACITY());
    }

    function invariant_orderedMatchesModel() public view {
        PriorityQueue.Entry[] memory ordered = queue.ordered();
        assertEq(ordered.length, handler.modelLength());
        for (uint256 i = 0; i < ordered.length; ++i) {
            (bytes32 id, address owner, uint32 priority) = handler.model(i);
            assertEq(ordered[i].id, id);
            assertEq(ordered[i].owner, owner);
            assertEq(ordered[i].priority, priority);
        }
        if (ordered.length > 0) {
            PriorityQueue.Entry memory top = queue.peek();
            assertEq(top.id, ordered[0].id);
        }
    }

    function invariant_idSlotMapIsConsistent() public view {
        uint256 n = queue.size();
        for (uint256 i = 0; i < n; ++i) {
            PriorityQueue.Entry memory e = queue.entryAt(i);
            assertTrue(queue.isLive(e.id));
            PriorityQueue.Entry memory byId = queue.getEntry(e.id);
            assertEq(byId.sequence, e.sequence);
            assertEq(byId.owner, e.owner);
            for (uint256 j = i + 1; j < n; ++j) {
                assertTrue(queue.entryAt(j).id != e.id, "duplicate live id in storage");
                assertTrue(queue.entryAt(j).sequence != e.sequence, "duplicate sequence in storage");
            }
        }
    }

    function invariant_sequencesNeverExceedAssigned() public view {
        uint256 n = queue.size();
        for (uint256 i = 0; i < n; ++i) {
            assertLe(queue.entryAt(i).sequence, handler.lastSequence());
        }
        assertEq(queue.nextSequence(), handler.lastSequence() + 1);
    }
}
