/// Unit tests for the SimpleStorage contract (L2-10)
///
/// Tests the set and get functions using snforge test framework.

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use simple_storage::ISimpleStorageDispatcher;
use simple_storage::ISimpleStorageDispatcherTrait;

/// Helper function to deploy the SimpleStorage contract for testing.
/// Returns a dispatcher that can be used to call contract functions.
fn deploy_contract() -> ISimpleStorageDispatcher {
    // Declare the contract class
    let contract = declare("SimpleStorage").unwrap().contract_class();

    // Deploy with no constructor arguments
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();

    // Return a dispatcher bound to the deployed contract address
    ISimpleStorageDispatcher { contract_address }
}

/// Test that the initial stored value is 0 (default).
#[test]
fn test_initial_value_is_zero() {
    let dispatcher = deploy_contract();

    // The default value should be 0 (felt252 default)
    let value = dispatcher.get();
    assert(value == 0, 'Initial value should be 0');
}

/// Test that set() correctly updates the stored value.
#[test]
fn test_set_value() {
    let dispatcher = deploy_contract();

    // Set the value to 42
    dispatcher.set(42);

    // Verify the value was stored correctly
    let value = dispatcher.get();
    assert(value == 42, 'Value should be 42');
}

/// Test that set() can overwrite a previously stored value.
#[test]
fn test_overwrite_value() {
    let dispatcher = deploy_contract();

    // Set initial value
    dispatcher.set(100);
    let value1 = dispatcher.get();
    assert(value1 == 100, 'Value should be 100');

    // Overwrite with a new value
    dispatcher.set(200);
    let value2 = dispatcher.get();
    assert(value2 == 200, 'Value should be 200');
}

/// Test setting the value to 0 explicitly.
#[test]
fn test_set_zero() {
    let dispatcher = deploy_contract();

    // Set a non-zero value first
    dispatcher.set(999);
    assert(dispatcher.get() == 999, 'Value should be 999');

    // Set back to 0
    dispatcher.set(0);
    assert(dispatcher.get() == 0, 'Value should be 0 again');
}

/// Test with a large felt252 value.
#[test]
fn test_large_value() {
    let dispatcher = deploy_contract();

    // Use a large felt252 value
    let large_value: felt252 = 3618502788666131213697322783095070105623107215331596699973092056135872020480;
    dispatcher.set(large_value);

    let stored = dispatcher.get();
    assert(stored == large_value, 'Large value mismatch');
}
