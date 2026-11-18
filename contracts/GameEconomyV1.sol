// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title GameEconomyV1
/// @author Anurag
/// @notice Upgradeable ERC-1155 game economy contract deployed behind an EIP-1967
///         Transparent Proxy (OpenZeppelin TransparentUpgradeableProxy).
///         Token ID 0 = currency (fungible, fixed-price ETH sale at CURRENCY_PRICE per unit).
///         Token IDs 1–999 = materials (fungible, purchasable with currency).
///         Token IDs >= 1000 = crafted unique items (supply 1 each, never reused).
/// @dev Uses EIP-1967 Transparent Proxy pattern with OpenZeppelin upgradeable contracts v5.0.2.
///      Upgrade authorization is handled by a separate ProxyAdmin contract (not in implementation).
///      All value-flow paths apply checks-effects-interactions (CEI) pattern.
///      ReentrancyGuard protects ETH withdrawal. No tx.origin usage.
///      No unbounded loops in state-changing user paths.
contract GameEconomyV1 is
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ──────────────────────────────────────────────────────────────────────────
    //  Roles
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Role hash for accounts that can pause/unpause the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role hash for game admin operations (pricing, recipes, withdrawals)
    bytes32 public constant GAME_ADMIN_ROLE = keccak256("GAME_ADMIN_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Token ID for the fungible currency token
    uint256 public constant CURRENCY_ID = 0;

    /// @notice ETH cost per one currency unit (GE-3: fixed-price ETH sale model)
    uint256 public constant CURRENCY_PRICE = 0.001 ether;

    /// @notice First ID available for crafted unique items (IDs >= 1000)
    uint256 public constant CRAFTED_ID_START = 1000;

    // ──────────────────────────────────────────────────────────────────────────
    //  State Variables
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Next unused ID for crafted items; starts at CRAFTED_ID_START
    /// @dev Incremented atomically on each craft; ensures crafted IDs are never reused
    uint256 public nextUniqueId;

    /// @notice Price (in currency units) to buy one unit of a given material ID
    /// @dev Maps materialId => price. Only IDs 1–999 are valid materials.
    mapping(uint256 => uint256) public materialPrice;

    /// @notice Active crafting recipe: materialId => required quantity to burn
    mapping(uint256 => uint256) public recipe;

    /// @notice Ordered list of material IDs required by the active recipe
    /// @dev Bounded by admin-set recipe length; used to iterate recipe in craft().
    ///      No unbounded loops in state-changing paths (GE-9).
    uint256[] public recipeMaterialIds;

    // ──────────────────────────────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a user purchases currency with ETH
    /// @param buyer Address of the buyer
    /// @param amount Number of currency units minted
    /// @param ethPaid Amount of ETH paid
    event CurrencyBought(address indexed buyer, uint256 amount, uint256 ethPaid);

    /// @notice Emitted when admin withdraws ETH from the contract
    /// @param to Recipient address
    /// @param amount Amount of ETH withdrawn
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when a material price is set or updated
    /// @param id Material token ID
    /// @param price New price in currency units
    event MaterialPriceSet(uint256 indexed id, uint256 price);

    /// @notice Emitted when a user purchases materials with currency
    /// @param buyer Address of the buyer
    /// @param id Material token ID purchased
    /// @param amount Quantity of material minted
    event MaterialPurchased(address indexed buyer, uint256 indexed id, uint256 amount);

    /// @notice Emitted when the active crafting recipe is updated
    /// @param materialIds Array of material IDs in the recipe
    /// @param amounts Array of required quantities for each material
    event RecipeSet(uint256[] materialIds, uint256[] amounts);

    /// @notice Emitted when a user crafts a unique item
    /// @param crafter Address of the crafter
    /// @param uniqueId The newly minted unique token ID
    event Crafted(address indexed crafter, uint256 indexed uniqueId);

    // ──────────────────────────────────────────────────────────────────────────
    //  Constructor / Initializer
    // ──────────────────────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @dev Disables initializers on the implementation contract to prevent
    ///      direct initialization bypassing the proxy.
    constructor() {
        _disableInitializers();
    }

    // GE-1: Proxy & Upgradeability — Deploy behind an EIP-1967 Transparent Proxy with
    //       OZ upgradeable contracts. Initialize once, set roles (DEFAULT_ADMIN_ROLE,
    //       PAUSER_ROLE, GAME_ADMIN_ROLE), base URI, currency ID 0, material IDs
    //       starting from 1, and nextUniqueId for crafted items.
    //       Upgrade authorization is handled by the external ProxyAdmin contract.
    /// @notice Initialize the proxy state (called once on first deployment)
    /// @param uri_ Base URI for token metadata (supports {id} substitution)
    /// @param admin Address that receives all roles initially
    /// @dev This function replaces the constructor for upgradeable contracts.
    ///      Can only be called once due to the `initializer` modifier.
    function initialize(string memory uri_, address admin) public initializer {
        require(admin != address(0), "GameEconomy: admin is zero address");

        __ERC1155_init(uri_);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(GAME_ADMIN_ROLE, admin);

        nextUniqueId = CRAFTED_ID_START;
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-2: Pause Control — Role-gated pause/unpause. Paused state blocks
    //        currency buys, material purchases, and crafting.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Pause the contract, blocking buyCurrency, buyMaterial, craft, and withdraw
    /// @dev Only callable by accounts with PAUSER_ROLE
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract, re-enabling all operations
    /// @dev Only callable by accounts with PAUSER_ROLE
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-3: Currency Acquisition — Fixed-price ETH sale model.
    //        buyCurrency(amount) mints fungible token ID 0 for ETH at fixed price per unit.
    //        Checks price match, not paused, non-zero caller. ETH stays in contract.
    //        Emit CurrencyBought.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Buy `amount` units of currency (token ID 0) by sending exact ETH.
    /// @param amount Number of currency units to mint (must be > 0)
    /// @dev Price per unit is CURRENCY_PRICE (0.001 ETH). msg.value must equal
    ///      amount * CURRENCY_PRICE exactly. ETH remains in the contract for
    ///      admin withdrawal via withdraw(). Follows CEI pattern.
    ///      Includes zero address check per reviewer feedback.
    function buyCurrency(uint256 amount) external payable whenNotPaused {
        // Checks
        require(msg.sender != address(0), "GameEconomy: zero address caller");
        require(amount > 0, "GameEconomy: amount must be > 0");
        require(msg.value == amount * CURRENCY_PRICE, "GameEconomy: incorrect ETH amount");

        // Effects — ETH already received by EVM before execution reaches here

        // Interactions — mint is internal, no external call
        _mint(msg.sender, CURRENCY_ID, amount, "");

        emit CurrencyBought(msg.sender, amount, msg.value);
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-4: Admin Withdrawals — withdraw(to, amount) lets admin pull ETH.
    //        Checks CEI pattern, not paused, non-zero address, enough balance.
    //        Uses nonReentrant. Emit Withdrawn.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Withdraw `amount` wei of ETH to address `to`
    /// @param to Recipient address (must not be zero address)
    /// @param amount Amount of ETH in wei to withdraw (must be > 0)
    /// @dev Role-gated to GAME_ADMIN_ROLE. Protected by nonReentrant modifier
    ///      since this is the only function making an external ETH call.
    ///      Follows checks-effects-interactions pattern (GE-9).
    function withdraw(address to, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(GAME_ADMIN_ROLE)
    {
        // Checks
        require(to != address(0), "GameEconomy: zero address");
        require(amount > 0, "GameEconomy: amount must be > 0");
        require(address(this).balance >= amount, "GameEconomy: insufficient balance");

        // Effects — no on-chain state to update; ETH balance IS the state

        // Interactions — external call last (CEI)
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "GameEconomy: ETH transfer failed");

        emit Withdrawn(to, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-5: Material Pricing & Storage — Maintain materialPrice[id] in currency units.
    //        Role-gated updates via setMaterialPrice. Emit MaterialPriceSet.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Set the currency cost for one unit of material `id`
    /// @param id Material token ID (must be in range 1–999)
    /// @param price Price in currency units per one material unit
    /// @dev Only callable by GAME_ADMIN_ROLE. Setting price to 0 effectively
    ///      removes the material from sale.
    function setMaterialPrice(uint256 id, uint256 price)
        external
        onlyRole(GAME_ADMIN_ROLE)
    {
        require(id > 0 && id < CRAFTED_ID_START, "GameEconomy: invalid material ID");
        materialPrice[id] = price;
        emit MaterialPriceSet(id, price);
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-6: Material Purchase — buyMaterial(id, amount) burns caller's currency,
    //        mints materials. Checks not paused, valid material, enough currency.
    //        Emit MaterialPurchased.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Buy `amount` units of material `id` by burning currency tokens
    /// @param id Material token ID to purchase (must be 1–999 with price set)
    /// @param amount Quantity to buy (must be > 0)
    /// @dev Burns (price * amount) currency from caller, then mints material.
    ///      Follows CEI: burn (effect) before mint (interaction, though internal).
    function buyMaterial(uint256 id, uint256 amount)
        external
        whenNotPaused
    {
        // Checks
        require(id > 0 && id < CRAFTED_ID_START, "GameEconomy: invalid material ID");
        require(amount > 0, "GameEconomy: amount must be > 0");
        uint256 price = materialPrice[id];
        require(price > 0, "GameEconomy: material not for sale");
        uint256 totalCost = price * amount;
        require(
            balanceOf(msg.sender, CURRENCY_ID) >= totalCost,
            "GameEconomy: insufficient currency"
        );

        // Effects — burn currency first (CEI)
        _burn(msg.sender, CURRENCY_ID, totalCost);

        // Interactions — mint material (internal, no external call)
        _mint(msg.sender, id, amount, "");

        emit MaterialPurchased(msg.sender, id, amount);
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-7: Craft Recipes — Store active recipe mapping material IDs to required
    //        quantities. Role-gated setRecipe sets one active recipe. Emit RecipeSet.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Set the single active crafting recipe
    /// @param materialIds Array of material IDs required for crafting (each 1–999)
    /// @param amounts Array of quantities required for each material ID
    /// @dev Replaces any previously set recipe. Arrays must be same length and non-empty.
    ///      The loop is bounded by the caller-supplied array length (admin-only path).
    ///      This satisfies GE-9's no-unbounded-loops requirement since only GAME_ADMIN
    ///      can call this with a reasonably-sized array.
    function setRecipe(uint256[] calldata materialIds, uint256[] calldata amounts)
        external
        onlyRole(GAME_ADMIN_ROLE)
    {
        require(materialIds.length > 0, "GameEconomy: empty recipe");
        require(materialIds.length == amounts.length, "GameEconomy: length mismatch");

        // Clear old recipe
        uint256 oldLen = recipeMaterialIds.length;
        for (uint256 i = 0; i < oldLen; ) {
            delete recipe[recipeMaterialIds[i]];
            unchecked { ++i; }
        }
        delete recipeMaterialIds;

        // Set new recipe
        for (uint256 i = 0; i < materialIds.length; ) {
            uint256 mid = materialIds[i];
            uint256 amt = amounts[i];
            require(mid > 0 && mid < CRAFTED_ID_START, "GameEconomy: invalid material in recipe");
            require(amt > 0, "GameEconomy: zero amount in recipe");
            recipe[mid] = amt;
            recipeMaterialIds.push(mid);
            unchecked { ++i; }
        }

        emit RecipeSet(materialIds, amounts);
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-8: Crafting Items — craft() burns recipe materials from caller, mints new
    //        unique ID with supply 1, increments nextUniqueId. Checks not paused,
    //        has materials, unique ID unused. Emit Crafted.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Craft a unique item by burning the active recipe's materials
    /// @dev Burns all materials specified in the active recipe from the caller,
    ///      then mints a new unique token (supply = 1) with an auto-incrementing ID.
    ///      The crafted ID is never reused. Follows CEI pattern:
    ///      1. Check balances 2. Record new ID + burn materials 3. Mint unique item.
    ///      Loop is bounded by recipe length (admin-set, small fixed list).
    function craft() external whenNotPaused {
        uint256 len = recipeMaterialIds.length;
        require(len > 0, "GameEconomy: no active recipe");

        // Checks — verify caller holds all required materials
        for (uint256 i = 0; i < len; ) {
            uint256 mid = recipeMaterialIds[i];
            require(
                balanceOf(msg.sender, mid) >= recipe[mid],
                "GameEconomy: insufficient materials"
            );
            unchecked { ++i; }
        }

        // Effects — record new unique ID before any minting
        uint256 newId = nextUniqueId;
        nextUniqueId = newId + 1;

        // Burn all required materials (effects before external interactions)
        for (uint256 i = 0; i < len; ) {
            uint256 mid = recipeMaterialIds[i];
            _burn(msg.sender, mid, recipe[mid]);
            unchecked { ++i; }
        }

        // Interactions — mint unique crafted item (supply = 1)
        _mint(msg.sender, newId, 1, "");

        emit Crafted(msg.sender, newId);
    }

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-9: Security & Best Practices — All value paths follow checks-effects-interactions,
    //        nonReentrant on ETH transfers, no tx.origin, no unbounded loops in
    //        state-changing code. Upgrade authorization handled by ProxyAdmin (Transparent Proxy).
    // ──────────────────────────────────────────────────────────────────────────

    // ──────────────────────────────────────────────────────────────────────────
    //  ERC-165 Interface Support
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Check if the contract supports a given interface
    /// @param interfaceId The interface identifier (ERC-165)
    /// @return bool True if the interface is supported
    /// @dev Required override due to multiple inheritance (ERC1155 + AccessControl)
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
