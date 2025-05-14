module narval::lending_main;

use sui::coin::{Self, Coin};
use sui::clock::{Clock};

use narval::account_ds::{AccountRegistry, AccountProfileCap};
use narval::admin::AdminCap;
use narval::lending_protocol::{Self, LendingProtocol};
use narval::liquidity::{LiquidityLayer};

/// Entry fun for register lending protocol
entry fun register_lending_protocol_api<T>(
    liquidity_layer: &mut LiquidityLayer, 
    admin_cap: &AdminCap, 
    supply_cap: u64, 
    ctx: &mut TxContext
) { 
    lending_protocol::register_lending_protocol<T>(liquidity_layer, admin_cap, supply_cap, ctx);
}

/// Entry fun for deposit
entry fun deposit_api<T>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    payload: Coin<T>, 
    clock: &Clock, 
    ctx: &mut TxContext
) {
    lending_protocol::deposit<T>(self, liquidity_layer, registry, payload, clock, ctx);
}

/// Entry fun for withdraw
entry fun withdraw_api<T>(
    self: &mut LendingProtocol<T>, 
    liquidity_layer: &mut LiquidityLayer, 
    registry: &mut AccountRegistry, 
    cap: &AccountProfileCap,
    amount: u64, // Value amount requested by user
    clock: &Clock, 
    ctx: &mut TxContext
) {
    let withdrawn_balance_t = lending_protocol::withdraw<T>(self, liquidity_layer, registry, cap, amount, clock, ctx);
    
    transfer::public_transfer(coin::from_balance<T>(withdrawn_balance_t, ctx), ctx.sender());
}