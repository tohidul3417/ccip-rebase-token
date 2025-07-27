// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author Mohammad Tohidul Hasan
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault
 * @notice the interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    ////////////
    // Errors //
    ////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    /////////////////////
    // State Variables //
    /////////////////////
    uint256 public s_interestRate = 5e28; // 5e10 * 1e18;
    uint256 private constant PRECISION_FACTOR = 1e36; // 1e18 * 1e18
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    ////////////
    // Events //
    ////////////
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault.
     * @param _to The user to mint the tokens to.
     * @param _amount The amount of tokens to mint.
     * @param _userInterestRate The interest rate of the user.
     * This is either the contract interest rate if the user is depositing
     * of the user's interest rate from the source chain if the user is bridging.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to); // Step 1: Mint any existing accrued interest for the user
        // Step 2: Update the user's interest rate for future calculations if necessary
        // This assumes s_ineterestRate is the current global interest rate
        // If the user already has a deposit, their rate might be updated
        s_userInterestRate[_to] = _userInterestRate;

        // Step 3: Mint the newly deposited amount
        _mint(_to, _amount);
    }

    /**
     * @notice Calculate the balance of the user including the principal and the interest that has
     *  accumulated since the last time the balance was updated
     * @param _user The user to calculate the balance for
     * @return The balance of the user including the interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principal balance of the user (the tokens that actually have been minted to the user)
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        // multiply the principal balance by the interest rate accumulated since the last time the balance has been updated
        // return the balance
        return (currentPrincipalBalance * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one address to another, on behalf of the sender provided an allowance is in place.
     * Accured interest for both sender and recipient is minted before the transfer.
     * If the recipient is new, they inherit the sender's interest rate.
     * @param _sender The address to transfer tokens from
     * @param _recipient The address to transfer tokens to
     * @param _amount The amount of tokens to transfer. Can be type(uint256).max to transfer full balance.
     * @return A boolean indicating whether the operation succeeded.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender); // Use the interest-inclusive balance of the _sender
        }

        // Set recipient's interest rate if they are new
        if (balanceOf(_recipient) == 0 && _amount > 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @dev transfer tokens from the sender to the recipient.
     * This function also mints any accured interest sinche the last time the user's balance was updated
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to trasfer
     * @return true if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        // Accumulates the balance of the user so it is up to date with any interest accumulated
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (balanceOf(_recipient) == 0) {
            // Update the users interest rate only if they have not yet got one (or they tranferred/burned all their tokens).
            // Otherwise people could force others to have lower interest.
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Calculate the interest since the last time the balance was updated
     * @param _user The user interest is caculated for
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // 1. Calculate the time since last update
        // 2. Calculate the amount of linear growth
        // (principal amount) +
        // 10 + (10 * 0.5 * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Burn the user tokens, e.g., when they withdraw from a vault or for cross chain transfers.
     * Handles burning the entire balance if _amount is type(uint256).max.
     * @param _from The user address from which to burn tokens
     * @param _amount The amount of tokens to burn. Use type(uint256).max to burn all tokens
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Access control to be added as needed
        uint256 currentTotalBalance = balanceOf(_from); // Calculate this once for efficiency, if needed for checks
        if (_amount == type(uint256).max) {
            _amount = currentTotalBalance; // Set amount to full current balance
        }
        // Ensure _amount does not exceed actual balance after potential interest accrual
        // This check is important especially if _amount was not type(uint256).max
        // _mintAccruedInterest will update the super.balanceOf(_from)
        // So, after _mintAccruedInterest, super.balanceOf(_from) should be currentTotalBalance
        // The ERC20 _burn function will typically revert if _amount > super.balanceOf(_from)

        _mintAccruedInterest(_from); // mint any accrued interest first

        // At this point, super.balanceOf(_from) reflects the balance including all interest up to now
        // If amount was type(uint256).max, then _amount == super.balanceOf(_from)
        // If _amount was specific, super.balanceOf(_from) must be >= _amount for _burn to succeed
        _burn(_from, _amount);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g., burn, mint, transfer)
     * @param _user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // 1. Find the current balance of rebase tokens that have been minted to the user: principal balance
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        // 2. Calculate their current balance including interest <- balanceOf
        uint256 currentBalance = balanceOf(_user);

        // Calculate the the number of tokens that need to be minted to the user <- 2. - 1.
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        // Set the user's last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;

        // Mint the accrued interest (Interaction)
        if (balanceIncrease > 0) {
            // Optimization: only mint if there is interest
            _mint(_user, balanceIncrease);
        }
    }

    /////////////////////////////
    // Getter / View functions //
    /////////////////////////////
    /**
     * @notice Get the interest rate for the user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice get the principal balance of a user (tokens actually minted to them), excluding any accured interest.
     * @param _user The address of the user
     * @return The principal balance of the user
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user); // Calls ERC20.balanceOf, which returns _balances[_user]
    }

    /**
     * @notice Get the current global interest rate for the token
     * @return The current global interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
