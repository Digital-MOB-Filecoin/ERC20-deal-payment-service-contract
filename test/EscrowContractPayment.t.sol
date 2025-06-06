// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Payments} from "../../lib/fws-payments/src/Payments.sol";

contract EscrowContractPaymentTest is Test {
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
        token.mint(client, 20 ether);

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

    function testRegisterPayment() public {
        uint256 amount = 5 wei;
        uint256 feeAmount = 2 ether;
        uint256 lockupPeriod = 100;

        // Approve EscrowContract to spend client's tokens
        vm.startPrank(client);
        token.approve(address(proxyPayments), 20 ether);
        vm.stopPrank();

        // Client deposits funds to Payments contract for the payment
        vm.startPrank(client);
        proxyPayments.deposit(address(token), client, 20 ether);
        vm.stopPrank();

        // Register payment
        vm.prank(operator);
        proxyEscrow.registerPayment(
            address(token),
            client,
            amount,
            feeAmount,
            lockupPeriod
        );

        // Check that the rail was created
        uint256 railId = proxyEscrow.paymentRails(address(token), client);
        assertGt(railId, 0, "Payment rail should have been created");

        // Check the rail details from the Payments contract
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
        assertEq(
            railView.lockupPeriod,
            lockupPeriod,
            "Lockup period should match"
        );
        assertEq(
            railView.lockupFixed,
            feeAmount,
            "Lockup fixed should match fee amount"
        );

        // Call register payment again to test the existing rail path
        vm.prank(operator);
        proxyEscrow.registerPayment(
            address(token),
            client,
            amount + 1 wei, // Different amount to test update
            feeAmount,
            lockupPeriod
        );

        // Check that the rail was updated (same ID)
        uint256 updatedRailId = proxyEscrow.paymentRails(
            address(token),
            client
        );
        assertEq(railId, updatedRailId, "Rail ID should remain the same");

        // Check that the payment rate was updated
        Payments.RailView memory updatedRailView = proxyPayments.getRail(
            railId
        );
        assertEq(
            updatedRailView.paymentRate,
            amount + 1 wei,
            "Payment rate should be updated"
        );
    }
}
