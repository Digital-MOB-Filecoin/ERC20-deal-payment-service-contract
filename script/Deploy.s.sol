// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EscrowContract.sol";
import "../src/test/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external {
        /*
            EscrowContract implementation deployed at: 0x6a8c15b62812FeCb80109B9e116B4be99aBACC97
            EscrowContract deployed at: 0x823e631fE711f1777C9fF320A8Ee65e813593f3C
            MockERC20 Token1 deployed at: 0xd80AA63A4211D1565a5BA6C784E37317b5f68C03
            MockERC20 Token2 deployed at: 0x9a76Db7B77CD4855C2C3fa80eFe3cf33Abdd49Ff
            Payments contract deployed at: 0x75fAEe56ce7afb25Aa9C3A209Caa0F98D61426c4
        */
        vm.startBroadcast();

        MockERC20 token1 = new MockERC20("Test Token 1", "TEST1");
        MockERC20 token2 = new MockERC20("Test Token 2", "TEST2");

        // Setup client and operator accounts
        address client100 = address(0x69e4201786d25a97D1E062f3e4e8D65dc166944D);
        address client101 = address(0x26e83a793f8a42dcC482eE097F1Ae3953d74cc1b);

        address operator = address(0xF7f7B16aADC8c528C0e49f26afC231FEC33326e7);

        // Deploy Payments contract
        Payments payments = new Payments();

        // Deploy EscrowContract
        EscrowContract implementation = new EscrowContract();
        bytes memory escrowData = abi.encodeWithSelector(
            EscrowContract.initialize.selector
        );
        ERC1967Proxy escrowProxy = new ERC1967Proxy(
            address(implementation),
            escrowData
        );
        EscrowContract proxyEscrow = EscrowContract(address(escrowProxy));

        // Set the payments contract in the escrow
        proxyEscrow.setPaymentsContract(address(payments));
        proxyEscrow.addOperator(operator);

        console.log(
            "EscrowContract implementation deployed at:",
            address(implementation)
        );
        console.log("EscrowContract deployed at:", address(proxyEscrow));
        console.log("MockERC20 Token1 deployed at:", address(token1));
        console.log("MockERC20 Token2 deployed at:", address(token2));
        console.log("Payments contract deployed at:", address(payments));
        vm.stopBroadcast();
    }
}
