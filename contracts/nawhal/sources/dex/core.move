

module narval::dex;

use std::u128;

use sui::balance::{Self, Balance, Supply, create_supply};
use sui::clock::{Clock};
use sui::event;


use narval::admin::AdminCap;
use narval::common::{YieldToken};
use narval::liquidity::LiquidityLayer;
use narval::protocol;
use narval::util;

/* ================= errors ================= */

#[error]
const EZeroInput: vector<u8> = b"Input balances cannot be zero.";

#[error]
const EExcessiveSlippage: vector<u8> =
    b"The resulting amount is below slippage tolerance.";

#[error]
const ENoLiquidity: vector<u8> = b"Pool has no liquidity";

#[error]
const EInvalidFeeParam: vector<u8> = b"Fee parameter is not valid.";

/* ================= events ================= */

public struct PoolCreationEvent has copy, drop {
    pool_id: ID,
}

/* ================= constants ================= */

/// The number of basis points in 100%.
const BPS_IN_100_PCT: u64 = 100 * 100;

/* ================= LP ================= */

/// Pool LP token witness.
public struct LP<phantom A, phantom B> has drop {}

/* ================= Pool ================= */

/// Pool represents an AMM Pool.
public struct Pool<phantom A, phantom B> has key {
    id: UID,

    balance_a: u64,

    balance_b: u64,

    yield_a: Balance<YieldToken<A>>,

    yield_b: Balance<YieldToken<B>>,

    lp_supply: Supply<LP<A, B>>,

    /// The liquidity provider fees expressed in basis points (1 bps is 0.01%)
    lp_fee_bps: u64,

    /// Admin fees are calculated as a percentage of liquidity provider fees.
    admin_fee_pct: u64,

    /// Admin fees are deposited into this balance. They can be colleced by
    /// this pool's PoolAdminCap bearer.
    admin_fee_balance: Balance<LP<A, B>>,
}

/// Returns ID of the pool.
public fun id<A, B>(pool: &Pool<A, B>): ID {
    object::id(pool)
}

/// Returns the balances of token A and B present in the pool and the total
/// supply of LP coins.
public fun values<A, B>(pool: &Pool<A, B>): (u64, u64, u64) {
    (
        pool.balance_a,
        pool.balance_b,
        pool.lp_supply.supply_value(),
    )
}

/// Returns the pool fee info.
public fun fees<A, B>(pool: &Pool<A, B>): (u64, u64) {
    (pool.lp_fee_bps, pool.admin_fee_pct)
}

/// Returns the value of collected admin fees stored in the pool.
public fun admin_fee_value<A, B>(pool: &Pool<A, B>): u64 {
    pool.admin_fee_balance.value()
}


/* ================= main logic ================= */

/// Creates a new Pool with provided initial balances. Returns the initial LP coins.
public fun create<A, B>(
    liquidity_layer: &mut LiquidityLayer,
    init_a: Balance<A>,
    init_b: Balance<B>,
    lp_fee_bps: u64,
    admin_fee_pct: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Balance<LP<A, B>> {
    // sanity checks
    assert!(init_a.value() > 0 && init_b.value() > 0, EZeroInput);
    assert!(lp_fee_bps < BPS_IN_100_PCT, EInvalidFeeParam);
    assert!(admin_fee_pct <= 100, EInvalidFeeParam);

    // add to registry (guarantees that there's only one pool per currency pair)
    liquidity_layer.registry_dex<A, B>();

    // create pool
    let pool_uid = object::new(ctx);
    let pool_id = object::uid_to_inner(&pool_uid);

    // mint initial lp tokens
    let balance_a = init_a.value();
    let balance_b = init_b.value();

    let lp_amt = util::mulsqrt(balance_a, balance_b);
    let mut lp_supply = create_supply(LP<A, B>{});
    let lp_balance = lp_supply.increase_supply(lp_amt);
    
    // register protocol

    liquidity_layer.register_protocol(pool_id, protocol::new_dex_protocol_type(), ctx);
    // liquidity_layer.register_protocol<B>(pool_id, ProtocolType::Dex, ctx);


    // deposit initial balances to liquidity layer
    let yield_a = liquidity_layer.deposit<A>(pool_id, init_a, clock, ctx);
    let yield_b = liquidity_layer.deposit<B>(pool_id, init_b, clock, ctx);

    let pool = Pool<A, B> {
        id: pool_uid,
        balance_a,
        balance_b,
        yield_a,
        yield_b,
        lp_supply,
        lp_fee_bps,
        admin_fee_pct,
        admin_fee_balance: balance::zero<LP<A, B>>(),
    };

    event::emit(PoolCreationEvent { pool_id: object::id(&pool) });
    transfer::share_object(pool);

    lp_balance
}

/// Deposit liquidity into pool. The deposit will use up the maximum amount of
/// the provided balances possible depending on the current pool ratio. Usually
/// this means that all of either `input_a` or `input_b` will be fully used, while
/// the other only partially. Otherwise, both input values will be fully used.
/// Returns the remaining input amounts (if any) and LP Coin of appropriate value.
/// Fails if the value of the issued LP Coin is smaller than `min_lp_out`.
public fun deposit<A, B>( 
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    mut input_a: Balance<A>,
    mut input_b: Balance<B>,
    min_lp_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Balance<A>, Balance<B>, Balance<LP<A, B>>) {
    // sanity checks
    if (input_a.value() == 0 || input_b.value() == 0) {
        assert!(min_lp_out == 0, EExcessiveSlippage);
        return (input_a, input_b, balance::zero())
    };

    // calculate the deposit amounts
    let dab: u128 = (input_a.value() as u128) * (
        pool.balance_b as u128,
    );
    let dba: u128 = (input_b.value() as u128) * (
        pool.balance_a as u128,
    );

    let deposit_a: u64;
    let deposit_b: u64;
    let lp_to_issue: u64;
    if (dab > dba) {
        deposit_b = input_b.value();
        deposit_a =
            u128::divide_and_round_up(
                dba,
                pool.balance_b as u128,
            ) as u64;
        lp_to_issue =
            util::muldiv(
                deposit_b,
                pool.lp_supply.supply_value(),
                pool.balance_b,
            );
    } else if (dab < dba) {
        deposit_a = input_a.value();
        deposit_b =
            u128::divide_and_round_up(
                dab,
                pool.balance_a as u128,
            ) as u64;
        lp_to_issue =
            util::muldiv(
                deposit_a,
                pool.lp_supply.supply_value(),
                pool.balance_a,
            );
    } else {
        deposit_a = input_a.value();
        deposit_b = input_b.value();
        if (pool.lp_supply.supply_value() == 0) {
            // in this case both pool balances are 0 and lp supply is 0
            lp_to_issue = util::mulsqrt(deposit_a, deposit_b);
        } else {
            // the ratio of input a and b matches the ratio of pool balances
            lp_to_issue =
                util::muldiv(
                    deposit_a,
                    pool.lp_supply.supply_value(),
                    pool.balance_a,
                );
        }
    };

    // deposit amounts into pool
    // pool.balance_a.join(input_a.split(deposit_a));
    // pool.balance_b.join(input_b.split(deposit_b));
    let yield_a = liquidity_layer.deposit<A>(pool.id(), input_a.split(deposit_a), clock, ctx);
    let yield_b = liquidity_layer.deposit<B>(pool.id(), input_b.split(deposit_b), clock, ctx);

    pool.yield_a.join(yield_a);
    pool.yield_b.join(yield_b);

    pool.balance_a = pool.balance_a + deposit_a;
    pool.balance_b = pool.balance_b + deposit_b;

    // mint lp coin
    assert!(lp_to_issue >= min_lp_out, EExcessiveSlippage);
    let lp = pool.lp_supply.increase_supply(lp_to_issue);

    // return
    (input_a, input_b, lp)
}

/// Burns the provided LP Coin and withdraws corresponding pool balances.
/// Fails if the withdrawn balances are smaller than `min_a_out` and `min_b_out`
/// respectively.
public fun withdraw<A, B>(
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    lp_in: Balance<LP<A, B>>,
    min_a_out: u64,
    min_b_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Balance<A>, Balance<B>) {
    // sanity checks
    if (lp_in.value() == 0) {
        lp_in.destroy_zero();
        return (balance::zero(), balance::zero())
    };

    // calculate output amounts
    let lp_in_value = lp_in.value();
    let pool_a_value = pool.balance_a;
    let pool_b_value = pool.balance_b;
    let pool_lp_value = pool.lp_supply.supply_value();

    let a_out = util::muldiv(lp_in_value, pool_a_value, pool_lp_value);
    let b_out = util::muldiv(lp_in_value, pool_b_value, pool_lp_value);

    assert!(a_out >= min_a_out, EExcessiveSlippage);
    assert!(b_out >= min_b_out, EExcessiveSlippage);

    // burn lp tokens
    pool.lp_supply.decrease_supply(lp_in);

    pool.balance_a = pool.balance_a - a_out;
    pool.balance_b = pool.balance_b - b_out;

    // TODO: Check yt shares
    let yield_a_to_withdraw = pool.yield_a.split(a_out);
    let yield_b_to_withdraw = pool.yield_b.split(b_out);

    let a_balance = liquidity_layer.withdraw<A>(pool.id(), yield_a_to_withdraw, clock, ctx);
    let b_balance = liquidity_layer.withdraw<B>(pool.id(), yield_b_to_withdraw, clock, ctx);

    // return amounts
    (
        a_balance,
        b_balance,
    )
}

/// Calclates swap result and fees based on the input amount and current pool state.
fun calc_swap_result(
    i_value: u64,
    i_pool_value: u64,
    o_pool_value: u64,
    pool_lp_value: u64,
    lp_fee_bps: u64,
    admin_fee_pct: u64,
): (u64, u64) {
    // calc out value
    let lp_fee_value = util::ceil_muldiv(i_value, lp_fee_bps, BPS_IN_100_PCT);
    let in_after_lp_fee = i_value - lp_fee_value;
    let out_value = util::muldiv(
        in_after_lp_fee,
        o_pool_value,
        i_pool_value + in_after_lp_fee,
    );

    // calc admin fee
    let admin_fee_value = util::muldiv(lp_fee_value, admin_fee_pct, 100);
    // dL = L * sqrt((A + dA) / A) - L = sqrt(L^2(A + dA) / A) - L
    let admin_fee_in_lp = (
        u128::sqrt(
            util::muldiv_u128(
                (pool_lp_value as u128) * (pool_lp_value as u128),
                ((i_pool_value + i_value) as u128),
                ((i_pool_value + i_value - admin_fee_value) as u128),
            ),
        ) as u64,
    ) -
    pool_lp_value;

    (out_value, admin_fee_in_lp)
}

/// Swaps the provided amount of A for B. Fails if the resulting amount of B
/// is smaller than `min_out`.
public fun swap_a<A, B>(
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    input: Balance<A>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Balance<B> {
    if (input.value() == 0) {
        assert!(min_out == 0, EExcessiveSlippage);
        input.destroy_zero();
        return balance::zero()
    };
    assert!(
        pool.balance_a > 0 && pool.balance_b > 0,
        ENoLiquidity,
    );

    // calculate swap result
    let i_value = input.value();
    let i_pool_value = pool.balance_a;
    let o_pool_value = pool.balance_b;
    let pool_lp_value = pool.lp_supply.supply_value();

    let (out_value, admin_fee_in_lp) = calc_swap_result(
        i_value,
        i_pool_value,
        o_pool_value,
        pool_lp_value,
        pool.lp_fee_bps,
        pool.admin_fee_pct,
    );

    assert!(out_value >= min_out, EExcessiveSlippage);

    // deposit admin fee
    pool
        .admin_fee_balance
        .join(pool.lp_supply.increase_supply(admin_fee_in_lp));

    // TODO: Check yt shares
    // deposit input
    let yield_a = liquidity_layer.deposit<A>(pool.id(), input, clock, ctx);
    pool.yield_a.join(yield_a);
    pool.balance_a = pool.balance_a + i_value;

    // return output
    let yield_b_to_withdraw = pool.yield_b.split(out_value);
    pool.balance_b = pool.balance_b - out_value;
    liquidity_layer.withdraw<B>(pool.id(), yield_b_to_withdraw, clock, ctx)
}

/// Swaps the provided amount of B for A. Fails if the resulting amount of A
/// is smaller than `min_out`.
public fun swap_b<A, B>(
    pool: &mut Pool<A, B>,
    liquidity_layer: &mut LiquidityLayer,
    input: Balance<B>,
    min_out: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Balance<A> {
    if (input.value() == 0) {
        assert!(min_out == 0, EExcessiveSlippage);
        input.destroy_zero();
        return balance::zero()
    };
    assert!(
        pool.balance_a > 0 && pool.balance_b > 0,
        ENoLiquidity,
    );

    // calculate swap result
    let i_value = input.value();
    let i_pool_value = pool.balance_b;
    let o_pool_value = pool.balance_a;
    let pool_lp_value = pool.lp_supply.supply_value();

    let (out_value, admin_fee_in_lp) = calc_swap_result(
        i_value,
        i_pool_value,
        o_pool_value,
        pool_lp_value,
        pool.lp_fee_bps,
        pool.admin_fee_pct,
    );

    assert!(out_value >= min_out, EExcessiveSlippage);

    // deposit admin fee
    pool
        .admin_fee_balance
        .join(pool.lp_supply.increase_supply(admin_fee_in_lp));

    // deposit input
    let yield_b = liquidity_layer.deposit<B>(pool.id(), input, clock, ctx);
    pool.yield_b.join(yield_b);
    pool.balance_b = pool.balance_b + i_value;

    // return output
    let yield_a_to_withdraw = pool.yield_a.split(out_value);
    pool.balance_a = pool.balance_a - out_value;
    liquidity_layer.withdraw<A>(pool.id(), yield_a_to_withdraw, clock, ctx)
}

/// Withdraw `amount` of collected admin fees by providing pool's PoolAdminCap.
/// When `amount` is set to 0, it will withdraw all available fees.
public fun admin_withdraw_fees<A, B>(
    pool: &mut Pool<A, B>,
    _: &AdminCap,
    mut amount: u64,
): Balance<LP<A, B>> {
    if (amount == 0) amount = pool.admin_fee_balance.value();
    pool.admin_fee_balance.split(amount)
}

/// Admin function. Set new fees for the pool.
public fun admin_set_fees<A, B>(
    pool: &mut Pool<A, B>,
    _: &AdminCap,
    lp_fee_bps: u64,
    admin_fee_pct: u64,
) {
    assert!(lp_fee_bps < BPS_IN_100_PCT, EInvalidFeeParam);
    assert!(admin_fee_pct <= 100, EInvalidFeeParam);

    pool.lp_fee_bps = lp_fee_bps;
    pool.admin_fee_pct = admin_fee_pct;
}
