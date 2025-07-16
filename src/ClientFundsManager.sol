// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ClientFundsManager
 * @notice Library for managing client funds including security deposits and refunds
 */
library ClientFundsManager {
    using SafeERC20 for IERC20;

    /**
     * @notice Storage struct for client funds data
     */
    struct ClientFunds {
        uint256 securityDeposit;
        uint256 refund;
    }

    /**
     * @notice Storage struct for client funds manager data
     */
    struct ClientFundsManagerStorage {
        // Mapping to track client funds by client address and token address
        mapping(address => mapping(address => ClientFunds)) clientFunds; // client => token => ClientFunds
    }

    event SecurityDepositDeposited(
        address indexed client,
        address indexed token,
        uint256 amount
    );
    event SecurityDepositUnlocked(
        address indexed client,
        address indexed token,
        uint256 unlockedAmount,
        uint256 refundAmount
    );
    event RefundValueChanged(
        address indexed client,
        address indexed token,
        int256 changeValue,
        uint256 newRefundValue
    );
    event FundsWithdrawn(
        address indexed client,
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Deposit security deposit for a client in a specific token
     * @param storage_ The storage struct containing client funds manager data
     * @param client The address of the client
     * @param token The ERC20 token address
     * @param amount The amount of tokens to deposit as security deposit
     */
    function depositSecurityDeposit(
        ClientFundsManagerStorage storage storage_,
        address client,
        address token,
        uint256 amount
    ) internal {
        require(client != address(0), "Client address cannot be zero");
        require(token != address(0), "Token address cannot be zero");
        require(amount > 0, "Amount must be greater than zero");

        // Transfer tokens from client to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Increase security deposit
        storage_.clientFunds[client][token].securityDeposit += amount;

        emit SecurityDepositDeposited(client, token, amount);
    }

    /**
     * @notice Unlock security deposit and optionally set refund amount
     * @param storage_ The storage struct containing client funds manager data
     * @param client The address of the client
     * @param token The ERC20 token address
     * @param unlockAmount The amount to unlock from security deposit (must be <= securityDeposit)
     * @param refundAmount The amount to add to refund (must be <= unlockAmount)
     */
    function unlockSecurityDeposit(
        ClientFundsManagerStorage storage storage_,
        address client,
        address token,
        uint256 unlockAmount,
        uint256 refundAmount
    ) internal {
        require(client != address(0), "Client address cannot be zero");
        require(token != address(0), "Token address cannot be zero");

        ClientFunds storage clientFunds = storage_.clientFunds[client][token];

        require(
            unlockAmount <= clientFunds.securityDeposit,
            "Unlock amount exceeds security deposit"
        );
        require(
            refundAmount <= unlockAmount,
            "Refund amount exceeds unlock amount"
        );

        // Decrease security deposit
        clientFunds.securityDeposit -= unlockAmount;

        // Increase refund
        clientFunds.refund += refundAmount;

        emit SecurityDepositUnlocked(client, token, unlockAmount, refundAmount);
    }

    /**
     * @notice Change refund value for a client and token
     * @param storage_ The storage struct containing client funds manager data
     * @param client The address of the client
     * @param token The ERC20 token address
     * @param changeValue The value to change refund by (positive to increase, negative to decrease)
     */
    function changeRefundValue(
        ClientFundsManagerStorage storage storage_,
        address client,
        address token,
        int256 changeValue
    ) internal {
        require(client != address(0), "Client address cannot be zero");
        require(token != address(0), "Token address cannot be zero");

        ClientFunds storage clientFunds = storage_.clientFunds[client][token];

        if (changeValue >= 0) {
            // Increase refund
            clientFunds.refund += uint256(changeValue);
        } else {
            // Decrease refund, but ensure it doesn't go below 0
            uint256 decreaseAmount = uint256(-changeValue);
            require(
                decreaseAmount <= clientFunds.refund,
                "Cannot decrease refund below zero"
            );
            clientFunds.refund -= decreaseAmount;
        }

        emit RefundValueChanged(client, token, changeValue, clientFunds.refund);
    }

    /**
     * @notice Withdraw refund for a client
     * @param storage_ The storage struct containing client funds manager data
     * @param token The ERC20 token address to withdraw
     */
    function withdrawFunds(
        ClientFundsManagerStorage storage storage_,
        address token
    ) internal {
        require(token != address(0), "Token address cannot be zero");

        address client = msg.sender;
        ClientFunds storage clientFunds = storage_.clientFunds[client][token];

        uint256 withdrawableAmount = clientFunds.refund;
        require(withdrawableAmount > 0, "No funds available for withdrawal");

        // Reset refund balance
        clientFunds.refund = 0;

        // Transfer tokens to client
        IERC20(token).safeTransfer(client, withdrawableAmount);

        emit FundsWithdrawn(client, token, withdrawableAmount);
    }

    /**
     * @notice Get client funds information for a specific client and token
     * @param storage_ The storage struct containing client funds manager data
     * @param client The address of the client
     * @param token The ERC20 token address
     * @return funds The ClientFunds struct containing all fund information
     */
    function getClientFunds(
        ClientFundsManagerStorage storage storage_,
        address client,
        address token
    ) internal view returns (ClientFunds memory funds) {
        return storage_.clientFunds[client][token];
    }

    /**
     * @notice Get withdrawable amount for a specific client and token
     * @param storage_ The storage struct containing client funds manager data
     * @param client The address of the client
     * @param token The ERC20 token address
     * @return withdrawableAmount The refund amount that can be withdrawn
     */
    function getWithdrawableAmount(
        ClientFundsManagerStorage storage storage_,
        address client,
        address token
    ) internal view returns (uint256 withdrawableAmount) {
        ClientFunds storage clientFunds = storage_.clientFunds[client][token];
        return clientFunds.refund;
    }
}
