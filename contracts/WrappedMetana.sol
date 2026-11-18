// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title WrappedMetana (wMTN)
/// @author Anurag
/// @notice ERC20 token with role-based mint and burn functionality.
///         Name: "Wrapped METANA", Symbol: "wMTN".
///         The deposit contract holds MINTER_ROLE and BURNER_ROLE.
/// @dev Access is controlled via OpenZeppelin AccessControl.
///      Mint and burn rights are granted to the DepositContract after deployment.
contract WrappedMetana is ERC20, AccessControl {
    /// @notice Role identifier for addresses allowed to mint wMTN.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role identifier for addresses allowed to burn wMTN.
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Deploys the WrappedMetana token and grants admin role to deployer.
    /// @dev The deployer should later grant MINTER_ROLE and BURNER_ROLE to the DepositContract.
    constructor() ERC20("Wrapped METANA", "wMTN") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Mint wMTN tokens to a specified address.
    /// @dev Only callable by addresses with MINTER_ROLE (the DepositContract).
    /// @param to The recipient address to receive minted tokens.
    /// @param amount The number of tokens to mint (in wei).
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Burn wMTN tokens from a specified address.
    /// @dev Only callable by addresses with BURNER_ROLE (the DepositContract).
    /// @param from The address whose tokens will be burned.
    /// @param amount The number of tokens to burn (in wei).
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }
}
