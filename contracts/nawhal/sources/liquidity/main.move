
module narval::liquidity_main;

use sui::coin::{Self, Coin};
use sui::clock::Clock;

use narval::admin::AdminCap;
use narval::common::{YieldToken};
use narval::liquidity::{Self, LiquidityLayer};
use narval::protocol;


/* ================= constants ================= */



/* ================= Logic functions ================= */
/// Entry fun for depoist
public entry fun deposit_api<T>(self: &mut LiquidityLayer, protocol_id: ID, payload: Coin<T>, clock: &Clock, ctx: &mut TxContext) {
    let shares = liquidity::deposit<T>(self, protocol_id, payload.into_balance(), clock, ctx);
    
    transfer::public_transfer(coin::from_balance<YieldToken<T>>(shares, ctx), ctx.sender());
}

/// Entry fun for withdraw
public entry fun withdraw_api<T>(self: &mut LiquidityLayer, protocol_id: ID, shares: Coin<YieldToken<T>>, clock: &Clock, ctx: &mut TxContext) {
    let withdrawn_balance_t = liquidity::withdraw<T>(self, protocol_id, shares.into_balance(), clock, ctx);
    
    transfer::public_transfer(coin::from_balance<T>(withdrawn_balance_t, ctx), ctx.sender());
}

/// Entry fun for register protocol
public entry fun register_protocol_api(self: &mut LiquidityLayer, admin_cap: &AdminCap, protocol_id: ID, protocol_type: u8, ctx: &mut TxContext) {
    let protocol_type = protocol::protocol_type_from_u8(protocol_type);

    liquidity::register_protocol_by_admin_cap(self, admin_cap, protocol_id, protocol_type, ctx);
}

/* ================= Governance functions ================= */

/// Entry fun for register vault
entry fun register_vault_api<T>(self: &mut LiquidityLayer, admin_cap: &AdminCap, ctx: &mut TxContext) {
    let vault_cap = liquidity::register_vault_by_admin_cap<T>(self, admin_cap, ctx);
    
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

