// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// BE-3: Deploy ERC20 token (prerequisite for Action 2)
/**
 * @title SimpleToken
 * @author Anurag
 * @notice A minimal ERC20 token implementation for testing batch call delegation.
 * @dev Implements transfer, approve, and transferFrom without OpenZeppelin dependencies.
 *      Used as the ERC20 token in the batch execution tests (Action 2: Transfer 100 tokens).
 */
contract SimpleToken {
    /// @notice The token name.
    string public name = "SimpleToken";

    /// @notice The token symbol.
    string public symbol = "STK";

    /// @notice The number of decimals (18, standard for ERC20).
    uint8 public decimals = 18;

    /// @notice The total supply of tokens.
    uint256 public totalSupply;

    /// @notice Mapping of address to token balance.
    mapping(address => uint256) public balanceOf;

    /// @notice Mapping of owner => spender => allowance amount.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Emitted when tokens are transferred.
    /// @param from The sender address (address(0) for minting).
    /// @param to The recipient address.
    /// @param value The amount of tokens transferred.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when an approval is set.
    /// @param owner The token owner granting approval.
    /// @param spender The address approved to spend tokens.
    /// @param value The approved amount.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Deploys the token with an initial supply minted to the deployer.
     * @param initialSupply The number of whole tokens to mint (will be multiplied by 10^decimals).
     */
    constructor(uint256 initialSupply) {
        totalSupply = initialSupply * 10 ** decimals;
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /**
     * @notice Transfers tokens from the caller to a recipient.
     * @dev Reverts if the caller has insufficient balance.
     * @param to The recipient address.
     * @param value The amount of tokens to transfer.
     * @return success Always returns true on success (reverts on failure).
     */
    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    // BE-3: Approve ERC20 token to be spent by BatchCallDelegation contract
    /**
     * @notice Approves a spender to transfer tokens on behalf of the caller.
     * @param spender The address to approve.
     * @param value The maximum amount the spender can transfer.
     * @return success Always returns true.
     */
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another using an allowance.
     * @dev Reverts if the from address has insufficient balance or if the caller
     *      has insufficient allowance.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return success Always returns true on success (reverts on failure).
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }
}
