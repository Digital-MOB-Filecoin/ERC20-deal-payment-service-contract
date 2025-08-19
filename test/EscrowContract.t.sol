// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowContract.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowContractTest is Test {
    EscrowContract implementation;
    ERC1967Proxy proxy;
    EscrowContract proxyEscrow;

    function setUp() public {
        implementation = new EscrowContract();
        bytes memory data = abi.encodeWithSelector(
            EscrowContract.initialize.selector,
            ""
        );
        proxy = new ERC1967Proxy(address(implementation), data);
        proxyEscrow = EscrowContract(address(proxy));
    }

    function testOwnerIsSet() public view {
        assertEq(proxyEscrow.owner(), address(this));
    }

    function testCannotReinitialize() public {
        vm.expectRevert("InvalidInitialization()");
        proxyEscrow.initialize();
    }

    function testSetPaymentsContract() public {
        address paymentsContract = makeAddr("payments");
        proxyEscrow.setPaymentsContract(paymentsContract);
        assertEq(proxyEscrow.paymentsContract(), paymentsContract);
    }

    function testSetPaymentsContractNull() public {
        address paymentsContract = address(0);
        vm.expectRevert("Cannot set zero address");
        proxyEscrow.setPaymentsContract(paymentsContract);
    }

    function testUpgradeOnlyOwner() public {
        // Deploy a new implementation
        EscrowContract newImpl = new EscrowContract();
        assertEq(proxyEscrow.owner(), address(this));

        // Should succeed as owner
        proxyEscrow.upgradeToAndCall(address(newImpl), "");
        assertEq(_getImplementation(address(proxyEscrow)), address(newImpl));

        // Transfer ownership to another address
        address newOwner = address(0xBEEF);
        proxyEscrow.transferOwnership(newOwner);

        // Should succeed as new owner
        vm.prank(newOwner);
        proxyEscrow.upgradeToAndCall(address(implementation), "");

        // Should revert for non-owner
        vm.prank(address(0xCAFE));
        vm.expectRevert(
            "OwnableUnauthorizedAccount(0x000000000000000000000000000000000000cafE)"
        );
        proxyEscrow.upgradeToAndCall(address(newImpl), "");
    }

    function _getImplementation(
        address proxyAddr
    ) internal view returns (address impl) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        impl = address(uint160(uint256(vm.load(proxyAddr, slot))));
    }
}
