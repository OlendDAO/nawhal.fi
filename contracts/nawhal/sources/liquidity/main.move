
module narval::liquidity_layer_main;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::clock::Clock;

use narval::admin::AdminCap;
use narval::liquidity::{Self, LiquidityLayer};
use narval::protocol;


/* ================= constants ================= */

// const BPS_IN_100_PCT: u64 = 10000;

// /* ================= errors ================= */
// const EInvalidWeights: u64 = 0;

/* ================= Logic functions ================= */
/// Entry fun for depoist
public entry fun deposit_api<T, YT>(self: &mut LiquidityLayer, protocol_id: ID, payload: Coin<T>, clock: &Clock, ctx: &mut TxContext) {
    let shares = liquidity::deposit<T, YT>(self, protocol_id, payload.into_balance(), clock, ctx);
    
    transfer::public_transfer(coin::from_balance<YT>(shares, ctx), ctx.sender());
}

/// Entry fun for withdraw
public entry fun withdraw_api<T, YT>(self: &mut LiquidityLayer, protocol_id: ID, shares: Coin<YT>, clock: &Clock, ctx: &mut TxContext) {
    let withdrawn_balance_t = liquidity::withdraw<T, YT>(self, protocol_id, shares.into_balance(), clock, ctx);
    
    transfer::public_transfer(coin::from_balance<T>(withdrawn_balance_t, ctx), ctx.sender());
}

/// Entry fun for register protocol
public entry fun register_protocol_api<T, YT>(self: &mut LiquidityLayer, admin_cap: &AdminCap, protocol_id: ID, protocol_type: u8, ctx: &mut TxContext) {
    let protocol_type = protocol::protocol_type_from_u8(protocol_type);

    liquidity::register_protocol<T, YT>(self, admin_cap, protocol_id, protocol_type, ctx);
}

/* ================= Governance functions ================= */

/// Entry fun for register vault
entry fun register_vault_api<T, YT>(self: &mut LiquidityLayer, admin_cap: &AdminCap, lp_treasury: TreasuryCap<YT>, ctx: &mut TxContext) {
    let vault_cap = liquidity::register_vault_by_admin_cap<T, YT>(self, admin_cap, lp_treasury, ctx);
    
    transfer::public_transfer(vault_cap, ctx.sender());
}

/// Remove a protocol from LiquidityLayer
entry fun unregister_protocol_api(
    liquidity_layer: &mut LiquidityLayer, 
    admin_cap: &AdminCap,
    protocol_id: ID, 
    ctx: &mut TxContext
) {
    liquidity::unregister_protocol(liquidity_layer, admin_cap, protocol_id, ctx);
}

