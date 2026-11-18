// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./GameEconomyV1.sol";

/// @title GameEconomyV2
/// @author Anurag
/// @notice Upgrades GameEconomyV1 by adding batch material purchase functionality.
///         All V1 state (balances, materialPrice, recipe, nextUniqueId) is preserved
///         because this contract inherits V1's storage layout without adding new state
///         variables before existing ones (storage collision prevention).
/// @dev EIP-1967 Transparent Proxy upgrade authorized by ProxyAdmin (inherited pattern).
///      No new storage variables are introduced — only new functions — ensuring
///      zero risk of storage slot collision after upgrade.
contract GameEconomyV2 is GameEconomyV1 {

    // ──────────────────────────────────────────────────────────────────────────
    //  New Events
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a user batch-purchases multiple materials
    /// @param buyer Address of the buyer
    /// @param ids Array of material token IDs purchased
    /// @param amounts Array of quantities purchased for each material
    /// @param totalCurrencyBurned Total currency burned across all materials
    event MaterialsBatchPurchased(
        address indexed buyer,
        uint256[] ids,
        uint256[] amounts,
        uint256 totalCurrencyBurned
    );

    // ──────────────────────────────────────────────────────────────────────────
    //  GE-10: V2 Upgrade Feature — Add buyMaterialsBatch(ids[], amounts[]) to purchase
    //         multiple materials in one transaction with single currency burn.
    //         State persists from V1; tests confirm balances, recipes, and prices
    //         remain after upgrade.
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Purchase multiple materials in a single transaction
    /// @param ids Array of material IDs to buy (each must be valid material 1–999)
    /// @param amounts Array of quantities corresponding to each material ID
    /// @dev Currency is burned once for the total cost of all materials combined.
    ///      Follows checks-effects-interactions (GE-9):
    ///      1. Check all inputs and balances (no unbounded state writes).
    ///      2. Burn total currency in one operation (effect).
    ///      3. Mint all materials (interaction — internal only, no external calls).
    ///      Loop is bounded by caller-supplied array length; gas cost is proportional
    ///      to number of materials, which is the caller's choice.
    function buyMaterialsBatch(
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external whenNotPaused {
        // ── Checks ──────────────────────────────────
        uint256 len = ids.length;
        require(len > 0, "GameEconomy: empty batch");
        require(len == amounts.length, "GameEconomy: length mismatch");

        uint256 totalCost = 0;
        for (uint256 i = 0; i < len; ) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            require(id > 0 && id < CRAFTED_ID_START, "GameEconomy: invalid material ID");
            require(amount > 0, "GameEconomy: zero amount");
            uint256 price = materialPrice[id];
            require(price > 0, "GameEconomy: material not for sale");
            // Safe: Solidity 0.8 reverts on overflow for amount * price
            totalCost += price * amount;
            unchecked { ++i; }
        }

        require(
            balanceOf(msg.sender, CURRENCY_ID) >= totalCost,
            "GameEconomy: insufficient currency"
        );

        // ── Effects ──────────────────────────────────
        _burn(msg.sender, CURRENCY_ID, totalCost);

        // ── Interactions (internal mints only) ───────
        for (uint256 i = 0; i < len; ) {
            _mint(msg.sender, ids[i], amounts[i], "");
            unchecked { ++i; }
        }

        emit MaterialsBatchPurchased(msg.sender, ids, amounts, totalCost);
    }

    /// @notice Returns the version string of this implementation
    /// @return The string "V2" identifying this as the second implementation version
    /// @dev Used to verify upgrade was successful in tests and scripts
    function version() external pure returns (string memory) {
        return "V2";
    }
}
