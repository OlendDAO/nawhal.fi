//! The Lending Protocol is a module that manages the lending business of the protocol.
//! It is responsible for:
//! - Stake assets to the protocol
//! - Withdraw assets from the protocol
//! - Configure the protocol
//! - Manage the protocol's liquidity
//!

module narval::lending_protocol;


use sui::balance::{Self, Balance};
use sui::coin::{Coin};
use sui::table::{Self, Table};
use sui::clock::Clock;

use narval::admin::AdminCap;
use narval::liquidity::{Self, LiquidityLayer};
use narval::account_ds::{AccountRegistry, AccountProfileCap};
use narval::position::{Self, StakingInfo};
use narval::protocol::{Self};
use narval::common::{YieldToken};

// ------- Errors ------- //
const EInsufficientBalance: u64 = 20001;
const ESupplyCapReached: u64 = 20002;
const EStakingInfoNotFound: u64 = 20003;

// ------- Constants ------- //
// const DEFAULT_SUPPLY_CAP: u64 = 1_000_000_000_000_000_000;

// ------- structs ------- //
/// Lending protocol is a protocol that allows users to deposit and withdraw assets
public struct LendingProtocol<phantom T> has key, store {
    id: UID,
    supply: u64,
    supply_cap: u64,
    // Stores (account_id, StakingInfo<T>) pair
    stakers: Table<ID, StakingInfo<T>>,
    created_at_ms: u64,
    created_at_epoch: u64,
}

// ------- Business Logic ------- //
/// Deposit assets to the protocol
public fun deposit<T>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    payload: Coin<T>, 
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let protocol_id = self.protocol_id();

    let profile = registry.borrow_or_create_profile(clock, ctx);
    let account_id = profile.account_id();

    self.supply = self.supply + payload.value();

    assert!(self.supply <= self.supply_cap, ESupplyCapReached);

    let now = clock.timestamp_ms();
    profile.add_lending_protocol(protocol_id);
    profile.update_latest_updated_ms(now);


    let asset_amount = payload.value();
    let shares = liquidity::deposit<T>(liquidity_layer, protocol_id, payload.into_balance(), clock, ctx);

    self.add_staking_shares<T>(account_id, shares, asset_amount, now);
}

/// Withdraw assets from the protocol
public fun withdraw<T>(
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

    let account_id = cap.account_of();
    check_staking_info_exists(self, account_id);

    let protocol_id = self.protocol_id();
    
    let profile = registry.borrow_account_mut(account_id);

    let now = clock.timestamp_ms();
    // profile.add_lending_protocol(protocol_id);
    profile.update_latest_updated_ms(now);

    // 1. Check recorded stake amount (value)
    let stake_total_amount = self.staking_total_amount<T>(account_id);
    check_stake_total_amount_greater_than_or_equal_to_amount(stake_total_amount, amount);

    // 2. Calculate/Determine shares to withdraw
    // WARNING: Assuming shares amount = value amount. This needs accurate calculation logic.
    let shares_amount_to_take = amount; 

    // 3. Take the corresponding shares (Balance<YT>) from the profile
    // This will abort with ENotEnough if actual shares are insufficient.
    let shares_to_withdraw_balance = self.take_staking_shares<T>(account_id, shares_amount_to_take, now); 

    // 4. Withdraw from Liquidity Layer using the taken shares
    let withdrawn_balance_t = liquidity::withdraw<T>(liquidity_layer, protocol_id, shares_to_withdraw_balance, clock, ctx);
    
    // 5. Return the actual withdrawn Balance<T>
    withdrawn_balance_t
}

/// Withdraw shares from the protocol
public fun withdraw_shares<T>(
    self: &mut LendingProtocol<T>, 
    account_cap: &AccountProfileCap,
    amount: u64,
    clock: &Clock,
    _ctx: &mut TxContext
): Balance<YieldToken<T>> {
    self.take_staking_shares<T>(account_cap.account_of(), amount, clock.timestamp_ms())
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

    liquidity::register_protocol_by_admin_cap(liquidity_layer, admin_cap, protocol_id, protocol::new_lending_protocol_type(), ctx);
    
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

public fun check_staking_info_exists<T>(self: &LendingProtocol<T>, account_id: ID) {
    assert!(self.stakers.contains(account_id), EStakingInfoNotFound);
}

// ------- Getters ------- //
public fun protocol_id<T>(self: &LendingProtocol<T>): ID {
    object::id(self)
}

/// Get the staking total amount of the protocol id
/// Returns 0 if the protocol id does not exist
public fun staking_total_amount<T>(self: &LendingProtocol<T>, account_id: ID): u64 {
    if (self.stakers.contains(account_id)) {
        let stake_info = self.stakers.borrow<ID, StakingInfo<T>>(account_id);
        stake_info.total_asset_amount()
    } else {
        0
    }
}

/// Borrow the staking info
public fun borrow_staking_info<T>(self: &LendingProtocol<T>, account_id: ID): &StakingInfo<T> {
    self.stakers.borrow<ID, StakingInfo<T>>(account_id)
}

/// Borrow mut the staking info
public fun borrow_staking_info_mut<T>(self: &mut LendingProtocol<T>, account_id: ID): &mut StakingInfo<T> {
    self.stakers.borrow_mut<ID, StakingInfo<T>>(account_id)
}

// ------- Setters ------- //
/// Add the staking infos to the account profile, including shares
public(package) fun add_staking_shares<T>(
    self: &mut LendingProtocol<T>, 
    account_id: ID, 
    shares: Balance<YieldToken<T>>, 
    total_asset_amount: u64, 
    latest_updated_ms: u64
) {
    let protocol_id = self.protocol_id();

    if (self.stakers.contains(account_id)) {
        let stakes = self.stakers.borrow_mut<ID, StakingInfo<T>>(account_id);
        stakes.add_shares(shares, latest_updated_ms);
    } else {
        self.stakers.add(account_id, position::new_staking_info<T>(protocol_id, 
        account_id, total_asset_amount, shares, latest_updated_ms));
    }

}

/// Take shares from the staking info.
/// Abort if the shares are less than the amount to take
public(package) fun take_staking_shares<T>(
    self: &mut LendingProtocol<T>, 
    account_id: ID, 
    amount: u64, 
    timestamp_ms: u64
): Balance<YieldToken<T>> {
    let stake_info = self.borrow_staking_info_mut<T>(account_id);
    
    stake_info.take_shares(amount, timestamp_ms)
}


/// Remove staking info
/// Abort if the staking info does not exist
public(package) fun remove_staking_info<T>(self: &mut LendingProtocol<T>, account_id: ID): StakingInfo<T> {
    self.stakers.remove(account_id)
}
