// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ProviderFundsManager
 * @notice Library for managing provider funds and withdrawable balances
 */
library ProviderFundsManager {
    using SafeERC20 for IERC20;

    /**
     * @notice Storage struct for provider funds manager data
     */
    struct ProviderFundsManagerStorage {
        // Mapping to track provider balances by provider address and token address
        mapping(address => mapping(address => uint256)) providerBalances; // provider => token => balance
    }

    event BalanceUpdated(
        address indexed provider,
        address indexed token,
        int256 changeValue,
        uint256 newBalance
    );
    event FundsWithdrawn(
        address indexed provider,
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Update provider balance for a specific token
     * @param storage_ The storage struct containing provider funds manager data
     * @param provider The address of the provider
     * @param token The ERC20 token address
     * @param changeValue The value to change balance by (positive to increase, negative to decrease)
     */
    function updateBalance(
        ProviderFundsManagerStorage storage storage_,
        address provider,
        address token,
        int256 changeValue
    ) internal {
        require(provider != address(0), "Provider address cannot be zero");
        require(token != address(0), "Token address cannot be zero");

        uint256 currentBalance = storage_.providerBalances[provider][token];

        if (changeValue >= 0) {
            // Increase balance
            storage_.providerBalances[provider][token] =
                currentBalance +
                uint256(changeValue);
        } else {
            // Decrease balance, but ensure it doesn't go below 0
            uint256 decreaseAmount = uint256(-changeValue);
            require(
                decreaseAmount <= currentBalance,
                "Cannot decrease balance below zero"
            );
            storage_.providerBalances[provider][token] =
                currentBalance -
                decreaseAmount;
        }

        emit BalanceUpdated(
            provider,
            token,
            changeValue,
            storage_.providerBalances[provider][token]
        );
    }

    /**
     * @notice Withdraw full balance for a provider
     * @param storage_ The storage struct containing provider funds manager data
     * @param token The ERC20 token address to withdraw
     */
    function withdrawFunds(
        ProviderFundsManagerStorage storage storage_,
        address token
    ) internal {
        require(token != address(0), "Token address cannot be zero");

        address provider = msg.sender;
        uint256 balance = storage_.providerBalances[provider][token];

        require(balance > 0, "No funds available for withdrawal");

        // Reset balance to 0
        storage_.providerBalances[provider][token] = 0;

        // Transfer tokens to provider
        IERC20(token).safeTransfer(provider, balance);

        emit FundsWithdrawn(provider, token, balance);
    }

    /**
     * @notice Get provider balance for a specific token
     * @param storage_ The storage struct containing provider funds manager data
     * @param provider The address of the provider
     * @param token The ERC20 token address
     * @return balance The provider's balance for the specified token
     */
    function getBalance(
        ProviderFundsManagerStorage storage storage_,
        address provider,
        address token
    ) internal view returns (uint256 balance) {
        return storage_.providerBalances[provider][token];
    }
}
