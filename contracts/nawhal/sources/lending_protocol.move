//! The Lending Protocol is a module that manages the lending business of the protocol.
//! It is responsible for:
//! - Stake assets to the protocol
//! - Withdraw assets from the protocol
//! - Configure the protocol
//! - Manage the protocol's liquidity
//!

module narval::lending_protocol;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::table::{Self, Table};
use sui::clock::Clock;

use narval::admin::AdminCap;
use narval::liquidity_layer_model::{LiquidityLayer, new_lending_protocol_type};
use narval::liquidity_layer;
use narval::account_ds::{AccountProfile, AccountRegistry, AccountProfileCap};

// ------- Errors ------- //
const EInsufficientBalance: u64 = 20001;
const ESupplyCapReached: u64 = 20002;

// ------- Constants ------- //
// const DEFAULT_SUPPLY_CAP: u64 = 1_000_000_000_000_000_000;

// ------- structs ------- //
/// Lending protocol is a protocol that allows users to deposit and withdraw assets
public struct LendingProtocol<phantom T> has key, store {
    id: UID,
    supply: u64,
    supply_cap: u64,
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
public fun deposit<T, YT>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    payload: Coin<T>, 
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let protocol_id = self.protocol_id();

    self.supply = self.supply + payload.value();

    assert!(self.supply <= self.supply_cap, ESupplyCapReached);
    
    let asset_amount = payload.value();
    let shares = liquidity_layer::deposit(liquidity_layer, protocol_id, payload.into_balance(), clock, ctx);

    let profile = registry.borrow_or_create_profile(clock, ctx);
    profile.add_staking_shares<T, YT>(protocol_id, shares, asset_amount, clock.timestamp_ms());
}

/// Withdraw assets from the protocol
public fun withdraw<T, YT>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    cap: &AccountProfileCap,
    amount: u64, // Value amount requested by user
    clock: &Clock, 
    ctx: &mut TxContext
): Balance<T> { 
    if (amount == 0) {
        return balance::zero<T>()
    };

    let protocol_id = self.protocol_id();
    let account_id = cap.account_of();
    let profile = registry.borrow_account_mut(account_id);

    // 1. Check recorded stake amount (value)
    let stake_total_amount = profile.stake_total_amount<T, YT>(protocol_id);
    check_stake_total_amount_greater_than_or_equal_to_amount(stake_total_amount, amount);

    // 2. Calculate/Determine shares to withdraw
    // WARNING: Assuming shares amount = value amount. This needs accurate calculation logic.
    let shares_amount_to_take = amount; 

    // 3. Take the corresponding shares (Balance<YT>) from the profile
    // This will abort with ENotEnough if actual shares are insufficient.
    let shares_to_withdraw_balance = profile.take_staking_shares<T, YT>(protocol_id, shares_amount_to_take); 

    // 4. Update the profile's recorded total_asset_amount (value)
    profile.sub_staking_value<T, YT>(protocol_id, amount);

    // 5. Withdraw from Liquidity Layer using the taken shares
    let withdrawn_balance_t = liquidity_layer::withdraw<T, YT>(liquidity_layer, protocol_id, shares_to_withdraw_balance, clock, ctx);
    
    // 6. Return the actual withdrawn Balance<T>
    withdrawn_balance_t
}

/// ------- Governance ------- //
/// Register a new lending protocol to LiquidityLayer
/// Returns the ID of the newly created protocol object.
public fun register_lending_protocol<T>(
    liquidity_layer: &mut LiquidityLayer, 
    admin_cap: &AdminCap, 
    supply_cap: u64, 
    ctx: &mut TxContext
): ID { // Return the ID
    let lending_protocol = new_lending_protocol<T>(supply_cap, ctx);
    let protocol_id = lending_protocol.protocol_id(); // Get ID before sharing

    liquidity_layer::register_protocol<T>(liquidity_layer, admin_cap, protocol_id, new_lending_protocol_type(), ctx);
    
    transfer::share_object(lending_protocol);
    protocol_id // Return the ID
}

// ------- new structs ------- //
/// New a new LendingProtocol
public fun new_lending_protocol<T>(supply_cap: u64, ctx: &mut TxContext): LendingProtocol<T> {
    LendingProtocol {
        id: object::new(ctx),
        supply: 0,
        supply_cap,
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

