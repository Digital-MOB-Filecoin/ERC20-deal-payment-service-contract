// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Payments} from "../../lib/fws-payments/src/Payments.sol";

contract EscrowContractPaymentManagerTest is Test {
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
        operator = payable(makeAddr("operator"));

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
            20 ether
        );
        vm.stopPrank();
    }

    /**
     * @notice Test registering a payment and checking the created rail
     */
    function testRegisterPayment() public {
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
        proxyEscrow.registerMonthlyPayment(address(token), client, amount);

        // Check that the rail was created
        uint256 railId = proxyEscrow.getRailId(address(token), client);
        assertGt(railId, 0, "Payment rail should have been created");

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
            address(proxyEscrow),
            "To address in rail should be EscrowContract"
        );
        assertEq(
            railView.paymentRate,
            amount,
            "Payment rate should match amount"
        );

        vm.roll(10);

        uint256 settlementAmount;
        uint256 netPayeeAmount;
        uint256 paymentFee;
        uint256 operatorCommission;
        uint256 settledUpto;
        string memory note;
        (
            settlementAmount,
            netPayeeAmount,
            paymentFee,
            operatorCommission,
            settledUpto,
            note
        ) = proxyEscrow.settlePaymentRail(address(token), client, 10);
        assertEq(settlementAmount, 45, "Settlement Amount should be 45");
        assertEq(netPayeeAmount, 45, "Net Payee Amount should be 45");
        assertEq(paymentFee, 0, "Payment Fee should be 0");
        assertEq(operatorCommission, 0, "Operator Commission should be 0");
        assertEq(settledUpto, 10, "Settled Upto should be 10");
        assertEq(note, "", "Note should be empty");

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
        proxyEscrow.registerMonthlyPayment(address(token), client, amount);

        // Check that the rail was created
        uint256 railId = proxyEscrow.getRailId(address(token), client);
        assertGt(railId, 0, "Payment rail should have been created");

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
            address(proxyEscrow),
            "To address in rail should be EscrowContract"
        );
        assertEq(
            railView.paymentRate,
            amount,
            "Payment rate should match amount"
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

        railView = proxyPayments.getRail(railId);

        uint256 settlementAmount;
        uint256 netPayeeAmount;
        uint256 paymentFee;
        uint256 operatorCommission;
        uint256 settledUpto;
        string memory note;
        (
            settlementAmount,
            netPayeeAmount,
            paymentFee,
            operatorCommission,
            settledUpto,
            note
        ) = proxyEscrow.settlePaymentRail(address(token), client, 10);
        assertEq(settlementAmount, 45, "Settlement Amount should be 45");
        assertEq(netPayeeAmount, 45, "Net Payee Amount should be 45");
        assertEq(paymentFee, 0, "Payment Fee should be 0");
        assertEq(operatorCommission, 0, "Operator Commission should be 0");
        assertEq(settledUpto, 10, "Settled Upto should be 10");
        assertEq(
            note,
            "terminated rail fully settled and finalized.",
            "Note should be 'terminated rail fully settled and finalized."
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
        proxyEscrow.registerMonthlyPayment(address(token), client, amount);

        // Check that the rail was created
        uint256 railId = proxyEscrow.getRailId(address(token), client);
        assertGt(railId, 0, "Payment rail should have been created");

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
            address(proxyEscrow),
            "To address in rail should be EscrowContract"
        );
        assertEq(
            railView.paymentRate,
            amount,
            "Payment rate should match amount"
        );

        vm.roll(10);

        vm.startPrank(client);
        // Terminate the payment rail
        vm.expectRevert(
            "caller is not authorized: must be operator or client with settled lockup"
        );
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

        railView = proxyPayments.getRail(railId);

        uint256 settlementAmount;
        uint256 netPayeeAmount;
        uint256 paymentFee;
        uint256 operatorCommission;
        uint256 settledUpto;
        string memory note;
        (
            settlementAmount,
            netPayeeAmount,
            paymentFee,
            operatorCommission,
            settledUpto,
            note
        ) = proxyEscrow.settlePaymentRail(address(token), client, 10);
        assertEq(settlementAmount, 45, "Settlement Amount should be 45");
        assertEq(netPayeeAmount, 45, "Net Payee Amount should be 45");
        assertEq(paymentFee, 0, "Payment Fee should be 0");
        assertEq(operatorCommission, 0, "Operator Commission should be 0");
        assertEq(settledUpto, 10, "Settled Upto should be 10");
        assertEq(
            note,
            "terminated rail fully settled and finalized.",
            "Note should be 'terminated rail fully settled and finalized."
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
        proxyEscrow.registerMonthlyPayment(address(token), client, amount);

        // Check that the rail was created
        uint256 railId = proxyEscrow.getRailId(address(token), client);
        assertGt(railId, 0, "Payment rail should have been created");

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
            address(proxyEscrow),
            "To address in rail should be EscrowContract"
        );
        assertEq(
            railView.paymentRate,
            amount,
            "Payment rate should match amount"
        );

        vm.roll(10);

        // Terminate the payment rail
        proxyEscrow.terminatePaymentRail(address(token), client);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            0,
            "Proxy token balance should be 0"
        );

        railView = proxyPayments.getRail(railId);

        uint256 settlementAmount;
        uint256 netPayeeAmount;
        uint256 paymentFee;
        uint256 operatorCommission;
        uint256 settledUpto;
        string memory note;
        (
            settlementAmount,
            netPayeeAmount,
            paymentFee,
            operatorCommission,
            settledUpto,
            note
        ) = proxyEscrow.settlePaymentRail(address(token), client, 10);
        assertEq(settlementAmount, 40, "Settlement Amount should be 40");
        assertEq(netPayeeAmount, 40, "Net Payee Amount should be 40");
        assertEq(paymentFee, 0, "Payment Fee should be 0");
        assertEq(operatorCommission, 0, "Operator Commission should be 0");
        assertEq(settledUpto, 9, "Settled Upto should be 9");
        assertEq(
            note,
            "terminated rail fully settled and finalized.",
            "Note should be 'terminated rail fully settled and finalized."
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
     * @notice Test terminating a payment rail through the new terminatePaymentRail function
     */
    function testTerminatePaymentRail() public {
        vm.startPrank(client);
        token.approve(address(proxyPayments), 100 ether);
        proxyPayments.deposit(address(token), client, 100 ether);
        vm.stopPrank();

        uint256 amount = 5 wei;

        // Register payment rail
        proxyEscrow.registerMonthlyPayment(address(token), client, amount);

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
     * @notice Test terminating a payment rail through the new terminatePaymentRail function
     *         - only operator can terminate
     */
    function testTerminatePaymentRailOnlyOperator() public {
        vm.startPrank(client);
        token.approve(address(proxyPayments), 100 ether);
        proxyPayments.deposit(address(token), client, 100 ether);
        vm.stopPrank();

        uint256 amount = 5 wei;

        // Register payment rail
        proxyEscrow.registerMonthlyPayment(address(token), client, amount);

        // Try to terminate as non-operator - should fail
        vm.prank(client);
        vm.expectRevert();
        proxyEscrow.terminatePaymentRail(address(token), client);
    }

    /**
     * @notice Test terminating a non-existent payment rail through the new terminatePaymentRail function
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
