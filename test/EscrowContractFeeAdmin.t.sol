// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FilecoinPayV1} from "@filecoin-pay/FilecoinPayV1.sol";
import {console} from "forge-std/console.sol";

contract EscrowContractProviderFundsManager is Test {
    EscrowContract implementation;
    ERC1967Proxy escrowProxy;
    EscrowContract proxyEscrow;

    FilecoinPayV1 proxyPayments;

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

    //test setFeeValue
    function testSetFeeValue() public {
        uint256 newFee = 100;
        vm.startPrank(operator);
        proxyEscrow.setFeeValue(newFee);
        vm.stopPrank();

        assertEq(proxyEscrow.fee(), newFee, "Fee value should be updated");
    }

    //test setFeeBeneficiaryAddress
    function testSetFeeBeneficiaryAddress() public {
        address newBeneficiary = payable(makeAddr("newBeneficiary"));
        vm.startPrank(operator);
        proxyEscrow.setFeeBeneficiaryAddress(newBeneficiary);
        vm.stopPrank();

        assertEq(
            proxyEscrow.feeBeneficiaryAddress(),
            newBeneficiary,
            "Fee beneficiary address should be updated"
        );
    }

    //test updateFee
    function testUpdateFee() public {
        int256 newFee = 200;
        vm.startPrank(operator);
        proxyEscrow.updateFee(IERC20(token), newFee);
        vm.stopPrank();
        (uint256 totalToPay, uint256 totalPaid) = proxyEscrow.fees(
            address(token)
        );
        assertEq(totalToPay, uint256(newFee), "Fee should be updated");
        assertEq(totalPaid, 0, "Total paid should be zero");
    }

    // test withdrawFees
    function testWithdrawFees() public {
        int256 feeAmount = 5000 wei;

        uint256 amount = 1 ether;
        address newBeneficiary = payable(makeAddr("newBeneficiary"));

        // Client deposits security deposit
        vm.startPrank(client);
        token.approve(address(proxyEscrow), 200 ether);

        proxyEscrow.depositSecurityDeposit(IERC20(token), client, amount);
        vm.stopPrank();

        // Operator updates the fee to be paid
        vm.startPrank(operator);
        proxyEscrow.updateFee(IERC20(token), feeAmount);
        proxyEscrow.setFeeBeneficiaryAddress(newBeneficiary);
        vm.stopPrank();

        vm.startPrank(newBeneficiary);
        proxyEscrow.withdrawFees(IERC20(token));
        vm.stopPrank();

        assertEq(
            token.balanceOf(address(newBeneficiary)),
            5000 wei,
            "Beneficiary token balance should be 5000 wei"
        );
    }
}
