// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Payments} from "@fws-payments/Payments.sol";
import "../../src/EscrowContract.sol";

/**
 * @title RailTestHelper
 * @notice Helper contract for testing payment rail creation and validation
 */
contract RailTestHelper is Test {
    /**
     * @notice Validates that a payment rail was created correctly
     * @param proxyEscrow The EscrowContract proxy instance
     * @param proxyPayments The Payments contract proxy instance
     * @param token The token address for the rail
     * @param client The client address (payer)
     * @param amount The expected payment amount
     * @return railId The ID of the validated rail
     */
    function validateRailCreation(
        EscrowContract proxyEscrow,
        Payments proxyPayments,
        address token,
        address client,
        uint256 amount
    ) internal view returns (uint256 railId) {
        // Check that the rail was created
        railId = proxyEscrow.getRailId(token, client);
        assertGt(railId, 0, "Payment rail should have been created");

        // Check the rail details from the Payments contract
        Payments.RailView memory railView = proxyPayments.getRail(railId);
        assertEq(railView.token, token, "Token address in rail should match");
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

        return railId;
    }

    /**
     * @notice Validates settlement result values
     * @param result The settlement result struct to validate
     * @param expectedSettledAmount Expected total settled amount
     * @param expectedNetPayeeAmount Expected net payee amount
     * @param expectedPaymentFee Expected payment fee
     * @param expectedOperatorCommission Expected operator commission
     * @param expectedFinalEpoch Expected final settled epoch
     * @param expectedNote Expected note string
     */
    function validateSettlementResult(
        EscrowContract.SettlementResult memory result,
        uint256 expectedSettledAmount,
        uint256 expectedNetPayeeAmount,
        uint256 expectedPaymentFee,
        uint256 expectedOperatorCommission,
        uint256 expectedFinalEpoch,
        string memory expectedNote
    ) internal pure {
        assertEq(
            result.totalSettledAmount,
            expectedSettledAmount,
            "Settlement Amount should match expected"
        );
        assertEq(
            result.totalNetPayeeAmount,
            expectedNetPayeeAmount,
            "Net Payee Amount should match expected"
        );
        assertEq(
            result.totalPaymentFee,
            expectedPaymentFee,
            "Payment Fee should match expected"
        );
        assertEq(
            result.totalOperatorCommission,
            expectedOperatorCommission,
            "Operator Commission should match expected"
        );
        assertEq(
            result.finalSettledEpoch,
            expectedFinalEpoch,
            "Final Settled Epoch should match expected"
        );
        assertEq(result.note, expectedNote, "Note should match expected");
    }
}
