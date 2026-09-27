// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {PriorityQueue} from "../src/PriorityQueue.sol";

/// @notice Exercises the deploy script through `deployWith` / `checkChain` with an explicit config.
/// No test reads or sets the environment.
contract DeployTest is Test {
    Deploy internal deployer;

    function setUp() public {
        deployer = new Deploy();
    }

    function test_deploysOnLocalChainWithZeroConfig() public {
        vm.chainId(31337);
        PriorityQueue q = deployer.deployWith(Deploy.Config({expectedChainId: 0}));
        assertEq(q.CAPACITY(), 32);
        assertEq(q.size(), 0);
        assertLe(address(q).code.length, 24_576);
        _assertNoEscapeOpcodes(address(q).code);
    }

    function test_deploysOnSepoliaWhenExpected() public {
        vm.chainId(11_155_111);
        PriorityQueue q = deployer.deployWith(Deploy.Config({expectedChainId: 11_155_111}));
        assertEq(q.CAPACITY(), 32);
    }

    function test_refusesMismatchedChain() public {
        vm.chainId(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ChainMismatch.selector, 11_155_111, 31337));
        deployer.deployWith(Deploy.Config({expectedChainId: 11_155_111}));
    }

    function test_refusesUnsetExpectationOnSepolia() public {
        vm.chainId(11_155_111);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ChainMismatch.selector, 31337, 11_155_111));
        deployer.deployWith(Deploy.Config({expectedChainId: 0}));
    }

    function test_refusesMainnetAndOtherChains() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 1));
        deployer.deployWith(Deploy.Config({expectedChainId: 1}));
    }

    function testFuzz_checkChainOnlyAcceptsLocalOrSepolia(uint256 expected, uint256 actual) public {
        vm.assume(expected != 0 && expected != 31337 && expected != 11_155_111);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, expected));
        deployer.checkChain(expected, actual);
    }

    function _assertNoEscapeOpcodes(bytes memory code) internal pure {
        assertGt(code.length, 0);
        for (uint256 j = 0; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
