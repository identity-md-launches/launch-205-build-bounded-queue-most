// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Naive reference model: an array kept sorted by priority descending, insertion order
/// ascending among equals. It deliberately knows nothing about the contract's sequence numbers;
/// FIFO among ties comes purely from where `insert` places a new item (after every existing item
/// of the same priority). Every operation is O(n) shifting, which is fine for n <= 32.
library SortedModel {
    struct Item {
        bytes32 id;
        address owner;
        uint32 priority;
    }

    function insert(Item[] storage m, Item memory e) internal {
        uint256 pos = m.length;
        for (uint256 i = 0; i < m.length; ++i) {
            if (m[i].priority < e.priority) {
                pos = i;
                break;
            }
        }
        m.push(e);
        for (uint256 j = m.length - 1; j > pos; --j) {
            m[j] = m[j - 1];
        }
        m[pos] = e;
    }

    function indexOf(Item[] storage m, bytes32 id) internal view returns (bool found, uint256 index) {
        for (uint256 i = 0; i < m.length; ++i) {
            if (m[i].id == id) return (true, i);
        }
        return (false, 0);
    }

    function removeAt(Item[] storage m, uint256 index) internal {
        for (uint256 j = index; j + 1 < m.length; ++j) {
            m[j] = m[j + 1];
        }
        m.pop();
    }

    function popFront(Item[] storage m) internal returns (Item memory e) {
        e = m[0];
        removeAt(m, 0);
    }
}
