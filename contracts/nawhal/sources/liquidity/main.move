
module narval::liquidity_layer_main;

use std::type_name;
use sui::coin::{TreasuryCap};

use narval::access::{VaultCap};
use narval::admin::AdminCap;
use narval::layer::{Self, LiquidityLayer};
use narval::layer_event;
use narval::vault;

/* ================= constants ================= */

// const BPS_IN_100_PCT: u64 = 10000;

// /* ================= errors ================= */
// const EInvalidWeights: u64 = 0;

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
fun register_asset_vault<T, YT>(
    self: &mut LiquidityLayer, 
    lp_treasury: TreasuryCap<YT>, 
    ctx: &mut TxContext
): VaultCap<T, YT> {
    let pt = type_name::get<T>();
    let yt = type_name::get<YT>();

    layer::check_liquidity_layer_is_active(self);
    layer::check_asset_type_not_exists(self, pt, yt);

    let (vault, vault_cap) = vault::new<T, YT>(lp_treasury, ctx);
            
    let vault_id = vault.id();

    self.add_vault_asset_type(pt, yt, vault_id);
    self.add_vault(vault_id, vault);  

    // Emit vault registered event
    layer_event::emit_vault_registered_event(self.layer_id(), vault_id, pt.into_string(), ctx.epoch_timestamp_ms(), ctx.epoch());

    vault_cap
}


/// Register a new asset vault to the LiquidityLayer by AdminCap
public fun register_vault_by_admin_cap<T, YT>(
    self: &mut LiquidityLayer, 
    _admin_cap: &AdminCap, 
    lp_treasury: TreasuryCap<YT>, 
    ctx: &mut TxContext
): VaultCap<T, YT> {
    register_asset_vault<T, YT>(self, lp_treasury, ctx)
}

/// Entry fun for register vault
public entry fun register_vault_api<T, YT>(self: &mut LiquidityLayer, admin_cap: &AdminCap, lp_treasury: TreasuryCap<YT>, ctx: &mut TxContext) {
    let vault_cap = register_vault_by_admin_cap<T, YT>(self, admin_cap, lp_treasury, ctx);
    
    transfer::public_transfer(vault_cap, ctx.sender());
}
