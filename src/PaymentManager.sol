// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Payments} from "../lib/fws-payments/src/Payments.sol";

/**
 * @title PaymentManager
 * @notice Library for managing payment rails and token operations for the escrow system
 */
library PaymentManager {
    /**
     * @notice Storage struct for payment manager data
     */
    struct PaymentManagerStorage {
        address paymentsContract;
        // Mapping to track payment rails by token address and payer
        mapping(address => mapping(address => uint256)) paymentRails; // token => from => railId
    }

    event PaymentRailCreated(
        address indexed token,
        address indexed from,
        uint256 railId
    );
    event PaymentRailSettled(
        address indexed token,
        address indexed from,
        uint256 indexed railId,
        uint256 totalSettledAmount,
        uint256 totalNetPayeeAmount,
        uint256 totalPaymentFee,
        uint256 totalOperatorCommission,
        uint256 finalSettledEpoch
    );
    event TokensWithdrawn(address indexed token, uint256 amount);

    /**
     * @notice Register a payment and create payment rail if needed
     * @param storage_ The storage struct containing payment manager data
     * @param token The ERC20 token address for the payment
     * @param from The address of the payer
     * @param recipient The address of the recipient
     * @param amount The amount of tokens being paid
     */
    function registerMonthlyPayment(
        PaymentManagerStorage storage storage_,
        address token,
        address from,
        address recipient,
        uint256 amount
    ) internal {
        require(
            storage_.paymentsContract != address(0),
            "Payments contract not set"
        );
        require(from != address(0), "From address cannot be zero");
        require(recipient != address(0), "Recipient address cannot be zero");
        uint256 railId = storage_.paymentRails[token][from];

        require(
            railId == 0,
            "Rail already exists for this token and from address"
        );

        Payments payments = Payments(storage_.paymentsContract);

        railId = payments.createRail(
            token,
            from,
            recipient,
            address(0), // no arbiter
            0 // 0% commission
        );

        // Store the rail ID in our mapping
        storage_.paymentRails[token][from] = railId;

        payments.modifyRailPayment(
            railId,
            amount, // Set the regular payment rate to amount
            0 // One-time payment
        );

        emit PaymentRailCreated(token, from, railId);
    }

    /**
     * @notice Settle a payment rail for a specific token and payer
     * @param storage_ The storage struct containing payment manager data
     * @param token The ERC20 token address of the payment rail
     * @param from The address of the payer whose rail to settle
     * @param blockNumber The block number up to which to settle payments
     * @return totalSettledAmount The total amount settled from the rail
     * @return totalNetPayeeAmount The net amount received by the payee after fees
     * @return totalPaymentFee The total fees paid during settlement
     * @return totalOperatorCommission The total commission paid to operators
     * @return finalSettledEpoch The final epoch that was settled
     * @return note Additional notes from the settlement process
     */
    function settlePaymentRail(
        PaymentManagerStorage storage storage_,
        address token,
        address from,
        uint256 blockNumber
    )
        internal
        returns (
            uint256 totalSettledAmount,
            uint256 totalNetPayeeAmount,
            uint256 totalPaymentFee,
            uint256 totalOperatorCommission,
            uint256 finalSettledEpoch,
            string memory note
        )
    {
        require(
            storage_.paymentsContract != address(0),
            "Payments contract not set"
        );
        require(from != address(0), "From address cannot be zero");
        uint256 railId = storage_.paymentRails[token][from];
        require(railId != 0, "Rail does not exist");

        Payments payments = Payments(storage_.paymentsContract);
        (
            totalSettledAmount,
            totalNetPayeeAmount,
            totalPaymentFee,
            totalOperatorCommission,
            finalSettledEpoch,
            note
        ) = payments.settleRail(railId, blockNumber);

        emit PaymentRailSettled(
            token,
            from,
            railId,
            totalSettledAmount,
            totalNetPayeeAmount,
            totalPaymentFee,
            totalOperatorCommission,
            finalSettledEpoch
        );

        return (
            totalSettledAmount,
            totalNetPayeeAmount,
            totalPaymentFee,
            totalOperatorCommission,
            finalSettledEpoch,
            note
        );
    }

    /**
     * @notice Withdraw tokens from the payments contract
     * @param storage_ The storage struct containing payment manager data
     * @param token The ERC20 token address to withdraw
     * @param amount The amount of tokens to withdraw
     */
    function withdrawTokens(
        PaymentManagerStorage storage storage_,
        address token,
        uint256 amount
    ) internal {
        require(
            storage_.paymentsContract != address(0),
            "Payments contract not set"
        );

        Payments payments = Payments(storage_.paymentsContract);
        payments.withdraw(token, amount);

        emit TokensWithdrawn(token, amount);
    }

    /**
     * @notice Set the address of the Payments contract
     * @param storage_ The storage struct containing payment manager data
     * @param _paymentsContract Address of the Payments contract
     */
    function setPaymentsContract(
        PaymentManagerStorage storage storage_,
        address _paymentsContract
    ) internal {
        require(_paymentsContract != address(0), "Cannot set zero address");
        storage_.paymentsContract = _paymentsContract;
    }

    /**
     * @notice Get the rail ID for a specific token and payer
     * @param storage_ The storage struct containing payment manager data
     * @param token The ERC20 token address
     * @param from The address of the payer
     * @return railId The rail ID for the token and payer combination
     */
    function getRailId(
        PaymentManagerStorage storage storage_,
        address token,
        address from
    ) internal view returns (uint256) {
        return storage_.paymentRails[token][from];
    }

    /**
     * @notice Check if a rail exists for a specific token and payer
     * @param storage_ The storage struct containing payment manager data
     * @param token The ERC20 token address
     * @param from The address of the payer
     * @return exists True if the rail exists, false otherwise
     */
    function railExists(
        PaymentManagerStorage storage storage_,
        address token,
        address from
    ) internal view returns (bool) {
        return storage_.paymentRails[token][from] != 0;
    }

    /**
     * @notice Terminate a payment rail for a specific token and payer
     * @param storage_ The storage struct containing payment manager data
     * @param token The ERC20 token address of the payment rail
     * @param from The address of the payer whose rail to terminate
     */
    function terminateRail(
        PaymentManagerStorage storage storage_,
        address token,
        address from
    ) internal {
        require(
            storage_.paymentsContract != address(0),
            "Payments contract not set"
        );
        require(from != address(0), "From address cannot be zero");

        uint256 railId = storage_.paymentRails[token][from];
        require(railId != 0, "Rail does not exist");

        Payments payments = Payments(storage_.paymentsContract);
        payments.terminateRail(railId);
    }
}
