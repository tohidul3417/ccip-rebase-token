// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken;

    ////////////
    // Events //
    ////////////
    event Deposit(address indexed user, uint256 indexed amount);
    event Redeem(address indexed user, uint256 indexed amount);

    ////////////
    // Errors //
    ////////////
    error Vault__RedeemFailed();
    error Vault__DepositAmountIsZero();

    // Core Requirements:
    // 1. Store the address of the RebaseToken contract (passed in constructor).
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /**
     * @notice Fallback function to receive any ETH send to this contract directly
     * Any ETH sent to this contract's address without data will be accepted
     */
    receive() external payable {}

    /**
     * @notice Allows a user to deposit ETH and receive an equivalent amount of RebaseTokens.
     * @dev The amount of ETH sent with the transaction (msg.value) determines the amount of tokens minted.
     * Assumes a 1:1 peg for ETH to RebaseToken for simplicity in this version.
     */
    function deposit() external payable {
        // The amount of ETH sent is msg.value
        // The user making the call is msg.sender
        uint256 amountToMint = msg.value;

        // Ensure some ETH is actually sent
        if (amountToMint == 0) {
            revert Vault__DepositAmountIsZero();
        }

        // Call the mint function on the RebaseToken contract
        i_rebaseToken.mint(msg.sender, amountToMint, i_rebaseToken.getInterestRate());

        // Emit an event to log the deposit
        emit Deposit(msg.sender, amountToMint);
    }

    /**
     * @notice Allows a user to burn their RebaseTokens and receive a corresponding
     * @param _amount The amount of RebaseTokens to redeem
     * @dev Follows Checks-Effects-Interactions pattern. Uses low-level .call for ETH transfer
     */
    function redeem(uint256 _amount) external {
        uint256 amountToRedeem = _amount;
        if (_amount == type(uint256).max) {
            amountToRedeem = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. Effects (State changes occur first)
        i_rebaseToken.burn(msg.sender, amountToRedeem);

        // 2. Interactions (External calls / Eth transfer last)
        // Send the equivalent amount of ETH back to the user
        (bool success,) = payable(msg.sender).call{value: amountToRedeem}("");

        // Check if the ETH transfer succeeded
        if (!success) {
            revert Vault__RedeemFailed();
        }

        // Emit an event logging the redemption
        emit Redeem(msg.sender, amountToRedeem);
    }

    /**
     * @notice Gets the address of the RebaseToken contract associated with this vault
     * @return The address of the RebaseToken
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    // 4. Implement a mechanism to add ETH rewards to the vault.
}
