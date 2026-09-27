// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title LaunchToken
/// @notice Fixed-supply ERC-20 required by the IdentityMD project-launch floor. It is NOT part of
/// the PriorityQueue's behaviour: the queue never references or moves tokens.
///
/// Exactly 1,000,000,000 tokens (10^27 minor units, 18 decimals) are minted once, in the
/// constructor, to `msg.sender` (the ProjectFactory). There is no owner, no mint, no burn, no
/// pause, no upgrade path and no constructor argument.
contract LaunchToken {
    string public constant name = "Priority Queue Launch Token";
    string public constant symbol = "PQL";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000e18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance(uint256 requested, uint256 available);
    error InsufficientAllowance(uint256 requested, uint256 available);
    error ZeroAddress();

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance(amount, allowed);
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance(amount, balance);
        unchecked {
            balanceOf[from] = balance - amount;
        }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
