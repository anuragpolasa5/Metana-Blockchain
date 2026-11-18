/// Simple Storage Contract (L2-5, L2-6, L2-7)
///
/// A basic Cairo 1.0 smart contract implementing a simple storage system.
/// It allows setting and getting a single felt252 value on-chain.
///
/// Decorators used (L2-6):
/// - #[starknet::interface] : Defines the contract's external interface
/// - #[starknet::contract]  : Marks this module as a Starknet contract
/// - #[storage]             : Defines the contract's storage layout
/// - #[abi(embed_v0)]       : Exposes functions as external/view entry points

/// Interface definition for the SimpleStorage contract.
/// This defines the public API that external callers can interact with.
#[starknet::interface]
pub trait ISimpleStorage<TContractState> {
    /// Sets the stored value to a new felt252 value.
    /// This is an external (state-modifying) function.
    fn set(ref self: TContractState, value: felt252);

    /// Gets the currently stored felt252 value.
    /// This is a view (read-only) function that does not modify state.
    fn get(self: @TContractState) -> felt252;
}

/// The SimpleStorage contract module.
/// Stores a single felt252 value that can be read and written.
#[starknet::contract]
pub mod SimpleStorage {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    /// Storage struct defining all persistent state variables (L2-6: #[storage] decorator).
    /// 
    /// `stored_value`: The single felt252 value stored in this contract.
    ///                 Initialized to 0 by default when the contract is deployed.
    #[storage]
    struct Storage {
        stored_value: felt252,
    }

    /// Implementation of the ISimpleStorage interface.
    /// #[abi(embed_v0)] exposes these functions as external entry points (L2-6).
    #[abi(embed_v0)]
    impl SimpleStorageImpl of super::ISimpleStorage<ContractState> {
        /// Sets the stored value to the provided `value` parameter.
        ///
        /// # Arguments
        /// * `value` - The new felt252 value to store in the contract.
        ///
        /// # Behavior
        /// - This is an external function (modifies contract state).
        /// - Overwrites the previous stored value with the new one.
        /// - Any caller can invoke this function (no access control).
        fn set(ref self: ContractState, value: felt252) {
            // Write the new value to persistent storage
            self.stored_value.write(value);
        }

        /// Gets the currently stored felt252 value.
        ///
        /// # Returns
        /// The current felt252 value stored in the contract.
        ///
        /// # Behavior
        /// - This is a view function (does not modify contract state).
        /// - Returns 0 if no value has been set yet (default initialization).
        fn get(self: @ContractState) -> felt252 {
            // Read and return the value from persistent storage
            self.stored_value.read()
        }
    }
}
