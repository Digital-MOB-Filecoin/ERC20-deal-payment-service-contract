// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FilecoinPayV1} from "@filecoin-pay/FilecoinPayV1.sol";

contract EscrowContractClientFundsManagerTest is Test {
    EscrowContract implementation;
    ERC1967Proxy escrowProxy;
    EscrowContract proxyEscrow;

    FilecoinPayV1 proxyPayments;

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
     * @notice Test deposit security deposit functionality
     * @dev This function tests the depositSecurityDeposit function in ClientFundsManagerStorage
     */
    function testDepositSecurityDeposit() public {
        uint256 amount = 1 ether;

        // Client deposits security deposit
        vm.startPrank(client);
        token.approve(address(proxyEscrow), 200 ether);

        proxyEscrow.depositSecurityDeposit(IERC20(token), client, amount);
        vm.stopPrank();

        // Check that the security deposit was recorded
        ClientFundsManager.ClientFunds memory clientFunds = proxyEscrow
            .getClientFunds(IERC20(token), client);
        assertEq(
            clientFunds.securityDeposit,
            amount,
            "Security deposit should match"
        );
    }

    /**
     * @notice Test deposit security deposit functionality using ERC20 permit
     * @dev This function tests the depositSecurityDepositWithPermit function in ClientFundsManagerStorage
     */
    function testDepositSecurityDepositWithPermit() public {
        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 days;
        uint256 clientPrivateKey = 0xA11CE;

        // Setup client with known private key
        address clientAddress = vm.addr(clientPrivateKey);
        token.mint(clientAddress, 100 ether);

        uint256 nonce = token.nonces(clientAddress);

        // Create permit signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                clientAddress,
                address(proxyEscrow),
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientPrivateKey, digest);

        // Client deposits security deposit with permit
        vm.prank(clientAddress);
        proxyEscrow.depositSecurityDepositWithPermit(
            IERC20(token),
            clientAddress,
            amount,
            deadline,
            v,
            r,
            s
        );

        // Check that the security deposit was recorded
        ClientFundsManager.ClientFunds memory clientFunds = proxyEscrow
            .getClientFunds(IERC20(token), clientAddress);
        assertEq(
            clientFunds.securityDeposit,
            amount,
            "Security deposit should match"
        );

        // Verify tokens were transferred
        assertEq(
            token.balanceOf(address(proxyEscrow)),
            amount,
            "Escrow contract should have received tokens"
        );
        assertEq(
            token.balanceOf(clientAddress),
            100 ether - amount,
            "Client balance should have decreased"
        );
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

        proxyEscrow.depositSecurityDeposit(IERC20(token), client, amount);
        vm.stopPrank();

        // Check that the security deposit was recorded
        ClientFundsManager.ClientFunds memory clientFunds = proxyEscrow
            .getClientFunds(IERC20(token), client);
        assertEq(
            clientFunds.securityDeposit,
            amount,
            "Security deposit should match"
        );

        // Client unlocks security deposit
        uint256 unlockAmount = 0.5 ether;
        uint256 refundAmount = 0.3 ether;
        vm.startPrank(operator);
        uint256 withdrawableAmount = proxyEscrow.getClientWithdrawableAmount(
            IERC20(token),
            client
        );

        assertEq(
            withdrawableAmount,
            0 ether,
            "Withdrawable amount should match, before unlock"
        );

        proxyEscrow.unlockSecurityDeposit(
            IERC20(token),
            client,
            unlockAmount,
            refundAmount
        );
        vm.stopPrank();

        withdrawableAmount = proxyEscrow.getClientWithdrawableAmount(
            IERC20(token),
            client
        );

        assertEq(
            withdrawableAmount,
            refundAmount,
            "Withdrawable amount should match, after unlock"
        );

        clientFunds = proxyEscrow.getClientFunds(IERC20(token), client);
        assertEq(
            clientFunds.securityDeposit,
            amount - unlockAmount,
            "Security deposit after unlock should match"
        );

        assertEq(
            clientFunds.refund,
            refundAmount,
            "Refund amount should match"
        );

        vm.startPrank(client);
        assertEq(
            token.balanceOf(address(client)),
            199 ether,
            "Client token balance should be 199 ether"
        );

        proxyEscrow.withdrawClientFunds(IERC20(token));

        assertEq(
            token.balanceOf(address(client)),
            199 ether + refundAmount,
            "Client token balance should be 199 ether + refundAmount"
        );

        assertEq(
            token.balanceOf(address(proxyEscrow)),
            amount - refundAmount,
            "Escrow contract token balance should be amount - refundAmount"
        );
    }
}
