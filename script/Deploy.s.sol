// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EscrowContract.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        EscrowContract escrow = new EscrowContract();
        // Optionally call initialize if needed:
        // escrow.initialize();

        vm.stopBroadcast();
    }
}