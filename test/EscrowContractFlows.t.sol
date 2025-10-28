// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FilecoinPayV1} from "@filecoin-pay/FilecoinPayV1.sol";
import "./helpers/RailTestHelper.sol";

contract EscrowContractFlowTest is Test, RailTestHelper {
    EscrowContract implementation;
    ERC1967Proxy escrowProxy;
    EscrowContract proxyEscrow;

    FilecoinPayV1 proxyPayments;

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
        proxyPayments = new FilecoinPayV1();

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
            IERC20(token),
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
    //todo: double check
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
        proxyPayments.deposit(IERC20(token), client, 20 ether);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(IERC20(token), client, 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
        vm.prank(operator);
        proxyEscrow.createPaymentRail(IERC20(token), client, amount);

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

        uint256 NETWORK_FEE_NUMERATOR = proxyPayments.NETWORK_FEE_NUMERATOR();
        uint256 NETWORK_FEE_DENOMINATOR = proxyPayments
            .NETWORK_FEE_DENOMINATOR();

        uint256 expectedSettledAmount = 3 * epochsPerMonth;
        uint256 fee = (expectedSettledAmount *
            NETWORK_FEE_NUMERATOR +
            (NETWORK_FEE_DENOMINATOR - 1)) / NETWORK_FEE_DENOMINATOR;

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail(IERC20(token), client, epochsPerMonth * 3 + 1);

        validateSettlementResult(
            result,
            expectedSettledAmount, // expectedSettledAmount
            expectedSettledAmount - fee, // expectedNetPayeeAmount
            fee, // expectedPaymentFee
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
        proxyEscrow.withdrawTokens(IERC20(token), expectedSettledAmount - fee);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + expectedSettledAmount - fee,
            "Proxy token balance should be 3 ether"
        );

        uint256 payoutAmount = 3 wei * epochsPerMonth;

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            IERC20(token),
            provider,
            int256(payoutAmount)
        );

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            IERC20(token),
            provider
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
        proxyEscrow.withdrawProviderFunds(IERC20(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
    }

    //todo: double check
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
        proxyPayments.deposit(IERC20(token), client, 20 ether);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(IERC20(token), client, 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
        vm.prank(operator);
        proxyEscrow.createPaymentRail(IERC20(token), client, amount);

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
        proxyEscrow.updatePaymentRail(IERC20(token), client, amount * 2);

        // Move forward in time 180 days and 5 epochs
        vm.roll(epochsPerMonth * 6 + 5);

        uint256 NETWORK_FEE_NUMERATOR = proxyPayments.NETWORK_FEE_NUMERATOR();
        uint256 NETWORK_FEE_DENOMINATOR = proxyPayments
            .NETWORK_FEE_DENOMINATOR();

        uint256 expectedSettledAmount = 3 *
            epochsPerMonth +
            6 *
            epochsPerMonth +
            1;
        uint256 fee = (expectedSettledAmount *
            NETWORK_FEE_NUMERATOR +
            (NETWORK_FEE_DENOMINATOR - 1)) / NETWORK_FEE_DENOMINATOR;

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail(IERC20(token), client, epochsPerMonth * 6 + 1);

        validateSettlementResult(
            result,
            expectedSettledAmount, // expectedSettledAmount
            expectedSettledAmount - fee, // expectedNetPayeeAmount
            fee, // expectedPaymentFee
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
        proxyEscrow.withdrawTokens(IERC20(token), expectedSettledAmount - fee);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + expectedSettledAmount - fee,
            "Proxy token balance should be 3 ether"
        );

        uint256 payoutAmount = 3 wei * epochsPerMonth;

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            IERC20(token),
            provider,
            int256(payoutAmount)
        );

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            IERC20(token),
            provider
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
        proxyEscrow.withdrawProviderFunds(IERC20(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
    }

    //todo: double check
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
        proxyPayments.deposit(IERC20(token), client, 86400 wei);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(IERC20(token), client, 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
        vm.prank(operator);
        proxyEscrow.createPaymentRail(IERC20(token), client, amount);

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

        uint256 NETWORK_FEE_NUMERATOR = proxyPayments.NETWORK_FEE_NUMERATOR();
        uint256 NETWORK_FEE_DENOMINATOR = proxyPayments
            .NETWORK_FEE_DENOMINATOR();

        uint256 expectedSettledAmount = epochsPerMonth;
        uint256 fee = (expectedSettledAmount *
            NETWORK_FEE_NUMERATOR +
            (NETWORK_FEE_DENOMINATOR - 1)) / NETWORK_FEE_DENOMINATOR;

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail(IERC20(token), client, epochsPerMonth * 3 + 1);

        validateSettlementResult(
            result,
            expectedSettledAmount, // expectedSettledAmount
            expectedSettledAmount - fee, // expectedNetPayeeAmount
            fee, // expectedPaymentFee
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
        proxyEscrow.withdrawTokens(IERC20(token), expectedSettledAmount - fee);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + expectedSettledAmount - fee,
            "Proxy token balance should be 3 ether"
        );

        //client didn't fully pay for the deal, we need to take out the remaining amount from the security deposit
        proxyEscrow.unlockSecurityDeposit(
            IERC20(token),
            client,
            2 wei * epochsPerMonth,
            0
        );

        uint256 payoutAmount = 3 wei * epochsPerMonth;

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            IERC20(token),
            provider,
            int256(payoutAmount)
        );

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            IERC20(token),
            provider
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
        proxyEscrow.withdrawProviderFunds(IERC20(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );
    }

    //todo: double check
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
        proxyPayments.deposit(IERC20(token), client, 20 ether);
        // Client deposits security deposit to EscrowContract
        proxyEscrow.depositSecurityDeposit(IERC20(token), client, 1 ether);
        vm.stopPrank();

        // The deal is valid and we create the payment rail
        vm.prank(operator);
        proxyEscrow.createPaymentRail(IERC20(token), client, amount);

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

        // Settle the payment rail
        EscrowContract.SettlementResult memory result = proxyEscrow
            .settlePaymentRail(IERC20(token), client, epochsPerMonth * 3 + 1);

        uint256 NETWORK_FEE_NUMERATOR = proxyPayments.NETWORK_FEE_NUMERATOR();
        uint256 NETWORK_FEE_DENOMINATOR = proxyPayments
            .NETWORK_FEE_DENOMINATOR();

        uint256 expectedSettledAmount = 3 * epochsPerMonth;
        uint256 fee = (expectedSettledAmount *
            NETWORK_FEE_NUMERATOR +
            (NETWORK_FEE_DENOMINATOR - 1)) / NETWORK_FEE_DENOMINATOR;

        validateSettlementResult(
            result,
            expectedSettledAmount, // expectedSettledAmount
            expectedSettledAmount - fee, // expectedNetPayeeAmount
            fee, // expectedPaymentFee
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
        proxyEscrow.withdrawTokens(IERC20(token), expectedSettledAmount - fee);

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            1 ether + expectedSettledAmount - fee,
            "Proxy token balance should be 3 ether"
        );

        uint256 payoutAmount = epochsPerMonth;
        int256 refundAmount = 2 wei * int256(epochsPerMonth);

        // Update provider balance in EscrowContract, to allow the provider to withdraw their money
        proxyEscrow.updateProviderBalance(
            IERC20(token),
            provider,
            int256(payoutAmount)
        );

        proxyEscrow.changeRefundValue(IERC20(token), client, refundAmount);

        uint256 withdrawableAmount = proxyEscrow.getProviderBalance(
            IERC20(token),
            provider
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
        proxyEscrow.withdrawProviderFunds(IERC20(token));

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
        proxyEscrow.withdrawClientFunds(IERC20(token));

        assertEq(
            token.balanceOf(address(client)),
            uint256(refundAmount),
            "Client token balance should be refundAmount"
        );
        vm.stopPrank();
    }
}
