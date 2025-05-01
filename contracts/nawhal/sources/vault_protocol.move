

module narval::vault_protocol;

use std::type_name::TypeName;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::clock::Clock;
use sui::table::{Self, Table};

use narval::account_ds::{AccountProfileCap, AccountRegistry};
use narval::liquidity_layer_model::{LiquidityLayer};
use narval::liquidity_layer;
use narval::vault_protocol_model::{Position, Tick};
use narval::oracle::PriceObject;


// ------- Errors ------- //
const EInsufficientBalance: u64 = 30001;
const ESupplyCapReached: u64 = 20002;

// ----- Structs ----- //
/// Vault protocol is a protocol that allows users to borrow assets(Debt) from the protocol with collateral
public struct VaultProtocol<phantom CT, phantom YT, phantom DT> has key, store {
    id: UID,
    supply: u64,
    supply_cap: u64,
    /// The shares after staked 
    shares: Balance<YT>,
    // Stores the (account id, posistion)
    positions: Table<ID, Position<CT, DT>>,

    // Ticks for liquidation, the tick should be store the ratio (debt/collateral value) TODO:
    ticks: Table<ID, Tick>,

    status: Status,
    created_at_ms: u64,
    created_at_epoch: u64,
}

public enum Status has copy, drop, store {
    Active,
    Paused,
    WithdrawalAndPayBack,
    Closed,
}

// ------- Logic ------- //
// /// Deposit assets to the protocol
// /// TODO: Add Oracle support
// public fun deposit_collateral<T, YT, DT>(
//     self: &mut VaultProtocol<T, YT, DT>, 
//     liquidity_layer: &mut LiquidityLayer, 
//     registry: &mut AccountRegistry, 
//     payload: Coin<T>, 
//     price_object: &PriceObject,     // Replace with Pyth oracle
//     clock: &Clock, 
//     ctx: &mut TxContext
// ) {
//     let protocol_id = self.protocol_id();

//     let profile = registry.borrow_or_create_profile(clock, ctx);
//     let account_id = profile.account_id();

//     self.supply = self.supply + payload.value();

//     assert!(self.supply <= self.supply_cap, ESupplyCapReached);

//     let now = clock.timestamp_ms();
//     profile.add_lending_protocol(protocol_id);
//     profile.update_latest_updated_ms(now);
    
//     let asset_amount = payload.value();
//     let shares = liquidity_layer::deposit<T, YT>(liquidity_layer, protocol_id, payload.into_balance(), clock, ctx);

//     self.shares.join (shares);

//     // Update collateral info in position data TODO:
// }

/// Borrow a specified amount of a given asset from the vault, with the collateral shares.
public fun borrow<CT, YT, DT>(
    self: &mut VaultProtocol<CT, YT, DT>,
    liquidity_layer: &mut LiquidityLayer,
    registry: &mut AccountRegistry,
    collateral_shares: Balance<YT>,
    to_withdraw: u64,
    account_cap: &AccountProfileCap,
    ctx: &mut TxContext
): Balance<DT> {
    // Step 1: Get the collateral shares
    // let vault = liquidity_layer.borrow_vault_mut<Collateral, YTCollateral>();
    // let balance = vault.borrow<T>(amount, ctx);
    // balance
    self.shares.join(collateral_shares);
    balance::zero()
}

/// Take shares from the LiquidityLayer

// ------- Getters ------- //
public fun protocol_id<CT, YT, DT>(self: &VaultProtocol<CT, YT, DT>): ID {
    object::id(self)
}

