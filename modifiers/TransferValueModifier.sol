pragma ton-solidity ^0.42.0;

/**
 * Error codes
 *     • 200 — Invalid transfer value
 */
contract TransferValueModifier {
    modifier validTransferValue(uint128 value) {
        require(value > 0 && value < address(this).balance, 200, "Invalid transfer value");
        _;
    }
}