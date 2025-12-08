// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/test/mocks/MockERC20.sol";

contract EscrowContractFlowTest is Test {
    MockERC20 token;
    address owner = address(0x1);
    address spender = address(0x2);
    address recipient = address(0x3);

    function setUp() public {
        // Deploy mock token
        vm.startPrank(owner);
        token = new MockERC20("Test Token", "TEST");
        token.mint(owner, 100 ether); // Mint tokens to owner
        vm.stopPrank();
    }

    function testPermitAndTransfer() public {
        uint256 amount = 10 ether;
        uint256 deadline = block.timestamp + 1 days;
        uint256 ownerPrivateKey = 0xA11CE;

        // Setup owner with known private key
        address ownerAddress = vm.addr(ownerPrivateKey);
        vm.startPrank(ownerAddress);
        token.mint(ownerAddress, 100 ether);
        vm.stopPrank();

        uint256 initialOwnerBalance = token.balanceOf(ownerAddress);
        uint256 nonce = token.nonces(ownerAddress);

        // 1. Create permit signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                ownerAddress,
                spender,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // 2. Call permit to approve spender
        token.permit(ownerAddress, spender, amount, deadline, v, r, s);

        // 3. Verify allowance was set
        assertEq(
            token.allowance(ownerAddress, spender),
            amount,
            "Allowance should be set"
        );

        // 4. Transfer tokens using transferFrom as the spender
        vm.prank(spender);
        token.transferFrom(ownerAddress, recipient, amount);

        // 5. Assert balances
        assertEq(
            token.balanceOf(recipient),
            amount,
            "Recipient should receive tokens"
        );
        assertEq(
            token.balanceOf(ownerAddress),
            initialOwnerBalance - amount,
            "Owner balance should decrease"
        );
        assertEq(
            token.allowance(ownerAddress, spender),
            0,
            "Allowance should be consumed"
        );
    }
}
