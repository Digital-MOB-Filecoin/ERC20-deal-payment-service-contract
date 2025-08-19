// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Payments} from "../../lib/fws-payments/src/Payments.sol";

contract EscrowContractProviderFundsManager is Test {
    EscrowContract implementation;
    ERC1967Proxy escrowProxy;
    EscrowContract proxyEscrow;

    Payments paymentsImplementation;
    ERC1967Proxy paymentsProxy;
    Payments proxyPayments;

    MockERC20 token;

    address payable client;
    address payable provider;
    address payable operator;

    function setUp() public {
        // Deploy mock token
        token = new MockERC20("Test Token", "TEST");

        // Setup client and operator accounts
        client = payable(makeAddr("client"));
        operator = payable(makeAddr("operator"));
        provider = payable(makeAddr("provider"));

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
     * @notice Test unlock security deposit functionality
     * @dev This function tests the unlockSecurityDeposit function in ClientFundsManagerStorage
     */
    function testUnlockSecurityDeposit() public {
        uint256 amount = 1 ether;

        // Client deposits security deposit
        vm.startPrank(client);
        token.approve(address(proxyEscrow), 200 ether);

        proxyEscrow.depositSecurityDeposit(client, address(token), amount);
        vm.stopPrank();

        // Check that the security deposit was recorded
        ClientFundsManager.ClientFunds memory clientFunds = proxyEscrow
            .getClientFunds(client, address(token));
        assertEq(
            clientFunds.securityDeposit,
            amount,
            "Security deposit should match"
        );

        // Client unlocks security deposit
        uint256 unlockAmount = 0.5 ether;
        uint256 refundAmount = 0.1 ether;
        uint256 payoutAmount = 0.3 ether;

        vm.startPrank(operator);

        proxyEscrow.unlockSecurityDeposit(
            client,
            address(token),
            unlockAmount,
            refundAmount
        );
        vm.stopPrank();

        vm.startPrank(client);

        proxyEscrow.withdrawClientFunds(address(token));
        vm.stopPrank();

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

        proxyEscrow.withdrawProviderFunds(address(token));

        vm.expectRevert();
        proxyEscrow.withdrawProviderFunds(address(token));

        assertEq(
            token.balanceOf(address(provider)),
            payoutAmount,
            "Provider token balance should be payoutAmount"
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            amount - refundAmount - payoutAmount,
            "Escrow contract token balance should be amount - refundAmount - payoutAmount"
        );
    }
}
