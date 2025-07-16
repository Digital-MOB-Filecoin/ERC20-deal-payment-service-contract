// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Payments} from "../../lib/fws-payments/src/Payments.sol";
import {console} from "forge-std/console.sol";
import {PaymentManager} from "./PaymentManager.sol";
import {ClientFundsManager} from "./ClientFundsManager.sol";
import {ProviderFundsManager} from "./ProviderFundsManager.sol";

contract EscrowContract is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable
{
    using PaymentManager for PaymentManager.PaymentManagerStorage;
    using ClientFundsManager for ClientFundsManager.ClientFundsManagerStorage;
    using ProviderFundsManager for ProviderFundsManager.ProviderFundsManagerStorage;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address public paymentsContract;
    PaymentManager.PaymentManagerStorage private paymentManagerStorage;
    ClientFundsManager.ClientFundsManagerStorage
        private clientFundsManagerStorage;
    ProviderFundsManager.ProviderFundsManagerStorage
        private providerFundsManagerStorage;

    event PaymentsContractSet(address indexed paymentsContract);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract and set the owner to the provided address
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Set the address of the Payments contract
     * @param _paymentsContract Address of the Payments contract
     */
    function setPaymentsContract(address _paymentsContract) external onlyOwner {
        require(_paymentsContract != address(0), "Cannot set zero address");
        paymentsContract = _paymentsContract;
        paymentManagerStorage.setPaymentsContract(_paymentsContract);
        emit PaymentsContractSet(_paymentsContract);
    }

    /**
     * @notice Grant the operator role to an address
     * @param operator Address to grant the operator role to
     */
    function addOperator(
        address operator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OPERATOR_ROLE, operator);
    }

    /**
     * @notice Revoke the operator role from an address
     * @param operator Address to revoke the operator role from
     */
    function removeOperator(
        address operator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }

    /**
     * @notice Register a payment and create payment rail if needed
     * @param token The ERC20 token address for the payment
     * @param from The address of the payer
     * @param amount The amount of tokens being paid
     */
    function registerMonthlyPayment(
        address token,
        address from,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        paymentManagerStorage.registerMonthlyPayment(
            token,
            from,
            address(this),
            amount
        );
    }

    /**
     * @notice Settle a payment rail for a specific token and payer
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
        address token,
        address from,
        uint256 blockNumber
    )
        external
        onlyRole(OPERATOR_ROLE)
        returns (
            uint256 totalSettledAmount,
            uint256 totalNetPayeeAmount,
            uint256 totalPaymentFee,
            uint256 totalOperatorCommission,
            uint256 finalSettledEpoch,
            string memory note
        )
    {
        return
            paymentManagerStorage.settlePaymentRail(token, from, blockNumber);
    }

    /**
     * @notice Withdraw tokens from the payments contract to this escrow contract
     * @param token The ERC20 token address to withdraw
     * @param amount The amount of tokens to withdraw
     */
    function withdrawTokens(
        address token,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        paymentManagerStorage.withdrawTokens(token, amount);
    }

    /**
     * @notice Get the rail ID for a specific token and payer
     * @param token The ERC20 token address
     * @param from The address of the payer
     * @return railId The rail ID for the token and payer combination
     */
    function getRailId(
        address token,
        address from
    ) external view returns (uint256) {
        return paymentManagerStorage.getRailId(token, from);
    }

    /**
     * @notice Check if a rail exists for a specific token and payer
     * @param token The ERC20 token address
     * @param from The address of the payer
     * @return exists True if the rail exists, false otherwise
     */
    function railExists(
        address token,
        address from
    ) external view returns (bool) {
        return paymentManagerStorage.railExists(token, from);
    }

    /**
     * @notice Terminate a payment rail for a specific token and payer
     * @param token The ERC20 token address of the payment rail
     * @param from The address of the payer whose rail to terminate
     */
    function terminatePaymentRail(
        address token,
        address from
    ) external onlyRole(OPERATOR_ROLE) {
        paymentManagerStorage.terminateRail(token, from);
    }

    // ==================== CLIENT FUNDS MANAGER FUNCTIONS ====================

    /**
     * @notice Deposit security deposit for a client in a specific token
     * @param client The address of the client
     * @param token The ERC20 token address
     * @param amount The amount of tokens to deposit as security deposit
     */
    function depositSecurityDeposit(
        address client,
        address token,
        uint256 amount
    ) external {
        clientFundsManagerStorage.depositSecurityDeposit(client, token, amount);
    }

    /**
     * @notice Unlock security deposit and optionally set refund amount
     * @param client The address of the client
     * @param token The ERC20 token address
     * @param unlockAmount The amount to unlock from security deposit
     * @param refundAmount The amount to add to refund
     */
    function unlockSecurityDeposit(
        address client,
        address token,
        uint256 unlockAmount,
        uint256 refundAmount
    ) external onlyRole(OPERATOR_ROLE) {
        clientFundsManagerStorage.unlockSecurityDeposit(
            client,
            token,
            unlockAmount,
            refundAmount
        );
    }

    /**
     * @notice Change refund value for a client and token
     * @param client The address of the client
     * @param token The ERC20 token address
     * @param changeValue The value to change refund by (positive to increase, negative to decrease)
     */
    function changeRefundValue(
        address client,
        address token,
        int256 changeValue
    ) external onlyRole(OPERATOR_ROLE) {
        clientFundsManagerStorage.changeRefundValue(client, token, changeValue);
    }

    /**
     * @notice Withdraw unlocked funds and refund for a client
     * @param token The ERC20 token address to withdraw
     */
    function withdrawClientFunds(address token) external {
        clientFundsManagerStorage.withdrawFunds(token);
    }

    /**
     * @notice Get client funds information for a specific client and token
     * @param client The address of the client
     * @param token The ERC20 token address
     * @return funds The ClientFunds struct containing all fund information
     */
    function getClientFunds(
        address client,
        address token
    ) external view returns (ClientFundsManager.ClientFunds memory funds) {
        return clientFundsManagerStorage.getClientFunds(client, token);
    }

    /**
     * @notice Get withdrawable amount for a specific client and token
     * @param client The address of the client
     * @param token The ERC20 token address
     * @return withdrawableAmount The total amount that can be withdrawn
     */
    function getClientWithdrawableAmount(
        address client,
        address token
    ) external view returns (uint256 withdrawableAmount) {
        return clientFundsManagerStorage.getWithdrawableAmount(client, token);
    }

    // ==================== PROVIDER FUNDS MANAGER FUNCTIONS ====================

    /**
     * @notice Update provider balance for a specific token
     * @param provider The address of the provider
     * @param token The ERC20 token address
     * @param changeValue The value to change balance by (positive to increase, negative to decrease)
     */
    function updateProviderBalance(
        address provider,
        address token,
        int256 changeValue
    ) external onlyRole(OPERATOR_ROLE) {
        providerFundsManagerStorage.updateBalance(provider, token, changeValue);
    }

    /**
     * @notice Withdraw full balance for a provider
     * @param token The ERC20 token address to withdraw
     */
    function withdrawProviderFunds(address token) external {
        providerFundsManagerStorage.withdrawFunds(token);
    }

    /**
     * @notice Get provider balance for a specific token
     * @param provider The address of the provider
     * @param token The ERC20 token address
     * @return balance The provider's balance for the specified token
     */
    function getProviderBalance(
        address provider,
        address token
    ) external view returns (uint256 balance) {
        return providerFundsManagerStorage.getBalance(provider, token);
    }
}
