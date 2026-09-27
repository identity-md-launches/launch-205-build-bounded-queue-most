// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title PriorityQueue
/// @notice A bounded priority queue holding at most 32 live entries.
///
/// Each entry carries a caller-chosen ID, the address that enqueued it (its owner), a uint32
/// priority and a strictly increasing insertion sequence that the contract assigns.
///
/// Rules:
///  - Anyone may enqueue. The queue rejects an ID that is currently live and rejects a 33rd entry.
///  - Only an entry's owner may cancel it.
///  - Anyone may pop. `pop` removes and returns the live entry with the highest priority; among
///    equal priorities the one with the lowest sequence (the oldest) wins, so ties are FIFO.
///  - Removed IDs (popped or cancelled) may be enqueued again; they receive a fresh sequence.
///
/// The live set is stored unordered and every pop/peek scans it. With a hard cap of 32 the scan is
/// cheap and bounded, and it avoids shifting storage on every insert.
contract PriorityQueue {
    /// @notice Maximum number of live entries.
    uint256 public constant CAPACITY = 32;

    struct Entry {
        bytes32 id;
        address owner;
        uint32 priority;
        uint64 sequence;
    }

    /// @dev Unordered live entries; `_entries.length <= CAPACITY`.
    Entry[] private _entries;

    /// @dev id => index in `_entries` plus one. Zero means the ID is not live.
    mapping(bytes32 => uint256) private _slotPlusOne;

    /// @dev Last assigned sequence. The first entry ever enqueued receives sequence 1.
    uint64 private _lastSequence;

    event Enqueued(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence);
    event Cancelled(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence);
    event Popped(bytes32 indexed id, address indexed owner, uint32 priority, uint64 sequence, address indexed caller);

    error QueueFull();
    error QueueEmpty();
    error DuplicateId(bytes32 id);
    error UnknownId(bytes32 id);
    error NotOwner(bytes32 id, address owner, address caller);

    // ---------------------------------------------------------------------------------------------
    // Mutations
    // ---------------------------------------------------------------------------------------------

    /// @notice Add an entry owned by the caller.
    /// @param id Caller-chosen identifier. Must not be live. Any value, including zero, is allowed.
    /// @param priority Higher pops first.
    /// @return sequence The insertion sequence assigned to this entry.
    function enqueue(bytes32 id, uint32 priority) external returns (uint64 sequence) {
        if (_entries.length >= CAPACITY) revert QueueFull();
        if (_slotPlusOne[id] != 0) revert DuplicateId(id);

        sequence = ++_lastSequence;
        _entries.push(Entry({id: id, owner: msg.sender, priority: priority, sequence: sequence}));
        _slotPlusOne[id] = _entries.length;

        emit Enqueued(id, msg.sender, priority, sequence);
    }

    /// @notice Remove a live entry. Only its owner may do this.
    function cancel(bytes32 id) external {
        uint256 slot = _slotPlusOne[id];
        if (slot == 0) revert UnknownId(id);
        Entry memory e = _entries[slot - 1];
        if (e.owner != msg.sender) revert NotOwner(id, e.owner, msg.sender);

        _removeAt(slot - 1);
        emit Cancelled(id, e.owner, e.priority, e.sequence);
    }

    /// @notice Remove and return the highest-priority entry (oldest among equals). Anyone may call.
    function pop() external returns (Entry memory e) {
        uint256 index = _bestIndex();
        e = _entries[index];
        _removeAt(index);
        emit Popped(e.id, e.owner, e.priority, e.sequence, msg.sender);
    }

    // ---------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------

    /// @notice The entry `pop` would return next. Reverts when empty.
    function peek() external view returns (Entry memory) {
        return _entries[_bestIndex()];
    }

    /// @notice Number of live entries.
    function size() external view returns (uint256) {
        return _entries.length;
    }

    /// @notice True when `id` is currently in the queue.
    function isLive(bytes32 id) external view returns (bool) {
        return _slotPlusOne[id] != 0;
    }

    /// @notice The live entry with the given ID. Reverts when it is not live.
    function getEntry(bytes32 id) external view returns (Entry memory) {
        uint256 slot = _slotPlusOne[id];
        if (slot == 0) revert UnknownId(id);
        return _entries[slot - 1];
    }

    /// @notice Live entry at a raw storage index. Storage order is NOT pop order.
    function entryAt(uint256 index) external view returns (Entry memory) {
        return _entries[index];
    }

    /// @notice The sequence the next enqueued entry will receive.
    function nextSequence() external view returns (uint64) {
        return _lastSequence + 1;
    }

    /// @notice All live entries in the order `pop` would return them.
    /// @dev O(n^2) selection with n <= 32; intended for off-chain reads and tests.
    function ordered() external view returns (Entry[] memory out) {
        uint256 n = _entries.length;
        out = new Entry[](n);
        bool[] memory used = new bool[](n);
        for (uint256 k = 0; k < n; ++k) {
            uint256 best = type(uint256).max;
            for (uint256 i = 0; i < n; ++i) {
                if (used[i]) continue;
                if (best == type(uint256).max || _outranks(_entries[i], _entries[best])) best = i;
            }
            used[best] = true;
            out[k] = _entries[best];
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    /// @dev True when `a` should pop before `b`: higher priority, or equal priority and older.
    function _outranks(Entry memory a, Entry memory b) private pure returns (bool) {
        if (a.priority != b.priority) return a.priority > b.priority;
        return a.sequence < b.sequence;
    }

    /// @dev Index of the entry `pop` would return. Reverts when the queue is empty.
    function _bestIndex() private view returns (uint256 best) {
        uint256 n = _entries.length;
        if (n == 0) revert QueueEmpty();
        // Only the packed (owner, priority, sequence) slot is read per entry; the id slot is not needed.
        uint32 bestPriority = _entries[0].priority;
        uint64 bestSequence = _entries[0].sequence;
        for (uint256 i = 1; i < n; ++i) {
            Entry storage candidate = _entries[i];
            uint32 p = candidate.priority;
            uint64 s = candidate.sequence;
            if (p > bestPriority || (p == bestPriority && s < bestSequence)) {
                bestPriority = p;
                bestSequence = s;
                best = i;
            }
        }
    }

    /// @dev Swap-remove the entry at `index`, keeping the id => slot map consistent.
    function _removeAt(uint256 index) private {
        uint256 last = _entries.length - 1;
        bytes32 removedId = _entries[index].id;
        if (index != last) {
            Entry memory moved = _entries[last];
            _entries[index] = moved;
            _slotPlusOne[moved.id] = index + 1;
        }
        _entries.pop();
        delete _slotPlusOne[removedId];
    }
}
