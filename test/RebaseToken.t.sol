// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        // Impersonating the "owner" address for deployment and role granting
        vm.startPrank(owner);
        vm.deal(owner, 1 ether);

        rebaseToken = new RebaseToken();

        // Deploy Vault: requires IRebaseToken
        // Direct casting (IRebaseToken(rebaseToken)) is invalid
        // Correct way: cast rebaseToken to address
        vault = new Vault(IRebaseToken(address(rebaseToken)));

        // Grant mint and burn role to the vault contract
        rebaseToken.grantMintAndBurnRole(address(vault));

        // Send one ETH to the vault to simulate initial funds
        // The target address must be cast to 'payable'
        (bool success,) = payable(address(vault)).call{value: 1 ether}("");
        if (!success) {
            revert();
        }

        // Stop impersonating the owner
        vm.stopPrank();
    }

    // Helper function
    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        vm.assume(success); // Optionally, assume thte transfer succeeds
    }

    // Test if interest accrues linearly after a deposit.
    // 'amount' will be a fuzzed input.
    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        assertApproxEqAbs(startBalance, amount, 2);

        // Warp time forward for 1 hour
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);

        // Warp time forwar again for another hour
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 2);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);

        vault.deposit{value: amount}();

        // User call vault.redeem(type(uint256).max) to withdraw their full balance
        vault.redeem(type(uint256).max);

        // User's RebaseToken should be 0 after withdrawing full amount
        assertEq(rebaseToken.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        time = bound(time, 100, type(uint32).max);
        uint256 expectedInterest = (depositAmount * rebaseToken.s_interestRate() * time) / 1e36;
        vm.assume(expectedInterest > 0);
        // 1. Deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        // 2. Warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user); //  100000

        uint256 rewardAmountForVault = balanceAfterSomeTime - depositAmount;
        vm.deal(owner, rewardAmountForVault);
        vm.prank(owner);
        addRewardsToVault(rewardAmountForVault);

        // 3. Redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        // Deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        uint256 userBalance = rebaseToken.balanceOf(user);

        address userTwo = makeAddr("userTwo");
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);

        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        // Owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e28); // 4e10 * 4e18

        // Transfer
        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterTransfer = rebaseToken.balanceOf(userTwo);

        // Assert
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalanceAfterTransfer, amountToSend);

        // check the user interest rate has been inherited (5e28, not 4e28)
        assertEq(rebaseToken.getUserInterestRate(user), 5e28);
        assertEq(rebaseToken.getUserInterestRate(userTwo), 5e28);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testGetPrincipalAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. Deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principalBalanceOf(user), amount);

        // Warp 1 hour forward
        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);

        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
