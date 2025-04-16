//! The Lending Protocol is a module that manages the lending business of the protocol.
//! It is responsible for:
//! - Stake assets to the protocol
//! - Withdraw assets from the protocol
//! - Configure the protocol
//! - Manage the protocol's liquidity
//!

module nawhal::lending_protocol;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::table::{Self, Table};
use sui::clock::Clock;

use nawhal::admin::AdminCap;
use nawhal::liquidity_layer_model::{LiquidityLayer, new_lending_protocol_type};
use nawhal::liquidity_layer;
use nawhal::account_ds::{AccountProfile, AccountRegistry, AccountProfileCap};

// ------- Errors ------- //
const EInsufficientBalance: u64 = 20001;

// ------- structs ------- //
/// Lending protocol is a protocol that allows users to deposit and withdraw assets
public struct LendingProtocol<phantom T> has key, store {
    id: UID,
    // Stores (account_id, account_profile) pair
    stakers: Table<ID, AccountProfile>,
    created_at_ms: u64,
    created_at_epoch: u64,
}

// ------- init ------- //
// /// Initialize the lending protocol and share it to the sender
// fun init(ctx: &mut TxContext) {

// }

// ------- Logic ------- //
/// Deposit assets to the protocol
public fun deposit<T>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    payload: Coin<T>, 
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let profile = registry.borrow_or_create_profile(clock, ctx);
    let protocol_id = self.protocol_id();

    profile.add_staking_value<T>(protocol_id, payload.value(), clock.timestamp_ms());

    liquidity_layer::deposit(liquidity_layer, protocol_id, payload.into_balance(), clock, ctx);
}

/// Withdraw assets from the protocol
public fun withdraw<T>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    cap: &AccountProfileCap,
    amount: u64,
    clock: &Clock, 
    ctx: &mut TxContext
): Balance<T> {
    if (amount == 0) {
        return balance::zero()
    };

    let protocol_id = self.protocol_id();

    let profile = registry.borrow_account_mut(cap.account_of());

    let stake_total_amount = profile.stake_total_amount(&protocol_id);

    check_stake_total_amount_greater_than_or_equal_to_amount(stake_total_amount, amount);

    profile.sub_staking_value(protocol_id, amount);

    liquidity_layer::withdraw(liquidity_layer, protocol_id, amount, clock, ctx)
}

/// ------- Governance ------- //
/// Register a new lending protocol to LiquidityLayer
public fun register_lending_protocol<T>(liquidity_layer: &mut LiquidityLayer, admin_cap: &AdminCap, ctx: &mut TxContext) {
    let lending_protocol = new_lending_protocol<T>(ctx);

    liquidity_layer::register_protocol<T>(liquidity_layer, admin_cap, lending_protocol.protocol_id(), new_lending_protocol_type(), ctx);
    
    transfer::share_object(lending_protocol);
}

// ------- new structs ------- //
/// New a new LendingProtocol
public fun new_lending_protocol<T>(ctx: &mut TxContext): LendingProtocol<T> {
    LendingProtocol {
        id: object::new(ctx),
        stakers: table::new(ctx),
        created_at_ms: ctx.epoch_timestamp_ms(),
        created_at_epoch: ctx.epoch(),
    }
}

// ------- Checks ------- //
public fun check_stake_total_amount_greater_than_or_equal_to_amount(stake_total_amount: u64, amount: u64) {
    assert!(stake_total_amount >= amount, EInsufficientBalance);
}

// ------- Getters ------- //
public fun protocol_id<T>(self: &LendingProtocol<T>): ID {
    object::id(self)
}

