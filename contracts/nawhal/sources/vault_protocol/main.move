module narval::market_main;

use sui::coin::{Self, Coin};
use sui::clock::Clock;

use narval::account_ds::AccountRegistry;
use narval::liquidity::LiquidityLayer;
use narval::market::{Self, Market};

/// Create a new market.
public entry fun create_market<T, ST: drop>(
    borrowable_cap: u64,
    ctx: &mut TxContext,
) {
    market::create_pool<T, ST>(borrowable_cap, ctx)
}

/// Deposit collateral into the market.
public entry fun deposit_collateral<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    account_registry: &mut AccountRegistry,
    payment: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    market::deposit_collateral<T, ST>(self, liquidity_layer, 
        account_registry, payment.into_balance(), clock, ctx
    )
}

/// Withdraw collateral from the market.
public entry fun withdraw_collateral<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    account_registry: &mut AccountRegistry,
    amount: u64,
    ctx: &mut TxContext,
) {
    let withdrawn_balance = market::withdraw_collateral<T, ST>(self, liquidity_layer, 
        account_registry, amount, ctx
    );

    transfer::public_transfer(coin::from_balance(withdrawn_balance, ctx), ctx.sender());
}

// /// Borrow assets from the market.
// public fun borrow<T, ST>(
//     self: &mut Market<T, ST>,
//     liquidity_layer: &mut LiquidityLayer,
//     _account_registry: &mut AccountRegistry,
//     facil_cap: &LendFacilCap,
//     amount: u64,
//     _clock: &Clock,
//     _ctx: &mut TxContext,
// ) {
//     let (market::borrow<T, ST>(self, liquidity_layer, _account_registry, facil_cap, amount, _clock, _ctx)
// }

    