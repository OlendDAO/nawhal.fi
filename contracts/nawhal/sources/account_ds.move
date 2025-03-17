
/// This module is used to define all the data structures for the account module

module nawhal::account_ds;

use std::ascii::String;

use sui::object_table::{Self as ot, ObjectTable};

/// Allow calling `.share` to share  `AccountRegistry`
public use fun share_registry as AccountRegistry.share;

// ------ Constants ------ //
const MAX_NAME_LENGTH: u64 = 64;

// ------ Errors ------ //
const EINVALID_NAME: u64 = 1;
const EAccountAlreadyExists: u64 = 2;
// ------ Structs ------ //
/// The global registry of the accounts
public struct AccountRegistry has key {
    id: UID,
    created_at_ms: u64,
    created_at_epoch: u64,
    /// Store the (account_id, account) pair
    accounts: ObjectTable<ID, AccountProfile>,
}

/// The account of the user
public struct AccountProfile has key, store {
    id: UID,
    name: String,
    staking_value: u64,
    debt_value: u64,
}

/// The owner cap of the account
public struct AccountOwnerCap has key, store {
    id: UID,
    account_id: ID,
}

/// Create AccountRegistry 
public fun new_registry(ctx: &mut TxContext): AccountRegistry {
    AccountRegistry {
        id: object::new(ctx),
        created_at_ms: ctx.epoch_timestamp_ms(),
        created_at_epoch: ctx.epoch(),
        accounts: ot::new(ctx),
    }
}

/// Create a new account profile
/// Abort if the name is invalid
public fun new_profile(
    name: String,
    ctx: &mut TxContext,
): (AccountProfile, AccountOwnerCap) {
    validate_name(name);

    let profile = AccountProfile {
        id: object::new(ctx),
        name,
        staking_value: 0,
        debt_value: 0,
    };

    let cap = AccountOwnerCap {
        id: object::new(ctx),
        account_id: profile.account_id(),
    };

    (profile, cap)
}

/// Share the AccountRegistry
public fun share_registry(registry: AccountRegistry) {
    transfer::share_object(registry);
}

/// Create a account for the user and register it
/// Abort if the name is invalid
public fun new_account_and_register(
    registry: &mut AccountRegistry,
    name: Option<String>,
    ctx: &mut TxContext,
): AccountOwnerCap {
    let name = name.get_with_default(ctx.sender().to_ascii_string());

    let (profile, cap) = new_profile(name, ctx);

    registry.add_account(profile);

    cap
}

/// Add a new account profile to the registry
/// Abort if the account already exists
public fun add_account(registry: &mut AccountRegistry, account: AccountProfile) {
    let account_id = account.account_id();

    validate_account_exists(registry, account_id);
    
    registry.accounts.add(account_id, account);
}

// ------ Getters ------ //
public fun account_id(self: &AccountProfile): ID {
    object::id(self)
}

public fun name(self: &AccountProfile): String {
    self.name
}

public fun staking_value(self: &AccountProfile): u64 {
    self.staking_value
}

public fun debt_value(self: &AccountProfile): u64 {
    self.debt_value
}

public fun contains_account(self: &AccountRegistry, account_id: ID): bool {
    self.accounts.contains(account_id)
}

/// Borrow `AccountProfile` from `AccountRegistry`
public fun borrow_account(self: &AccountRegistry, account_id: ID): &AccountProfile {
    self.accounts.borrow(account_id)
}

/// Borrow `AccountProfile` from `AccountRegistry` mutably
public fun borrow_account_mut(self: &mut AccountRegistry, account_id: ID): &mut AccountProfile {
    self.accounts.borrow_mut(account_id)
}

public fun account_of(self: &AccountOwnerCap): ID {
    self.account_id
}

/// Validations
/// Validate the name of `AccountProfile` must be less than MAX_NAME_LENGTH and not empty
public fun validate_name(name: String) {
    let len = name.as_bytes().length();
    assert!(len <= MAX_NAME_LENGTH && len > 0, EINVALID_NAME );
}

/// Validate the account exists
public fun validate_account_exists(registry: &AccountRegistry, account_id: ID) {
    assert!(!registry.accounts.contains(account_id), EAccountAlreadyExists);
}

/// For testing
/// Destroy AccountOwnerCap for testing
#[test_only]
public fun destroy_account_owner_cap(cap: AccountOwnerCap) {
    let AccountOwnerCap { id, account_id: _ } = cap;

    id.delete();
}

#[test]
fun test_add_account_should_work() {
    let mut ctx = tx_context::dummy();

    let mut registry = new_registry(&mut ctx);

    let alice_name = b"alice".to_ascii_string();
    let alice_cap  = new_account_and_register(&mut registry, option::some(alice_name), &mut ctx);

    assert!(registry.contains_account(alice_cap.account_of()), 0);

    destroy_account_owner_cap(alice_cap);

    registry.share();
}
