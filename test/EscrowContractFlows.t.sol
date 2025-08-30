// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Payments} from "@fws-payments/Payments.sol";
import "./helpers/RailTestHelper.sol";

contract EscrowContractFlowTest is Test, RailTestHelper {
    EscrowContract implementation;
    ERC1967Proxy escrowProxy;
    EscrowContract proxyEscrow;

    Payments proxyPayments;

    MockERC20 token;

    address payable client;
    address payable operator;
    address payable provider;

    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST");

        // Setup client and operator accounts
        client = payable(makeAddr("client"));
        vm.deal(client, 1 ether);
        operator = payable(makeAddr("operator"));
        provider = payable(makeAddr("provider"));

        vm.deal(operator, 1 ether);

        // Mint tokens to the client
        token.mint(client, 21 ether);

        // Deploy Payments contract
        proxyPayments = new Payments();

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
    function testStandardFlowSingleDeal() public {
        uint256 epochsPerMonth = 86400; // 30 days * 24 hours * 60 minutes * 2 epochs per minute
        uint256 amount = 1 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 20 ether);
        token.approve(address(proxyEscrow), 1 ether);

        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(client, address(token), 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
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

        // Move forward in time 90 days and 5 epochs
        vm.roll(epochsPerMonth * 3 + 5);

        uint256 networkFee = proxyPayments.NETWORK_FEE();

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(
            address(token),
            client,
            epochsPerMonth * 3 + 1
        );

        validateSettlementResult(
            result,
            3 * epochsPerMonth, // expectedSettledAmount
            3 * epochsPerMonth, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            epochsPerMonth * 3 + 1, // expectedFinalEpoch
            "" // expectedNote
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether,
            "Proxy token balance should be 0"
        );

        // Withdraw tokens from Payments contract to escrow contract
        proxyEscrow.withdrawTokens(address(token), 3 wei * epochsPerMonth);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + 3 wei * epochsPerMonth,
            "Proxy token balance should be 3 ether"
        );

        uint256 payoutAmount = 3 wei * epochsPerMonth;

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            provider,
            address(token),
            int256(payoutAmount)
        );

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            provider,
            address(token)
        );

        assertEq(
            withdrawableAmount,
            payoutAmount,
            "Withdrawable amount should match, before unlock"
        );

        vm.startPrank(provider);
        assertEq(
            token.balanceOf(address(provider)),
            0 ether,
            "Provider token balance should be 0 ether"
        );

        // Withdraw provider funds
        proxyEscrow.withdrawProviderFunds(address(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
    }

    function testStandardFlowMultipleDeals() public {
        uint256 epochsPerMonth = 86400; // 30 days * 24 hours * 60 minutes * 2 epochs per minute
        uint256 amount = 1 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 20 ether);
        token.approve(address(proxyEscrow), 1 ether);

        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(client, address(token), 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
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

        // Move forward in time 90 days
        vm.roll(epochsPerMonth * 3);

        // A new deal happened and we update the payment rail
        proxyEscrow.updatePaymentRail(address(token), client, amount * 2);

        // Move forward in time 180 days and 5 epochs
        vm.roll(epochsPerMonth * 6 + 5);

        uint256 networkFee = proxyPayments.NETWORK_FEE();

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(
            address(token),
            client,
            epochsPerMonth * 6 + 1
        );

        validateSettlementResult(
            result,
            3 * epochsPerMonth + 6 * epochsPerMonth + 1, // expectedSettledAmount
            3 * epochsPerMonth + 6 * epochsPerMonth + 1, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            epochsPerMonth * 6 + 1, // expectedFinalEpoch
            "" // expectedNote
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether,
            "Proxy token balance should be 0"
        );

        // Withdraw tokens from Payments contract to escrow contract
        proxyEscrow.withdrawTokens(address(token), 3 wei * epochsPerMonth);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + 3 wei * epochsPerMonth,
            "Proxy token balance should be 3 ether"
        );

        uint256 payoutAmount = 3 wei * epochsPerMonth;

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            provider,
            address(token),
            int256(payoutAmount)
        );

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            provider,
            address(token)
        );

        assertEq(
            withdrawableAmount,
            payoutAmount,
            "Withdrawable amount should match, before unlock"
        );

        vm.startPrank(provider);
        assertEq(
            token.balanceOf(address(provider)),
            0 ether,
            "Provider token balance should be 0 ether"
        );

        // Withdraw provider funds
        proxyEscrow.withdrawProviderFunds(address(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
    }

    function testClientDoesNotPayFlowSingleDeal() public {
        uint256 epochsPerMonth = 86400; // 30 days * 24 hours * 60 minutes * 2 epochs per minute
        uint256 amount = 1 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 86400 wei);
        token.approve(address(proxyEscrow), 1 ether);

        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 86400 wei);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(client, address(token), 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
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

        // Move forward in time 90 days and 5 epochs
        vm.roll(epochsPerMonth * 3 + 5);

        uint256 networkFee = proxyPayments.NETWORK_FEE();

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(
            address(token),
            client,
            epochsPerMonth * 3 + 1
        );

        validateSettlementResult(
            result,
            epochsPerMonth, // expectedSettledAmount
            epochsPerMonth, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            epochsPerMonth + 1, // expectedFinalEpoch
            "" // expectedNote
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether,
            "Proxy token balance should be 0"
        );

        // Withdraw tokens from Payments contract to escrow contract
        proxyEscrow.withdrawTokens(address(token), epochsPerMonth);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + epochsPerMonth,
            "Proxy token balance should be 3 ether"
        );

        //client didn't fully pay for the deal, we need to take out the remaining amount from the security deposit
        proxyEscrow.unlockSecurityDeposit(
            client,
            address(token),
            2 wei * epochsPerMonth,
            0
        );

        uint256 payoutAmount = 3 wei * epochsPerMonth;

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            provider,
            address(token),
            int256(payoutAmount)
        );

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            provider,
            address(token)
        );

        assertEq(
            withdrawableAmount,
            payoutAmount,
            "Withdrawable amount should match, before unlock"
        );

        vm.startPrank(provider);
        assertEq(
            token.balanceOf(address(provider)),
            0 ether,
            "Provider token balance should be 0 ether"
        );

        // Withdraw provider funds
        proxyEscrow.withdrawProviderFunds(address(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
    }

    function testClientDoesNotMeetSlaFlowSingleDeal() public {
        uint256 epochsPerMonth = 86400; // 30 days * 24 hours * 60 minutes * 2 epochs per minute
        uint256 amount = 1 wei;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 20 ether);
        token.approve(address(proxyEscrow), 1 ether);

        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(client, address(token), 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
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

        // Move forward in time 90 days and 5 epochs
        vm.roll(epochsPerMonth * 3 + 5);

        uint256 networkFee = proxyPayments.NETWORK_FEE();

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail{value: networkFee}(
            address(token),
            client,
            epochsPerMonth * 3 + 1
        );

        validateSettlementResult(
            result,
            3 * epochsPerMonth, // expectedSettledAmount
            3 * epochsPerMonth, // expectedNetPayeeAmount
            0, // expectedPaymentFee
            0, // expectedOperatorCommission
            epochsPerMonth * 3 + 1, // expectedFinalEpoch
            "" // expectedNote
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether,
            "Proxy token balance should be 0"
        );

        // Withdraw tokens from Payments contract to escrow contract
        proxyEscrow.withdrawTokens(address(token), 3 wei * epochsPerMonth);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + 3 wei * epochsPerMonth,
            "Proxy token balance should be 3 ether"
        );

        uint256 payoutAmount = epochsPerMonth;
        int256 refundAmount = 2 wei * int256(epochsPerMonth);

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            provider,
            address(token),
            int256(payoutAmount)
        );

        proxyEscrow.changeRefundValue(client, address(token), refundAmount);

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            provider,
            address(token)
        );

        assertEq(
            withdrawableAmount,
            payoutAmount,
            "Withdrawable amount should match, before unlock"
        );

        vm.startPrank(provider);
        assertEq(
            token.balanceOf(address(provider)),
            0 ether,
            "Provider token balance should be 0 ether"
        );

        // Withdraw provider funds
        proxyEscrow.withdrawProviderFunds(address(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
        vm.stopPrank();

        vm.startPrank(client);
        assertEq(
            token.balanceOf(address(client)),
            0 ether,
            "Client token balance should be 0 ether"
        );

        // Withdraw client funds
        proxyEscrow.withdrawClientFunds(address(token));

        assertEq(
            token.balanceOf(address(client)),
            uint256(refundAmount),
            "Client token balance should be refundAmount"
        );
        vm.stopPrank();
    }
}
