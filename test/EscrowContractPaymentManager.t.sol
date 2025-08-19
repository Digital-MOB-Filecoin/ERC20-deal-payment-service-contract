// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Payments} from "../../lib/fws-payments/src/Payments.sol";
import "./helpers/RailTestHelper.sol";

contract EscrowContractPaymentManagerTest is Test, RailTestHelper {
    EscrowContract implementation;
    ERC1967Proxy escrowProxy;
    EscrowContract proxyEscrow;

    Payments paymentsImplementation;
    ERC1967Proxy paymentsProxy;
    Payments proxyPayments;

    MockERC20 token;

    address payable client;
    address payable operator;

    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST");

        // Setup client and operator accounts
        client = payable(makeAddr("client"));
        vm.deal(client, 1 ether);
        operator = payable(makeAddr("operator"));
        vm.deal(operator, 1 ether);

        // Mint tokens to the client
        token.mint(client, 200 ether);

        // Deploy Payments contract
        paymentsImplementation = new Payments();
        bytes memory paymentsData = abi.encodeWithSelector(
            Payments.initialize.selector
        );
        paymentsProxy = new ERC1967Proxy(
            address(paymentsImplementation),
            paymentsData
        );
        proxyPayments = Payments(address(paymentsProxy));

        // Deploy EscrowContract
        implementation = new EscrowContract();
        bytes memory escrowData = abi.encodeWithSelector(
            EscrowContract.initialize.selector
        );
        escrowProxy = new ERC1967Proxy(address(implementation), escrowData);
        proxyEscrow = EscrowContract(address(escrowProxy));

        // Set the payments contract in the escrow
        proxyEscrow.setPaymentsContract(address(proxyPayments));
        proxyEscrow.addOperator(operator);
        // Add operator role to EscrowContract for Payments
        vm.startPrank(client);
        proxyPayments.setOperatorApproval(
            address(token),
            address(proxyEscrow),
            true,
            20 ether,
            20 ether,
            0
        );
        vm.stopPrank();
    }

    /**
     * @notice Test creating a payment rail and checking the created rail
     */
    function testCreatePaymentRail() public {
        uint256 amount = 5 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 200 ether);
        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        vm.stopPrank();

        // Register payment
        vm.prank(operator);
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Validate that the rail was created correctly
        validateRailCreation(
            proxyEscrow,
            proxyPayments,
            address(token),
            client,
            amount
        );

        vm.roll(10);

        uint256 networkFee = proxyPayments.NETWORK_FEE();

        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(address(token), client, 10);
        validateSettlementResult(
            result,
            45, // expectedSettledAmount
            45, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            10, // expectedFinalEpoch
            "" // expectedNote
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            0,
            "Proxy token balance should be 0"
        );

        proxyEscrow.withdrawTokens(address(token), 45 wei);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            45,
            "Proxy token balance should be 45"
        );
    }

    /**
     * @notice Test creating a payment rail and checking the created rail
     */
    function testUpdatePaymentRail() public {
        uint256 amount = 5 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 200 ether);
        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        vm.stopPrank();

        // Register payment
        vm.prank(operator);
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Validate that the rail was created correctly
        uint256 railId = validateRailCreation(
            proxyEscrow,
            proxyPayments,
            address(token),
            client,
            amount
        );

        vm.roll(10);

        proxyEscrow.updatePaymentRail(address(token), client, 2 * amount);

        Payments.RailView memory railView = proxyPayments.getRail(railId);
        assertEq(
            railView.paymentRate,
            2 * amount,
            "Payment rate should match amount"
        );
    }

    /**
     * @notice Test updating a payment rail and checking the created rail
     */
    function testUpdatePaymentRailDirect() public {
        uint256 amount = 5 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 200 ether);

        proxyPayments.setOperatorApproval(
            address(token),
            operator,
            true,
            20 ether,
            20 ether,
            0
        );

        proxyPayments.deposit(address(token), client, 20 ether);

        vm.stopPrank();

        // Register payment
        vm.startPrank(operator);

        uint256 railId = proxyPayments.createRail(
            address(token), // Token used for payments
            client, // Payer (client)
            operator, // Payee (service provider)
            address(0), // Optional validator (can be address(0) for no validation / arbitration)
            0, // Optional operator commission rate in basis points
            address(0)
        );

        proxyPayments.modifyRailPayment(
            railId, // Rail ID
            amount, // Lockup period (100 epochs)
            0 // Fixed lockup amount (10 tokens for onboarding)
        );

        //Check the rail details from the Payments contract
        Payments.RailView memory railView = proxyPayments.getRail(railId);
        assertEq(
            railView.token,
            address(token),
            "Token address in rail should match"
        );
        assertEq(
            railView.from,
            client,
            "From address in rail should be client"
        );
        assertEq(
            railView.to,
            operator,
            "To address in rail should be EscrowContract"
        );
        assertEq(
            railView.paymentRate,
            amount,
            "Payment rate should match amount"
        );

        vm.roll(30);

        proxyPayments.modifyRailPayment(
            railId, // Rail ID
            2 * amount, // Lockup period (100 epochs)
            0 // Fixed lockup amount (10 tokens for onboarding)
        );

        railView = proxyPayments.getRail(railId);
        assertEq(
            railView.paymentRate,
            2 * amount,
            "Payment rate should match amount"
        );
    }

    /**
     * @notice Test terminating a payment rail by the client with sufficient funds
     */
    function testTerminatePaymentRailByClientWithSufficientFunds() public {
        uint256 amount = 5 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 200 ether);
        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        vm.stopPrank();

        // Register payment
        vm.prank(operator);
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Validate that the rail was created correctly
        uint256 railId = validateRailCreation(
            proxyEscrow,
            proxyPayments,
            address(token),
            client,
            amount
        );

        vm.roll(10);

        vm.startPrank(client);
        // Terminate the payment rail
        proxyPayments.terminateRail(railId);
        vm.stopPrank();

        vm.startPrank(operator);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            0,
            "Proxy token balance should be 0"
        );

        uint256 networkFee = proxyPayments.NETWORK_FEE();
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(address(token), client, 10);
        validateSettlementResult(
            result,
            45, // expectedSettledAmount
            45, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            10, // expectedFinalEpoch
            "terminated rail fully settled and finalized." // expectedNote
        );

        proxyEscrow.withdrawTokens(address(token), 45 wei);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            45,
            "Proxy token balance should be 45"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test terminating a payment rail by the client with insufficient funds
     */
    function testTerminatePaymentRailByClientWithInsufficientFunds() public {
        uint256 amount = 5 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 200 ether);
        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 40 wei);
        vm.stopPrank();

        // Register payment
        vm.prank(operator);
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Validate that the rail was created correctly
        uint256 railId = validateRailCreation(
            proxyEscrow,
            proxyPayments,
            address(token),
            client,
            amount
        );

        vm.roll(10);

        vm.startPrank(client);
        // Terminate the payment rail
        vm.expectRevert();
        proxyPayments.terminateRail(railId);

        proxyPayments.deposit(address(token), client, 40 wei);
        proxyPayments.terminateRail(railId);
        vm.stopPrank();

        vm.startPrank(operator);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            0,
            "Proxy token balance should be 0"
        );

        uint256 networkFee = proxyPayments.NETWORK_FEE();
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(address(token), client, 10);
        validateSettlementResult(
            result,
            45, // expectedSettledAmount
            45, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            10, // expectedFinalEpoch
            "terminated rail fully settled and finalized." // expectedNote
        );

        proxyEscrow.withdrawTokens(address(token), 45 wei);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            45,
            "Proxy token balance should be 45"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test terminating a payment rail by the operator with insufficient funds
     */
    function testTerminatePaymentRailByOperatorWithInsufficientFunds() public {
        uint256 amount = 5 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 200 ether);
        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 40 wei);
        vm.stopPrank();

        // Register payment
        vm.startPrank(operator);
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Validate that the rail was created correctly
        validateRailCreation(
            proxyEscrow,
            proxyPayments,
            address(token),
            client,
            amount
        );

        vm.roll(10);

        // Terminate the payment rail
        proxyEscrow.terminatePaymentRail(address(token), client);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            0,
            "Proxy token balance should be 0"
        );

        uint256 networkFee = proxyPayments.NETWORK_FEE();
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(address(token), client, 10);

        validateSettlementResult(
            result,
            40, // expectedSettledAmount
            40, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            9, // expectedFinalEpoch
            "terminated rail fully settled and finalized." // expectedNote
        );

        proxyEscrow.withdrawTokens(address(token), 40 wei);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            40,
            "Proxy token balance should be 40"
        );

        vm.stopPrank();
    }

    /**
     * @notice Test terminating a payment rail through the terminatePaymentRail function
     */
    function testTerminatePaymentRail() public {
        vm.startPrank(client);
        token.approve(address(proxyPayments), 100 ether);
        proxyPayments.deposit(address(token), client, 100 ether);
        vm.stopPrank();

        uint256 amount = 5 wei;

        // Register payment rail
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Check that the rail exists
        uint256 railId = proxyEscrow.getRailId(address(token), client);
        assertTrue(railId != 0, "Rail should exist");

        // Verify rail exists
        bool railExists = proxyEscrow.railExists(address(token), client);
        assertTrue(railExists, "Rail should exist");

        // Add operator to escrow contract
        proxyEscrow.addOperator(operator);

        // Terminate the payment rail through EscrowContract
        vm.prank(operator);
        proxyEscrow.terminatePaymentRail(address(token), client);

        // Verify the rail is terminated by checking the rail view
        Payments.RailView memory railView = proxyPayments.getRail(railId);
        assertTrue(
            railView.endEpoch > 0,
            "Rail should be terminated (endEpoch > 0)"
        );
    }

    /**
     * @notice Test terminating a payment rail through the terminatePaymentRail function
     *         - only operator can terminate
     */
    function testTerminatePaymentRailOnlyOperator() public {
        vm.startPrank(client);
        token.approve(address(proxyPayments), 100 ether);
        proxyPayments.deposit(address(token), client, 100 ether);
        vm.stopPrank();

        uint256 amount = 5 wei;

        // Register payment rail
        proxyEscrow.createPaymentRail(address(token), client, amount);

        // Try to terminate as non-operator - should fail
        vm.prank(client);
        vm.expectRevert();
        proxyEscrow.terminatePaymentRail(address(token), client);
    }

    /**
     * @notice Test terminating a non-existent payment rail through the terminatePaymentRail function
     */
    function testTerminateNonExistentRail() public {
        // Add operator to escrow contract
        proxyEscrow.addOperator(operator);

        // Try to terminate non-existent rail - should fail
        vm.prank(operator);
        vm.expectRevert("Rail does not exist");
        proxyEscrow.terminatePaymentRail(address(token), client);
    }
}
