module narval::dex_main;

use sui::clock::Clock;
use sui::coin::{Self, Coin};

use narval::liquidity::LiquidityLayer;
use narval::dex::{Self, LP, Pool};

/// Entry fun for create pool
public entry fun create<A, B>(
    liquidity_layer: &mut LiquidityLayer,
    init_a: Coin<A>,
    init_b: Coin<B>,
    lp_fee_bps: u64,
    admin_fee_pct: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let input_a = init_a.into_balance();
    let input_b = init_b.into_balance();

    let lp_balance = dex::create(liquidity_layer, input_a, input_b, lp_fee_bps, admin_fee_pct, clock, ctx);

    transfer::public_transfer(coin::from_balance<LP<A, B>>(lp_balance, ctx), ctx.sender());
}

/// Entry fun for deposit
public entry fun deposit<A, B>( 
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    payment_a: Coin<A>,
    payment_b: Coin<B>,
    min_lp_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let input_a = payment_a.into_balance();
    let input_b = payment_b.into_balance();

    let (remaining_a, remaining_b, lp_coin) = dex::deposit(pool, liquidity_layer, input_a, input_b, min_lp_out, clock, ctx);

    transfer::public_transfer(coin::from_balance<A>(remaining_a, ctx), ctx.sender());
    transfer::public_transfer(coin::from_balance<B>(remaining_b, ctx), ctx.sender());

    transfer::public_transfer(coin::from_balance<LP<A, B>>(lp_coin, ctx), ctx.sender());
}


/// Entry fun for withdraw
public entry fun withdraw<A, B>(
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    lp_in: Coin<LP<A, B>>,
    min_a_out: u64,
    min_b_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let lp_in = lp_in.into_balance();

    let (remaining_a, remaining_b) = dex::withdraw(pool, liquidity_layer, lp_in, min_a_out, min_b_out, clock, ctx);

    transfer::public_transfer(coin::from_balance<A>(remaining_a, ctx), ctx.sender());
    transfer::public_transfer(coin::from_balance<B>(remaining_b, ctx), ctx.sender());
}

/// Entry fun for swap A -> B
public entry fun swap_a_to_b<A, B>(
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    input: Coin<A>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let input = input.into_balance();

    let output = dex::swap_a(pool, liquidity_layer, input, min_out, clock, ctx);

    transfer::public_transfer(coin::from_balance<B>(output, ctx), ctx.sender());
}

/// Entry fun for swap B -> A
public entry fun swap_b_to_a<A, B>(
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    input: Coin<B>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let input = input.into_balance();

    let output = dex::swap_b(pool, liquidity_layer, input, min_out, clock, ctx);

    transfer::public_transfer(coin::from_balance<A>(output, ctx), ctx.sender());
}