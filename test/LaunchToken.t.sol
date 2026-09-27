// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken internal token;
    address internal deployer = makeAddr("factory");
    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.prank(deployer);
        token = new LaunchToken();
    }

    function test_fixedSupplyMintedToDeployer() public view {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(deployer), 1e27);
        assertEq(token.decimals(), 18);
        assertEq(token.name(), "Priority Queue Launch Token");
        assertEq(token.symbol(), "PQL");
    }

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1_000e18));
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(token.balanceOf(deployer), 1e27 - 1_000e18);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_transferInsufficientReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.InsufficientBalance.selector, 1, 0));
        token.transfer(deployer, 1);
    }

    function test_transferToZeroReverts() public {
        vm.prank(deployer);
        vm.expectRevert(LaunchToken.ZeroAddress.selector);
        token.transfer(address(0), 1);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        token.approve(alice, 500);
        vm.prank(alice);
        token.transferFrom(deployer, alice, 300);
        assertEq(token.allowance(deployer, alice), 200);
        assertEq(token.balanceOf(alice), 300);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.InsufficientAllowance.selector, 201, 200));
        token.transferFrom(deployer, alice, 201);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_noMintSelectorIncreasesSupply() public {
        string[6] memory sigs = [
            "mint(address,uint256)",
            "mint(uint256)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < sigs.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(abi.encodeWithSignature(sigs[i], alice, uint256(1)));
            assertFalse(ok, sigs[i]);
            assertEq(token.totalSupply(), 1e27);
            assertEq(token.balanceOf(alice), 0);
        }
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        _assertNoEscapeOpcodes(address(token).code);
    }

    function _assertNoEscapeOpcodes(bytes memory code) internal pure {
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
