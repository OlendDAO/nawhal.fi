
/// This module is used to define all the data structures for the account module

module nawhal::account_ds;

use std::ascii::String;
use std::type_name::{Self, TypeName};

use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::clock::Clock;
use sui::event;
use sui::object_table::{Self as ot, ObjectTable};
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};
use sui::vec_map::{Self, VecMap};
/// Allow calling `.share` to share  `AccountRegistry`
public use fun share_registry as AccountRegistry.share;

/// Allow calling `.transfer` to transfer `AccountProfileCap`
public use fun transfer_profile_cap as AccountProfileCap.transfer;

// ------ Constants ------ //
const MAX_NAME_LENGTH: u64 = 64;

// ------ Errors ------ //
const EINVALID_NAME: u64 = 1;
const EAccountAlreadyRegistered: u64 = 2;
const EOwnerAlreadyRegistered: u64 = 3;

// ------ Events ------ //
public struct AccountCreatedEvent has copy, drop {
    account_id: ID,
    name: String,
    created_at_ms: u64,
}

// ------ Structs ------ //
/// The global registry of the accounts
public struct AccountRegistry has key {
    id: UID,
    created_at_ms: u64,
    created_at_epoch: u64,
    /// Store the (account_id, account) pair
    accounts: ObjectTable<ID, AccountProfile>,
    /// Store the (owner, account_id) pair
    owners: Table<address, ID>,
}

public enum AccountProfileStatus has copy, drop, store {
    Active,
    Pending,
    Cancelled,
}

/// The account of the user
public struct AccountProfile has key, store {
    id: UID,
    name: String,
    // Store (lending_protocol_id, staking_info) pair
    stakes: Bag,
    // Store (lending_protocol_id, debt_info) pair
    debts: VecMap<ID, DebtInfo>,
    latest_updated_ms: u64,
    status: AccountProfileStatus,
}

/// The staking info of a vault
public struct StakingInfo<phantom T, phantom YT> has store {
    lending_protocol_id: ID,
    asset_type: TypeName,
    /// The shares after staked 
    shares: Balance<YT>,
    /// The total amount of the staking `T
    total_asset_amount: u64,
    latest_updated_ms: u64,
}

/// The debt info of a pool
public struct DebtInfo has store, copy, drop {
    pool_id: ID,
    debt_type: TypeName,
    value: u64,
}

/// The owner cap of the account
public struct AccountProfileCap has key {
    id: UID,
    account_id: ID,
    /// Store the derivation AccountProfileCap's id
    delegatees: VecSet<ID>,
}

/// Create AccountRegistry 
public fun new_registry(ctx: &mut TxContext): AccountRegistry {
    AccountRegistry {
        id: object::new(ctx),
        created_at_ms: ctx.epoch_timestamp_ms(),
        created_at_epoch: ctx.epoch(),
        accounts: ot::new(ctx),
        owners: table::new(ctx),
    }
}

/// Create a new account profile
/// Abort if the name is invalid
public fun new_profile(
    name: String,
    created_at_ms: u64,
    ctx: &mut TxContext,
): (AccountProfile, AccountProfileCap) {
    validate_name(name);

    let profile = AccountProfile {
        id: object::new(ctx),
        name,
        stakes: bag::new(ctx),
        debts: vec_map::empty(),
        latest_updated_ms: created_at_ms,
        status: AccountProfileStatus::Active,
    };

    let cap = AccountProfileCap {
        id: object::new(ctx),
        account_id: profile.account_id(),
        delegatees: vec_set::empty(),
    };

    emit_account_created_event(profile.account_id(), name, created_at_ms);

    (profile, cap)
}

public fun new_staking_info<T, YT>(
    lending_protocol_id: ID,
    total_asset_amount: u64,
    shares: Balance<YT>,
    latest_updated_ms: u64,
): StakingInfo<T, YT> {
    StakingInfo {
        lending_protocol_id,
        asset_type: type_name::get<T>(),
        shares,
        total_asset_amount,
        latest_updated_ms,
    }
}

public fun new_debt_info<T>(
    pool_id: ID,
    value: u64,
): DebtInfo {
    DebtInfo {
        pool_id,
        debt_type: type_name::get<T>(),
        value,
    }
}

/// Share the AccountRegistry
public fun share_registry(registry: AccountRegistry) {
    transfer::share_object(registry);
}

/// Transfer the AccountProfileCap to the user
public fun transfer_profile_cap(self: AccountProfileCap, recipient: address) {
    transfer::transfer(self, recipient);
}

/// Create a account for the user and register it
/// Abort if the name is invalid
public fun new_account_and_register(
    registry: &mut AccountRegistry,
    name: Option<String>,
    owner: address,
    latest_updated_ms: u64, 
    ctx: &mut TxContext,
): AccountProfileCap {
    let name = name.get_with_default(ctx.sender().to_ascii_string());

    let (profile, cap) = new_profile(name, latest_updated_ms, ctx);

    registry.add_owner(owner, profile.account_id());
    registry.add_account(profile);

    cap
}

/// Create a new account and register it
public fun create_account_and_register(
    registry: &mut AccountRegistry,
    name: Option<String>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let cap = registry.new_account_and_register(name, ctx.sender(), clock.timestamp_ms(), ctx);
    let account_id = cap.account_of();

    cap.transfer(ctx.sender());

    account_id
}

/// Borrow account profile or create it if it doesn't exist
public fun borrow_or_create_profile(registry: &mut AccountRegistry, clock: &Clock, ctx: &mut TxContext): &mut AccountProfile {
    let sender = ctx.sender();
    let account_id_opt = registry.account_id_of(sender);

    let account_id = if (account_id_opt.is_none()) {
        let cap = registry.new_account_and_register(option::none(), sender, clock.timestamp_ms(), ctx);
        let account_id = cap.account_of();
        transfer_profile_cap(cap, sender);

        account_id
    } else {
        *account_id_opt.borrow()
    };

    registry.borrow_account_mut(account_id)
}

/// Add a new account profile to the registry
/// Abort if the account already exists
public(package) fun add_account(registry: &mut AccountRegistry, account: AccountProfile) {
    let account_id = account.account_id();

    validate_account_registered(registry, account_id);
    
    registry.accounts.add(account_id, account);
}

/// Add a new owner to the registry
public(package) fun add_owner(registry: &mut AccountRegistry, owner: address, account_id: ID) {
    validate_user_registered(registry, owner);

    registry.owners.add(owner, account_id);
}

/// Add the staking infos to the account profile, including shares
public(package) fun add_staking_shares<T, YT>(
    self: &mut AccountProfile, 
    protocol_id: ID, 
    shares: Balance<YT>, 
    total_asset_amount: u64, 
    latest_updated_ms: u64
) {
    if (self.stakes.contains(protocol_id)) {
        let stakes = self.stakes.borrow_mut<ID, StakingInfo<T, YT>>(protocol_id);
        stakes.shares.join(shares);
        stakes.total_asset_amount = stakes.total_asset_amount + total_asset_amount;
    } else {
        self.stakes.add(protocol_id, new_staking_info<T, YT>(protocol_id, 
        total_asset_amount, shares, latest_updated_ms));
    }
}

/// Take shares from the staking info.
/// Abort if the shares are less than the amount to take
public(package) fun take_staking_shares<T, YT>(self: &mut AccountProfile, lending_protocol_id: ID, amount: u64): Balance<YT> {
    let stakes = self.stakes.borrow_mut<ID, StakingInfo<T, YT>>(lending_protocol_id);
    stakes.shares.split(amount)
}

/// Subtract the staking value
/// Abort if the staking value is less than the value to subtract or the staking info does not exist
public(package) fun sub_staking_value<T, YT>(self: &mut AccountProfile, lending_protocol_id: ID, value: u64) {
    let stakes = self.stakes.borrow_mut<ID, StakingInfo<T, YT>>(lending_protocol_id);

    stakes.total_asset_amount = stakes.total_asset_amount - value;
}

/// Remove staking info
/// Abort if the staking info does not exist
public(package) fun remove_staking_info<T, YT>(self: &mut AccountProfile, lending_protocol_id: ID): StakingInfo<T, YT> {
    self.stakes.remove(lending_protocol_id)
}

/// Add the debt value
public(package) fun add_debt_value(self: &mut AccountProfile, pool_id: ID, value: u64) {
    let debts = self.debts.get_mut(&pool_id);

    debts.value = debts.value + value;
}

/// Subtract the debt value
/// Abort if the debt value is less than the value to subtract or the debt info does not exist
public(package) fun sub_debt_value(self: &mut AccountProfile, pool_id: ID, value: u64) {
    let debts = self.debts.get_mut(&pool_id);

    debts.value = debts.value - value;
}

/// Remove debt info
/// Abort if the debt info does not exist
public(package) fun remove_debt_info(self: &mut AccountProfile, pool_id: ID) {
    self.debts.remove(&pool_id);
}

/// Update the latest updated time of the account profile
public(package) fun update_latest_updated_ms(self: &mut AccountProfile, latest_updated_ms: u64) {
    self.latest_updated_ms = latest_updated_ms;
}

// ------ Getters ------ //
public fun account_id(self: &AccountProfile): ID {
    object::id(self)
}

public fun name(self: &AccountProfile): String {
    self.name
}

/// Get the staking total amount of the protocol id
/// Returns 0 if the protocol id does not exist
public fun stake_total_amount<T, YT>(self: &AccountProfile, protocol_id: ID): u64 {
    if (self.stakes.contains(protocol_id)) {
        let stake_info = self.stakes.borrow<ID, StakingInfo<T, YT>>(protocol_id);
        stake_info.total_asset_amount
    } else {
        0
    }
}
    
// /// Get the staaking total amount of the given protocol
// public fun staking_info<YT: store>(self: &AccountProfile, protocol_id: &ID): Option<&StakingInfo<YT>> {
//     if (self.stakes.contains(protocol_id)) {
//         option::some(self.stakes.borrow<ID, StakingInfo<YT>>(protocol_id))
//     } else {
//         option::none()
//     }
// }

public fun debt_info(self: &AccountProfile, pool_id: ID): Option<DebtInfo> {
    self.debts.try_get(&pool_id)
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

/// Get ID of the `AccountProfileCap` by the given address
public fun account_id_of(self: &AccountRegistry, owner: address): Option<ID> {
    if (self.owners.contains(owner)) {
        option::some(*self.owners.borrow(owner))
    } else {
        option::none()
    }
}

/// Get the account id of the `AccountProfileCap`
public fun account_of(self: &AccountProfileCap): ID {
    self.account_id
}

/// Get staking total amount
public fun staking_total_amount<T, YT>(self: &StakingInfo<T, YT>): u64 {
    self.total_asset_amount
}

/// Get staking type
public fun staking_asset_type<T, YT>(self: &StakingInfo<T, YT>): TypeName {
    self.asset_type
}

/// Validations
/// Validate the name of `AccountProfile` must be less than MAX_NAME_LENGTH and not empty
public fun validate_name(name: String) {
    let len = name.as_bytes().length();
    assert!(len <= MAX_NAME_LENGTH && len > 0, EINVALID_NAME );
}

/// Validate the account registered to registry or not
public fun validate_account_registered(registry: &AccountRegistry, account_id: ID) {
    assert!(!registry.accounts.contains(account_id), EAccountAlreadyRegistered);
}

/// Validate a user register to registry or not
public fun validate_user_registered(registry: &AccountRegistry, owner: address) {
    assert!(!registry.owners.contains(owner), EOwnerAlreadyRegistered);
}

/// Emit account created event
public fun emit_account_created_event(account_id: ID, name: String, created_at_ms: u64) {
    let event = AccountCreatedEvent {
        account_id,
        name,
        created_at_ms,
    };  

    event::emit(event);
}

/// For testing
/// Destroy AccountProfileCap for testing
#[test_only]
public fun destroy_account_profile_cap(cap: AccountProfileCap) {
    let AccountProfileCap { id, account_id: _, delegatees: _ } = cap;

    id.delete();
}

#[test]
fun test_add_account_should_work() {
    let mut ctx = tx_context::dummy();

    let mut registry = new_registry(&mut ctx);

    let alice_name = b"alice".to_ascii_string();

    let latest_updated_ms = 0;
    let alice_cap  = new_account_and_register(&mut registry, option::some(alice_name), @0xabc, latest_updated_ms, &mut ctx);

    assert!(registry.contains_account(alice_cap.account_of()), 0);

    destroy_account_profile_cap(alice_cap);

    registry.share();
}
