

//! `vault` module is the core module of the nawhal protocol.
//! It should be responsible for hold the user's collateral

module nawhal::vault;

// move std
use std::ascii::String;
use std::type_name;

// sui libs
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, TreasuryCap};  
use sui::event;


// self modules

// ------ Constants ------ //
const MODULE_VERSION: u64 = 1;

// const BPS_IN_100_PCT: u64 = 10000;

// const DEFAULT_PROFIT_UNLOCK_DURATION_SEC: u64 = 100 * 60; // 100 minutes

// ------ Errors ------ //
const ETreasurySupplyPositive: u64 = 1;
const EWrongVersion: u64 = 2;
const EExceededTVLCap: u64 = 3;
const EVaultNotActive: u64 = 4;

// ------ Events ------ //
/// Call by `new` if success
public struct VaultCreatedEvent has copy, drop {
    vault_id: ID,
    created_at_ms: u64,
    created_at_epoch: u64,
    created_by: address,
}

/// Call by `deposit` if success
public struct DepositEvent has copy, drop {
    account_id: ID,
    vault_id: ID,
    amount: u64,
    collateral_type: String,
    deposited_at_ms: u64,
}

/// Call by `redeem_withdraw_ticket` if success
public struct WithdrawEvent has copy, drop {
    account_id: ID,
    vault_id: ID,
    amount: u64,
    collateral_type: String,
    withdrawn_at_ms: u64,
}

// ------ Structs ------ //
/// There can only ever be one `VaultCap` for a `Vault`
public struct VaultCap has key, store {
    id: UID,
    vault_id: ID,
}

/// A `Vault` that holds user's collateral and issue the LP tokens
public struct Vault<phantom T, phantom LPT> has key {
    id: UID,
    // The name of the vault
    name: String,
    // The description of the vault
    description: String,
    // Store the collateral balance
    collateral_balance: Balance<T>,
    // Treasury of the vault's yield-bearing assets
    lp_treasury: TreasuryCap<LPT>,
    // Deposit will be rejected if the thershold is reached.
    tvl_cap: Option<u64>,
    // Version control
    version: u64,   
    // Created at timestamp
    created_at_ms: u64,
    // Created at epoch
    created_at_epoch: u64,
    // Status of the vault
    status: VaultStatus,
}

/// Status of the vault
public enum VaultStatus has copy, drop, store {
    Active,
    Suspended,
    Closed,
}

// ------ Creators ------ //
public fun new<T, LPT>(
    lp_treasury: TreasuryCap<LPT>,
    name: String,
    description: String,
    tvl_cap: Option<u64>,
    clock: &Clock,
    ctx: &mut TxContext,
): (Vault<T, LPT>, VaultCap) {
    assert!(lp_treasury.total_supply() == 0, ETreasurySupplyPositive);

    let created_at_ms = clock.timestamp_ms();
    let created_at_epoch = ctx.epoch();

    let vault = Vault<T, LPT> {
        id: object::new(ctx),
        name,
        description,
        collateral_balance: balance::zero(),
        lp_treasury,      
        tvl_cap,
        version: MODULE_VERSION,
        created_at_ms,
        created_at_epoch,
        status: VaultStatus::Active,
    };

    let vault_id = object::id(&vault);

    emit_vault_created_event(
        vault_id,
        created_at_ms,
        created_at_epoch,
        ctx.sender(),
    );

    (
        vault,
        VaultCap {
            id: object::new(ctx),
            vault_id,
        }
    )
}

/// Create a new vault and share it
public fun new_vault_and_share<T, LPT>(
    lp_treasury: TreasuryCap<LPT>,
    name: String,
    description: String,
    tvl_cap: Option<u64>,
    clock: &Clock,
    ctx: &mut TxContext,
): VaultCap {
    let (vault, vault_cap) = new<T, LPT>(lp_treasury, name, description, tvl_cap, clock, ctx);
    vault.share_vault();

    vault_cap
}

/// Share the vault 
public(package) fun share_vault<T, LPT>(self: Vault<T, LPT>) {
    transfer::share_object(self);
}

/// Emit events
/// Emit vault created event
public fun emit_vault_created_event(
    vault_id: ID,
    created_at_ms: u64,
    created_at_epoch: u64,
    created_by: address,
) {
    let event = VaultCreatedEvent {
        vault_id,
        created_at_ms,
        created_at_epoch,
        created_by,
    };

    event::emit(event);
}

/// Emit deposited event
public fun emit_deposited_event<T>(
    account_id: ID,
    vault_id: ID,
    amount: u64,
    deposited_at_ms: u64,
) {
    let event = DepositEvent {
        account_id,
        vault_id,
        amount,
        collateral_type: type_name::get<T>().into_string(),
        deposited_at_ms,
    };

    event::emit(event);
}

/// Emit withdrawn event
public fun emit_withdrawn_event<T>(
    account_id: ID,
    vault_id: ID,
    amount: u64,
    withdrawn_at_ms: u64,
) {
    let event = WithdrawEvent {
        account_id,
        vault_id,
        amount,
        collateral_type: type_name::get<T>().into_string(),
        withdrawn_at_ms,
    };
    
    event::emit(event);
}       

/// ------ Getters ------ ///
public fun vault_id<T, LPT>(self: &Vault<T, LPT>): ID {
    object::id(self)
}

public fun name<T, LPT>(self: &Vault<T, LPT>): String {
    self.name
}

public fun description<T, LPT>(self: &Vault<T, LPT>): String {
    self.description
}

public fun collateral_balance_value<T, LPT>(self: &Vault<T, LPT>): u64 {
    self.collateral_balance.value()
}

public fun lp_total_supply<T, LPT>(self: &Vault<T, LPT>): u64 {
    self.lp_treasury.total_supply()
}

public fun tvl_cap<T, LPT>(self: &Vault<T, LPT>): Option<u64> {
    self.tvl_cap
}

public fun status<T, LPT>(self: &Vault<T, LPT>): VaultStatus {
    self.status
}

public fun version<T, LPT>(self: &Vault<T, LPT>): u64 {
    self.version
}     

/// Borrow the collateral balance of the vault t
public fun borrow_collateral_mut<T, LPT>(self: &mut Vault<T, LPT>): &mut Balance<T> {
    &mut self.collateral_balance
}

/// Vault id of VaultCap
public fun vault_of(self: &VaultCap): ID {
    self.vault_id
}

// ------ Asserts ------ //
/// Validate the status of the vault
public fun assert_status<T, LPT>(vault: &Vault<T, LPT>) {
    assert!(vault.status == VaultStatus::Active, EVaultNotActive);
}   

/// Validate the version of the vault
public fun assert_version<T, LPT>(vault: &Vault<T, LPT>) {
    assert!(vault.version == MODULE_VERSION, EWrongVersion);
}   

/// Validate the TVL cap of the vault
public fun assert_tvl_cap<T, LPT>(vault: &Vault<T, LPT>) {
    assert!(
        vault.tvl_cap.is_none() || 
            *vault.tvl_cap.borrow() >= vault.collateral_balance.value(), 
        EExceededTVLCap
    );
}

#[test_only]
public fun destroy_for_testing<T, LPT>(self: Vault<T, LPT>) {
    let Vault { id, collateral_balance, lp_treasury, name:_, description:_, tvl_cap: _, 
        version: _, created_at_ms: _, created_at_epoch: _, status: _ } = self;

    id.delete();
    collateral_balance.destroy_for_testing();
    transfer::public_share_object(lp_treasury);
}

#[test_only]
public fun destroy_cap_for_testing(self: VaultCap) {
    let VaultCap { id, vault_id: _ } = self;
    id.delete();
}

#[test_only]
public struct TEST_SUI has drop {}

#[test_only]
public struct LP_SUI has drop {}

#[test]
fun new_vault_should_work() {
    let mut ctx = tx_context::dummy();

    let lp_treasury = coin::create_treasury_cap_for_testing<LP_SUI>(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);
    let (vault, vault_cap) = new<TEST_SUI, LP_SUI>( lp_treasury, b"test name".to_ascii_string(), b"test description".to_ascii_string(), option::none(), &clock, &mut ctx);

    assert!(vault.vault_id() == vault_cap.vault_of());
    assert!(vault.name() == b"test name".to_ascii_string());
    assert!(vault.description() == b"test description".to_ascii_string());

    vault.destroy_for_testing();
    vault_cap.destroy_cap_for_testing();
    clock.destroy_for_testing();

}