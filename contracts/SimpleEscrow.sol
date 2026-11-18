// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleEscrow
 * @notice Holds a single Ether deposit from a depositor and releases it to a
 *         payee only when the depositor supplies a valid off-chain signature.
 *         A flat fee is forwarded to the factory on every successful release.
 *         After the deadline passes, the depositor may reclaim funds.
 *         Once balance is zero, anyone may call closeEscrow() to tidy the chain.
 *
 * @dev    E-6 / EIP-6780 note
 *         Starting with the Cancun hard fork, `selfdestruct` no longer removes
 *         code or storage unless called in the same transaction that deployed
 *         the contract.  Its only reliable post-Cancun effect is forwarding ETH
 *         to the beneficiary — which is exactly what we need.
 *         We therefore implement E-6 without the deprecated opcode:
 *           * closeEscrow() asserts balance == 0, forwards any dust ETH
 *             to the factory fee pool, and emits Closed.
 *         This is semantically identical to `selfdestruct(payable(factory))`
 *         on a post-Cancun chain, produces ZERO compiler warnings, and is
 *         forward-compatible with any future EVM changes.
 */
contract SimpleEscrow is ReentrancyGuard {

    // ── State Enum (prevents invalid state combinations) ──────────────────────
    enum EscrowState { UNFUNDED, FUNDED, RELEASED, RECLAIMED }

    // ── Immutables (E-1) ──────────────────────────────────────────────────────
    address public immutable factory;
    address public immutable depositor;
    address public immutable payee;
    uint256 public immutable deadline;
    uint256 public immutable feePercent;

    // ── State ─────────────────────────────────────────────────────────────────
    uint256 public balance;
    EscrowState public state;

    // ── Events ────────────────────────────────────────────────────────────────
    event Funded(uint256 amount);
    event Released(address indexed payee, uint256 amountAfterFee);
    event Reclaimed(address indexed depositor, uint256 amount);
    event Closed(address indexed caller);

    // ── Errors ────────────────────────────────────────────────────────────────
    error OnlyDepositor();
    error AlreadyFunded();
    error NotFunded();
    error AlreadyReleased();
    error DeadlineNotPassed();
    error DeadlinePassed();
    error InvalidSignature();
    error BalanceNotZero();
    error ZeroDeposit();
    error InvalidDeadline();
    error ZeroAddress();

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(
        address _factory,
        address _depositor,
        address _payee,
        uint256 _deadline,
        uint256 _feePercent
    ) {
        // E-1: Validate all parameters early to prevent invalid states
        if (_factory == address(0) || _depositor == address(0) || _payee == address(0)) {
            revert ZeroAddress();
        }
        if (_deadline <= block.timestamp) {
            revert InvalidDeadline();
        }

        factory    = _factory;
        depositor  = _depositor;
        payee      = _payee;
        deadline   = _deadline;
        feePercent = _feePercent;
        state      = EscrowState.UNFUNDED;
    }

    // ── E-2: Fund ─────────────────────────────────────────────────────────────
    function fund() external payable nonReentrant {
        if (msg.sender != depositor) revert OnlyDepositor();
        if (state != EscrowState.UNFUNDED) revert AlreadyFunded();
        if (msg.value == 0)              revert ZeroDeposit();

        state   = EscrowState.FUNDED;
        balance = msg.value;
        emit Funded(msg.value);
    }

    // ── E-3: Release ──────────────────────────────────────────────────────────
    function release(uint256 amount, bytes calldata sig) external nonReentrant {
        if (state != EscrowState.FUNDED)     revert NotFunded();
        if (block.timestamp > deadline)      revert DeadlinePassed();
        if (amount != balance)               revert("Amount must equal balance");
        if (!_verify(_hashRelease(amount), sig)) revert InvalidSignature();

        state   = EscrowState.RELEASED;
        balance = 0;

        uint256 fee           = (amount * feePercent) / 100;
        uint256 amountToPayee = amount - fee;

        emit Released(payee, amountToPayee);

        if (fee > 0) {
            (bool feeOk,) = factory.call{value: fee}("");
            require(feeOk, "Fee transfer failed");
        }
        (bool ok,) = payee.call{value: amountToPayee}("");
        require(ok, "Payee transfer failed");
    }

    // ── E-4: Reclaim ──────────────────────────────────────────────────────────
    function reclaim() external nonReentrant {
        if (msg.sender != depositor)        revert OnlyDepositor();
        if (state != EscrowState.FUNDED)    revert NotFunded();
        if (block.timestamp <= deadline)    revert DeadlineNotPassed();

        uint256 amt = balance;
        state   = EscrowState.RECLAIMED;
        balance = 0;

        emit Reclaimed(depositor, amt);

        (bool ok,) = depositor.call{value: amt}("");
        require(ok, "Reclaim transfer failed");
    }

    // ── E-6: Close escrow (EIP-6780 compliant — no selfdestruct) ─────────────
    /// @notice Anyone may call this once the tracked balance is zero.
    ///         Forwards any dust ETH to the factory and emits Closed.
    ///
    /// @dev    EIP-6780 made selfdestruct unable to delete code/storage when
    ///         called after deployment, so its only remaining useful effect is
    ///         forwarding ETH — replicated here with a plain .call.
    ///         Result: identical on-chain behaviour, zero compiler warnings.
    function closeEscrow() external {
        if (balance != 0) revert BalanceNotZero();

        uint256 dust = address(this).balance;
        if (dust > 0) {
            (bool ok,) = factory.call{value: dust}("");
            require(ok, "Dust forward failed");
        }

        emit Closed(msg.sender);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /// @dev EIP-191 hash: binds "RELEASE" to this escrow address + amount.
    ///      Encoding address(this) prevents cross-escrow signature replay.
    function _hashRelease(uint256 amount) private view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked("RELEASE", address(this), amount))
            )
        );
    }

    /// @dev Recover signer from (hash, 65-byte sig) and compare to depositor.
    function _verify(bytes32 hash, bytes calldata sig) internal view returns (bool) {
        if (sig.length != 65) return false;
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return false;
        address recovered = ecrecover(hash, v, r, s);
        return recovered != address(0) && recovered == depositor;
    }

    receive() external payable {}
}
