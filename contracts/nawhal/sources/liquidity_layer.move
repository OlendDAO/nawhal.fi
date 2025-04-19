//! The Liquidity Layer is a "base" layer, also is a module that manage the global liquidity of the protocol.
//! This "base" layer can be responsible for:
//! - Holding the underlying assets
//! - Deposit  assets to the LiquidityVaults
//! - Withdraw assets from the LiquidityVaults
//! - Register assets to the protocol
//! - Providing oracle prices
//! - Implementing some defensive functions (such as rate limiting, status management, etc.)
//! - Transfer the assets to the protocol layer
//! 
//! It calls for simpler, more readable, and reliable code - at least at the base layer - to ensure safety.

module narval::liquidity_layer;

// use std::ascii::String;
use std::type_name;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::TreasuryCap;

use narval::admin::{Self, AdminCap};
use narval::liquidity_layer_model::{Self, LiquidityLayer, ProtocolType};
use narval::liquidity_event;
use narval::liquidity_vault::{VaultCap};

// ------- errors ------- //
// const EProtocolInsufficientBalance: u64 = 10008;


// ------- functions ------- //
/// Initialize the LiquidityLayer
/// Create a `LiquidityLayer` and share it,
/// Create a `AdminCap` and transfer it to the sender(publisher)
fun init(ctx: &mut TxContext) {
    let liquidity_layer = liquidity_layer_model::new_liquidity_layer(ctx);
    let layer_id = liquidity_layer.layer_id();

    liquidity_layer.share_object();

    admin::create_admin_cap_and_transfer(ctx);

    // Emit liquidity layer created event
    liquidity_event::emit_liquidity_layer_created_event(layer_id, ctx.epoch_timestamp_ms(), ctx.epoch());
}

// ------- Logic functions ------- //
/// The Protocol deposits the assets to the LiquidityLayer.
/// And update the protocol amount with protocol_id.
public fun deposit<T, YT>(self: &mut LiquidityLayer, protocol_id: ID, payload: Balance<T>, clock: &Clock, ctx: &mut TxContext): Balance<YT> {
    if (payload.value() == 0) {
        payload.destroy_zero();
        balance::zero()
    } else {
        let asset_type = type_name::get<T>();
        self.check_protocol_exists(&protocol_id);
        self.check_protocol_asset_type_match(&protocol_id, &asset_type);

        let deposit_value = payload.value();
        self.increment_protocol_amount(protocol_id, deposit_value);

        let shares = self.add_asset_to_vault_balance<T, YT>(payload, clock);

        // Emit protocol deposited event
        liquidity_event::emit_protocol_deposited_event(self.layer_id(), protocol_id, deposit_value, clock.timestamp_ms(), ctx.epoch());

        shares
    }  
}

/// The Protocol withdraws the assets from the LiquidityLayer.
/// And update the protocol amount with protocol_id.
/// Ignore the amount if the protocol amount is less than the amount.
public fun withdraw<T, YT>(self: &mut LiquidityLayer, protocol_id: ID, shares: Balance<YT>, clock: &Clock, ctx: &mut TxContext): Balance<T> {
    if (shares.value() == 0) {
        shares.destroy_zero();
        return balance::zero<T>()
    };

    let asset_type = type_name::get<T>();
    liquidity_layer_model::check_protocol_exists(self, &protocol_id);
    liquidity_layer_model::check_protocol_asset_type_match(self, &protocol_id, &asset_type);

    // Initial check based on shares value might be inaccurate, 
    // but necessary if layer withdraw requires shares
    // A better check might involve simulating the withdrawal value first.
    // assert!(self.get_protocol_amount(&protocol_id) >= shares.value(), EProtocolInsufficientBalance);
    
    let current_epoch = ctx.epoch();
    // let shares_value_for_event = shares.value(); // Keep for event

    // Withdraw from vault using shares
    let withdrawn_balance_t = self.withdraw_from_liquidity_vault<T, YT>( shares, clock);
    let withdrawn_value = withdrawn_balance_t.value(); // Get the actual withdrawn asset value

    // Decrement the protocol amount using the ACTUAL withdrawn asset value
    self.decrement_protocol_amount(protocol_id, withdrawn_value);

    // Emit protocol withdrawn event (using shares value as amount? Or withdrawn_value?)
    // Using withdrawn_value seems more consistent with the state update.
    liquidity_event::emit_protocol_withdrawn_event(self.layer_id(), protocol_id, withdrawn_value, clock.timestamp_ms(), current_epoch);

    withdrawn_balance_t
}

// /// Borrowing of funds from the treasury and the need to pay the corresponding interest on the borrowed funds 


// ------- Governance functions ------- //
/// Register a new asset vault to the LiquidityLayer.
/// 
/// # Arguments
/// * `liquidity_layer`: The LiquidityLayer to register the asset vault to.
/// * `payload`: The payload to register the asset vault to.
/// * `ctx`: The transaction context.
/// 
/// # Ignores
/// * If the asset type is already registered.
public(package) fun register_asset_vault<T, YT>(self: &mut LiquidityLayer, lp_treasury: TreasuryCap<YT>, ctx: &mut TxContext): VaultCap<YT> {
    let asset_type = type_name::get<T>();
    liquidity_layer_model::check_liquidity_layer_is_active(self);
    liquidity_layer_model::check_asset_type_not_exists(self, &asset_type);

    let (liquidity_vault, vault_cap) = liquidity_layer_model::new_liquidity_vault<T, YT>(lp_treasury, ctx);
            
    let liquidity_vault_id = liquidity_vault.id();

    self.add_asset_type(asset_type, liquidity_vault_id);
    self.add_liquidity_vault(liquidity_vault_id, liquidity_vault);  

    // Emit vault registered event
    liquidity_event::emit_vault_registered_event(self.layer_id(), liquidity_vault_id, asset_type.into_string(), ctx.epoch_timestamp_ms(), ctx.epoch());

    vault_cap
}

/// Register a new asset vault to the LiquidityLayer by AdminCap
public fun register_vault_by_admin_cap<T, YT>(
    self: &mut LiquidityLayer, 
    _admin_cap: &AdminCap, 
    lp_treasury: TreasuryCap<YT>, 
    ctx: &mut TxContext
): VaultCap<YT> {
    register_asset_vault<T, YT>(self, lp_treasury, ctx)
}

/// Register a new protocol to the LiquidityLayer
/// Pause the liquidity layer
public fun register_protocol<T>(self: &mut LiquidityLayer, _admin_cap: &AdminCap, protocol_id: ID, protocol_type: ProtocolType, ctx: &mut TxContext) {
    let asset_type = type_name::get<T>();

    liquidity_layer_model::check_liquidity_layer_is_active(self);
    liquidity_layer_model::check_asset_type_exists(self, &asset_type);
    liquidity_layer_model::check_protocol_not_exists(self, &protocol_id);
    
    self.add_protocol(
        protocol_id, 
        liquidity_layer_model::new_protocol_config(protocol_id, asset_type, 0, protocol_type)
    );

    // Emit protocol registered event
    liquidity_event::emit_protocol_registered_event(self.layer_id(), protocol_id, asset_type.into_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
}

/// Pause the liquidity layer
public fun pause_liquidity_layer(self: &mut LiquidityLayer, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let old_status = self.layer_status();
    let new_status = liquidity_layer_model::new_paused_liquidity_status();
    self.set_status(new_status);

    // Emit liquidity layer paused event
    liquidity_event::emit_liquidity_layer_paused_event(self.layer_id(), old_status.layer_status_to_string(), new_status.layer_status_to_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
}

/// Resume the liquidity layer
public fun resume_liquidity_layer(self: &mut LiquidityLayer, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let old_status = self.layer_status();
    let new_status = liquidity_layer_model::new_active_liquidity_status();
    self.set_status(new_status);

    // Emit liquidity layer resumed event
    liquidity_event::emit_liquidity_layer_resumed_event(self.layer_id(), old_status.layer_status_to_string(), new_status.layer_status_to_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
}

// ------- Testing functions ------- //
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

