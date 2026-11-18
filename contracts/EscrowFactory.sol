// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./SimpleEscrow.sol";

/**
 * @title EscrowFactory
 * @notice Deploys SimpleEscrow contracts at deterministic CREATE2 addresses,
 *         records them per depositor, collects 1 % fees from releases, and
 *         allows the owner to withdraw accumulated fees.
 */
contract EscrowFactory is Ownable, Pausable, ReentrancyGuard {

    // ── Constants / Immutables ────────────────────────────────────────────────
    uint256 public constant FEE_PERCENT = 1;  // 1 %
    address public immutable feeRecipient;

    // ── State ─────────────────────────────────────────────────────────────────
    /// @notice Running total of fees held by this contract.
    uint256 public accumulatedFees;

    /// @notice Maps depositor → list of escrow addresses they own.
    mapping(address => address[]) public escrows;

    // ── Events ────────────────────────────────────────────────────────────────
    event EscrowCreated(
        address indexed escrowAddress,
        address indexed depositor,
        address indexed payee,
        uint256 deadline
    );
    event FeesWithdrawn(address recipient, uint256 amount);

    // ── Errors ────────────────────────────────────────────────────────────────
    error ZeroAddress();
    error DeadlineInPast();
    error NoFeesToWithdraw();
    error WithdrawFailed();

    // ── Constructor ───────────────────────────────────────────────────────────
    /// @param _feeRecipient Address that receives withdrawn fees.
    constructor(address _feeRecipient) Ownable(msg.sender) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    // ── F-2: createEscrow ────────────────────────────────────────────────────
    /**
     * @notice Deploy a new SimpleEscrow via CREATE2.
     * @param depositor  Address that will fund the escrow.
     * @param payee      Address that will receive funds on release.
     * @param deadline   Unix timestamp after which depositor may reclaim.
     * @param salt       Arbitrary bytes32 for address derivation.
     * @return escrow    Address of the newly deployed SimpleEscrow.
     */
    function createEscrow(
        address depositor,
        address payee,
        uint256 deadline,
        bytes32 salt
    ) external whenNotPaused returns (address escrow) {
        if (depositor == address(0) || payee == address(0)) revert ZeroAddress();
        if (deadline <= block.timestamp)                    revert DeadlineInPast();

        bytes memory bytecode = _creationCode(depositor, payee, deadline);

        assembly {
            escrow := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(escrow != address(0), "CREATE2 failed");

        escrows[depositor].push(escrow);
        emit EscrowCreated(escrow, depositor, payee, deadline);
    }

    // ── F-3: predictAddress ──────────────────────────────────────────────────
    /**
     * @notice Compute the CREATE2 address without deploying.
     * @param depositor  Same value as passed to createEscrow.
     * @param payee      Same value as passed to createEscrow.
     * @param deadline   Same value as passed to createEscrow.
     * @param salt       Same value as passed to createEscrow.
     */
    function predictAddress(
        address depositor,
        address payee,
        uint256 deadline,
        bytes32 salt
    ) external view returns (address) {
        bytes32 initCodeHash = keccak256(_creationCode(depositor, payee, deadline));
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            initCodeHash
                        )
                    )
                )
            )
        );
    }

    // ── F-4: getEscrows ──────────────────────────────────────────────────────
    /// @notice Return all escrow addresses created for a given depositor.
    function getEscrows(address depositor) external view returns (address[] memory) {
        return escrows[depositor];
    }

    // ── F-5: pause / unpause ─────────────────────────────────────────────────
    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ── F-6: withdrawFees ────────────────────────────────────────────────────
    /// @notice Owner pulls all accumulated fees to feeRecipient.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amt = accumulatedFees;
        if (amt == 0) revert NoFeesToWithdraw();
        accumulatedFees = 0;

        emit FeesWithdrawn(feeRecipient, amt);

        (bool ok,) = feeRecipient.call{value: amt}("");
        if (!ok) revert WithdrawFailed();
    }

    // ── Fee receiver (called by SimpleEscrow on release) ─────────────────────
    /// @notice SimpleEscrow contracts forward their fee here.
    receive() external payable {
        accumulatedFees += msg.value;
    }

    // ── Internal helpers ──────────────────────────────────────────────────────
    /// @dev Returns the creation bytecode for a SimpleEscrow with given params.
    function _creationCode(
        address depositor,
        address payee,
        uint256 deadline
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(SimpleEscrow).creationCode,
            abi.encode(address(this), depositor, payee, deadline, FEE_PERCENT)
        );
    }
}
