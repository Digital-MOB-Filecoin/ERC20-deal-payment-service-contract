// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Payments} from "../../lib/fws-payments/src/Payments.sol";

contract EscrowContract is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address public paymentsContract;

    // Mapping to track payment rails by token address and payer
    mapping(address => mapping(address => uint256)) public paymentRails; // token => from => railId

    event PaymentsContractSet(address indexed paymentsContract);
    event PaymentRailCreated(
        address indexed token,
        address indexed from,
        uint256 railId
    );

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
     * @param feeAmount One-time fee amount to charge when creating the rail
     * @param lockupPeriod The lockup period (in epochs) for the rail
     */
    function registerPayment(
        address token,
        address from,
        uint256 amount,
        uint256 feeAmount,
        uint256 lockupPeriod
    ) external {
        require(paymentsContract != address(0), "Payments contract not set");
        require(from != address(0), "From address cannot be zero");
        require(lockupPeriod > 0, "Lockup period must be greater than zero");

        Payments payments = Payments(paymentsContract);
        _handleRailCreationOrUpdate(
            payments,
            token,
            from,
            amount,
            feeAmount,
            lockupPeriod
        );
    }

    /**
     * @dev Internal function to handle rail creation or update, reduces stack depth
     */
    function _handleRailCreationOrUpdate(
        Payments payments,
        address token,
        address from,
        uint256 amount,
        uint256 feeAmount,
        uint256 lockupPeriod
    ) internal {
        // Check if a payment rail already exists for this token and payer
        uint256 railId = paymentRails[token][from];

        // If no rail exists, create a new one
        if (railId == 0) {
            _createNewRail(
                payments,
                token,
                from,
                amount,
                feeAmount,
                lockupPeriod
            );
        } else {
            _updateExistingRail(
                payments,
                railId,
                amount,
                feeAmount,
                lockupPeriod
            );
        }
    }

    /**
     * @dev Creates a new payment rail
     */
    function _createNewRail(
        Payments payments,
        address token,
        address from,
        uint256 amount,
        uint256 feeAmount,
        uint256 lockupPeriod
    ) internal {
        // Create a new rail with this contract as the recipient and no arbiter
        uint256 railId = payments.createRail(
            token,
            from,
            address(this), // this contract is the recipient
            address(0), // no arbiter
            0 // 0% commission
        );

        // Store the rail ID in our mapping
        paymentRails[token][from] = railId;

        // Configure the rail with lockup period and fixed amount
        payments.modifyRailLockup(
            railId,
            lockupPeriod,
            feeAmount // Initial lockupFixed equals fee amount
        );

        // If a fee is specified, process it as one-time payment
        if (feeAmount > 0) {
            payments.modifyRailPayment(
                railId,
                amount, // Set the regular payment rate to amount
                0 // One-time payment
            );
        }

        emit PaymentRailCreated(token, from, railId);
    }

    /**
     * @dev Updates an existing payment rail
     */
    function _updateExistingRail(
        Payments payments,
        uint256 railId,
        uint256 amount,
        uint256 feeAmount,
        uint256 lockupPeriod
    ) internal {
        // Get the rail's current info
        Payments.RailView memory railView = payments.getRail(railId);

        // Verify the rail is still active
        require(railView.endEpoch == 0, "Existing rail has been terminated");

        // Verify correct endpoints
        require(railView.to == address(this), "Rail to address mismatch");

        // Update lockup period or fee amount if needed
        if (
            railView.lockupPeriod != lockupPeriod ||
            railView.lockupFixed != feeAmount
        ) {
            payments.modifyRailLockup(railId, lockupPeriod, feeAmount);
        }

        // Update the rail's payment rate if needed
        if (railView.paymentRate != amount) {
            payments.modifyRailPayment(
                railId,
                amount, // Update to the new rate
                0 // No additional one-time payment for updates
            );
        }
    }

    /**
     * @notice Passthrough function to withdraw tokens from the Payments contract to the caller
     * @param token The ERC20 token address to withdraw
     * @param amount The amount of tokens to withdraw
     */
    function withdraw(
        address token,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        require(paymentsContract != address(0), "Payments contract not set");

        // Forward the call to the Payments contract
        Payments(paymentsContract).withdraw(token, amount);
    }

    /**
     * @notice Passthrough function to withdraw tokens from the Payments contract to a specified address
     * @param token The ERC20 token address to withdraw
     * @param to The address to receive the withdrawn tokens
     * @param amount The amount of tokens to withdraw
     */
    function withdrawTo(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        require(paymentsContract != address(0), "Payments contract not set");
        require(to != address(0), "Cannot withdraw to zero address");

        // Forward the call to the Payments contract
        Payments(paymentsContract).withdrawTo(token, to, amount);
    }
}
