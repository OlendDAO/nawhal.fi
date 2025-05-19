

module narval::vault;


use std::u64;

use sui::balance::{Self, Balance, Supply};
use sui::clock::Clock;
// use sui::coin::{Self, TreasuryCap};
use sui::event;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self};

use narval::access::{Self, VaultCap, VaultAccess};
use narval::common::{Self, YieldToken};
use narval::protocol::{
    Self, 
    StrategyState, 
    RebalanceInfo, 
    RebalanceAmounts, 
    WithdrawTicket, 
    StrategyWithdrawInfo, 
    StrategyRemovalTicket
};

use narval::tlb::{Self as tlb, TimeLockedBalance};
use narval::util::{muldiv, muldiv_round_up, timestamp_sec};

/* ================= constants ================= */

const MODULE_VERSION: u64 = 1;

const BPS_IN_100_PCT: u64 = 10000;

const DEFAULT_PROFIT_UNLOCK_DURATION_SEC: u64 = 100 * 60; // 100 minutes

/* ================= errors ================= */

/// BPS value can be at most 10000 (100%)
const EInvalidBPS: u64 = 0;

/// Deposit is over vault's TVL cap
const EDepositTooLarge: u64 = 1;

/// A withdraw ticket is issued
const EWithdrawTicketIssued: u64 = 2;

/// Input balance amount should be positive
const EZeroAmount: u64 = 3;

/// Strategy has already withdrawn into the ticket
const EStrategyAlreadyWithdrawn: u64 = 4;

/// All strategies need to be withdrawn from to claim the ticket
const EStrategyNotWithdrawn: u64 = 5;

/// The strategy is not registered with the vault
const EInvalidVaultAccess: u64 = 6;

// /// Target strategy weights input should add up to 100% and contain the same
// /// number of elements as the number of strategies
const EInvalidWeights: u64 = 7;

/// An invariant has been violated
const EInvariantViolation: u64 = 8;

/// Calling functions from the wrong package version
const EWrongVersion: u64 = 9;

/// Migration is not an upgrade
const ENotUpgrade: u64 = 10;

/// Vault is not active
const EVaultNotActive: u64 = 11;

/// Reserved funds are not enough
const EReservedFundsNotEnough: u64 = 12;

/// Reserved funds for a protocol are not enough
const EReservedFundsNotEnoughForProtocol: u64 = 13;

/* ================= events ================= */

public struct DepositEvent<phantom T> has copy, drop {
    amount: u64,
    lp_minted: u64,
}

public struct WithdrawEvent<phantom T> has copy, drop {
    amount: u64,
    lp_burned: u64,
}

public struct StrategyProfitEvent<phantom T> has copy, drop {
    strategy_id: ID,
    profit: u64,
    fee_amt_yt: u64,
}

public struct StrategyLossEvent<phantom T> has copy, drop {
    strategy_id: ID,
    to_withdraw: u64,
    withdrawn: u64,
}

/* ================= Vault ================= */

// TODO: migrate strategies to `LiquidityLayer`
public struct Vault<phantom T> has key, store {
    id: UID,
    /// balance that's not allocated to any strategy
    available_balance: Balance<T>,
    /// total reserved funds for borrow and collateral
    reserved_funds: u64,
    /// reserved funds for each protocol
    reserved_protocols: Table<ID, u64>,
    /// slowly distribute profits over time to avoid sandwitch attacks on rebalance
    time_locked_profit: TimeLockedBalance<T>,
    /// supply of the vault's yield-bearing token
    lp_supply: Supply<YieldToken<T>>,
    /// strategies
    strategies: VecMap<ID, StrategyState>,
    /// performance fee balance
    performance_fee_balance: Balance<YieldToken<T>>,
    /// priority order for withdrawing from strategies
    strategy_withdraw_priority_order: vector<ID>,
    /// only one withdraw ticket can be active at a time
    withdraw_ticket_issued: bool,
    /// deposits are disabled above this threshold
    tvl_cap: Option<u64>,
    /// duration of profit unlock in seconds
    profit_unlock_duration_sec: u64,
    /// performance fee in basis points (taken from all profits)
    performance_fee_bps: u64,

    status: Status,

    version: u64,
}

public enum Status has copy, drop, store {
    Active,
    Paused,
    Closed,
}

/// New an Active Status 
public fun new_active_status(): Status {
    Status::Active
}

/// New a Paused Status 
public fun new_paused_status(): Status {
    Status::Paused
}

/// New a Closed Status 
public fun new_closed_status(): Status {
    Status::Closed
}

public(package) fun create<T>(ctx: &mut TxContext): (Vault<T>, VaultCap<T>) {

    let vault = new(
        balance::zero(), 
        0, 
        table::new(ctx), 
        tlb::create(balance::zero(), 0, 0), 
        balance::create_supply(common::new_yield_token<T>()),
        vec_map::empty(), 
        vector::empty(), 
        false, 
        option::none(), 
        DEFAULT_PROFIT_UNLOCK_DURATION_SEC, 
        0, 
        MODULE_VERSION,     
        ctx
    );

    // since there can be only one `TreasuryCap<YT>` for type `YT`, there can be only
    // one `Vault<T, YT>` and `AdminCap<YT>` for type `YT` as well.
    (vault, access::new_vault_cap(ctx))
}

public fun new<T>(
    available_balance: Balance<T>,
    reserved_funds: u64,
    reserved_protocols: Table<ID, u64>,
    time_locked_profit: TimeLockedBalance<T>,
    lp_supply: Supply<YieldToken<T>>,
    strategies: VecMap<ID, StrategyState>,
    strategy_withdraw_priority_order: vector<ID>,
    withdraw_ticket_issued: bool,
    tvl_cap: Option<u64>,
    profit_unlock_duration_sec: u64,
    performance_fee_bps: u64,
    version: u64,
    ctx: &mut TxContext,
): Vault<T> {
    Vault<T> {
        id: object::new(ctx),
        available_balance,
        reserved_funds,
        reserved_protocols,
        time_locked_profit,
        lp_supply,
        strategies,
        strategy_withdraw_priority_order,
        performance_fee_balance: balance::zero(),
        performance_fee_bps,
        profit_unlock_duration_sec,
        tvl_cap,
        version,
        status: new_active_status(),
        withdraw_ticket_issued,
    }
}

/* ================= read ================= */
/// Get the `id` of the vault
public fun id<T>(self: &Vault<T>): ID {
    object::id(self)
}

/// Assert the version of the vault
public fun check_latest_version<T>(vault: &Vault<T>) {
    assert!(vault.version == MODULE_VERSION, EWrongVersion);
}

/// Check the status of the vault
public fun check_active_status<T>(vault: &Vault<T>) {
    assert!(vault.status == Status::Active, EVaultNotActive);
}

/// Check if the reserved funds are enough
public fun check_reserved_funds_enough<T>(vault: &Vault<T>, amount: u64) {
    assert!(vault.reserved_funds >= amount, EReservedFundsNotEnough);
}

/// Check if the reserved funds for a protocol are enough
public fun check_reserved_funds_enough_for_protocol<T>(vault: &Vault<T>, protocol_id: ID, amount: u64) {
    assert!(vault.reserved_funds_for_protocol(protocol_id) >= amount, EReservedFundsNotEnoughForProtocol);
}

public fun available_balance<T>(vault: &Vault<T>): u64 {
    vault.available_balance.value()
}

public fun tvl_cap<T>(vault: &Vault<T>): Option<u64> {
    vault.tvl_cap
}

/// Get time locked profit value
public fun time_locked_profit<T>(vault: &Vault<T>): &TimeLockedBalance<T> {
    &vault.time_locked_profit
}

/// Get the total available balance of the vault
public fun total_available_balance<T>(vault: &Vault<T>, clock: &Clock): u64 {
    let mut total: u64 = 0;

    total = total + vault.available_balance.value();
    total = total + vault.time_locked_profit.max_withdrawable(clock);

    let mut i = 0;
    let n = vault.strategies.size();
    while (i < n) {
        let (_, strategy_state) = vault.strategies.get_entry_by_idx(i);
        total = total + strategy_state.borrowed();
        i = i + 1;
    };

    total
}

public fun total_yt_supply<T>(vault: &Vault<T>): u64 {
    vault.lp_supply.supply_value()
}

/// Get free balance value
public fun available_balance_value<T>(vault: &Vault<T>): u64 {
    vault.available_balance.value()
}

/// Get reserved funds value
public fun reserved_funds<T>(vault: &Vault<T>): u64 {
    vault.reserved_funds
}

/// Get reserved funds for a protocol
public fun reserved_funds_for_protocol<T>(vault: &Vault<T>, protocol_id: ID): u64 {
    *vault.reserved_protocols.borrow(protocol_id)
}

/// Get available balance value
/// Get performance fee balance value
public fun performance_fee_balance_value<T>(vault: &Vault<T>): u64 {
    vault.performance_fee_balance.value()
}

/// Get `strategy_withdraw_priority_order`
public fun strategy_withdraw_priority_order<T>(vault: &Vault<T>): vector<ID> {
    vault.strategy_withdraw_priority_order
}

/// Get size of `strategies`
public fun strategies_size<T>(vault: &Vault<T>): u64 {
    vault.strategies.size()
}

/// Get strategy by id
public fun get_strategy_by_id<T>(vault: &Vault<T>, strategy_id: &ID): &StrategyState {
    vault.strategies.get(strategy_id)
}

/// Migrate to a new version
entry fun migrate<T>(_cap: &VaultCap<T>, vault: &mut Vault<T>) {
    assert!(vault.version < MODULE_VERSION, ENotUpgrade);
    vault.version = MODULE_VERSION;
}

/// Borrow mut `lp_supply`
public fun borrow_mut_lp_supply<T>(vault: &mut Vault<T>): &mut Supply<YieldToken<T>> {
    &mut vault.lp_supply
}

/// Borrow mut `StrategyState`
public fun get_mut_strategy_state<T>(vault: &mut Vault<T>, strategy_id: &ID): &mut StrategyState {
    vault.strategies.get_mut(strategy_id)
}

/// Top up to `time_locked_profit`
public fun top_up_time_locked_profit<T>(vault: &mut Vault<T>, balance: Balance<T>, clock: &Clock) {
    vault.time_locked_profit.top_up(balance, clock);
}

/// Join `balance` to `available_balance`
public fun join_available_balance<T>(vault: &mut Vault<T>, balance: Balance<T>) {
    vault.available_balance.join(balance);
}

/// Insert `StrategyState` into `strategies`
public fun insert_strategy<T>(vault: &mut Vault<T>, strategy_id: ID, strategy_state: StrategyState) {
    vault.strategies.insert(strategy_id, strategy_state);
}

/// Add `strategy_id` to `strategy_withdraw_priority_order`
public fun add_strategy_to_withdraw_priority_order<T>(vault: &mut Vault<T>, strategy_id: ID) {
    vault.strategy_withdraw_priority_order.push_back(strategy_id);
}

/// Remove `strategy_id` from `strategy_withdraw_priority_order`
public(package) fun remove_strategy_from_withdraw_priority_order<T>(vault: &mut Vault<T>, strategy_id: &ID) {
    let (has, idx) = vault.strategy_withdraw_priority_order.index_of(strategy_id);
    assert!(has, EInvariantViolation);
    vault.strategy_withdraw_priority_order.remove(idx);
}

/// Default profit unlock duration in seconds
public fun default_profit_unlock_duration_sec(): u64 {
    DEFAULT_PROFIT_UNLOCK_DURATION_SEC
}

/// Module version
public fun module_version(): u64 {
    MODULE_VERSION
}

/* ================= admin funtions ================= */

/* ================= Admin ================= */
entry fun set_strategy_max_borrow<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    strategy_id: ID,
    max_borrow: Option<u64>,
) {
    vault.check_latest_version();

    let state = vault.get_mut_strategy_state(&strategy_id);
    state.set_max_borrow(max_borrow);
}

entry fun set_strategy_target_alloc_weights_bps<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    ids: vector<ID>,
    weights_bps: vector<u64>,
) {
    vault.check_latest_version();

    let mut ids_seen = vec_set::empty<ID>();
    let mut total_bps = 0;

    let mut i = 0;
    let n = vault.strategies_size();

    assert!(n == ids.length(), EInvalidWeights);
    assert!(n == weights_bps.length(), EInvalidWeights);

    while (i < n) {
        let id = ids[i];
        let weight = weights_bps[i];
        ids_seen.insert(id); // checks for duplicate ids
        total_bps = total_bps + weight;

        let state = vault.get_mut_strategy_state(&id);
        state.set_target_alloc_weight_bps(weight);

        i = i + 1;
    };

    assert!(total_bps == BPS_IN_100_PCT, EInvalidWeights);
}

public fun remove_strategy<T>(
    cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    ticket: StrategyRemovalTicket<T>,
    ids_for_weights: vector<ID>,
    weights_bps: vector<u64>,
    clock: &Clock,
) {
    vault.check_latest_version();

    // extract the ticket and destroy the access
    let (access, mut returned_balance) = ticket.extract();

    let id = access.vault_access_id();

    access.destroy_vault_access();

    // remove from strategies and return balance
    let (_, state) = vault.strategies.remove(&id);

    let (borrowed, _, _) = state.extract_strategy_state();

    let returned_value = returned_balance.value();
    if (returned_value > borrowed) {
        let profit = returned_balance.split(
            returned_value - borrowed,
        );

        vault.top_up_time_locked_profit(profit, clock);
    };

    vault.join_available_balance(returned_balance);

    // remove from withdraw priority order
    // let (has, idx) = vault.strategy_withdraw_priority_order_index_of(&id);

    // assert!(has, EInvariantViolation);

    vault.remove_strategy_from_withdraw_priority_order(&id);

    // set new weights
    set_strategy_target_alloc_weights_bps(cap, vault, ids_for_weights, weights_bps);
}

public fun add_strategy<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    ctx: &mut TxContext,
): VaultAccess {
    vault.check_latest_version();

    let access = access::new_vault_access(ctx);
    let strategy_id = access.vault_access_id();

    let target_alloc_weight_bps = if (vault.strategies_size() == 0) {
        BPS_IN_100_PCT
    } else {
        0
    };

    vault.insert_strategy(
        strategy_id,
        protocol::new_strategy_state(0, target_alloc_weight_bps, option::none()),
    );

    vault.add_strategy_to_withdraw_priority_order(strategy_id);

    access
}

/// Set the status of the vault
public fun set_status<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    status: Status,
) {
    vault.check_latest_version();
    vault.status = status;
}

entry fun pause<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
) {
    vault.check_latest_version();
    vault.status = new_paused_status();
}

entry fun resume<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
) {
    vault.check_latest_version();
    vault.status = new_active_status();
}   

entry fun set_tvl_cap<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    tvl_cap: Option<u64>,
) {
    vault.check_latest_version();
    vault.tvl_cap = tvl_cap;
}

entry fun set_profit_unlock_duration_sec<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    profit_unlock_duration_sec: u64,
) {
    vault.check_latest_version();
    vault.profit_unlock_duration_sec = profit_unlock_duration_sec;
}

entry fun set_performance_fee_bps<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    performance_fee_bps: u64,
) {
    vault.check_latest_version();
    assert!(performance_fee_bps <= BPS_IN_100_PCT, EInvalidBPS);
    vault.performance_fee_bps = performance_fee_bps;
}

public fun withdraw_performance_fee<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    amount: u64,
): Balance<YieldToken<T>> {
    vault.check_latest_version();
    vault.performance_fee_balance.split(amount)
}

entry fun pull_unlocked_profits_to_available_balance<T>(
    _cap: &VaultCap<T>,
    vault: &mut Vault<T>,
    clock: &Clock,
) {
    vault.check_latest_version();

    let balance = vault.time_locked_profit.withdraw_all(clock);

    vault.join_available_balance(
        balance,
    );
}

/* ================= protocol/user operations ================= */

public(package) fun deposit<T>(
    vault: &mut Vault<T>,
    payment: Balance<T>,
    clock: &Clock,
): Balance<YieldToken<T>> {
    check_latest_version(vault);
    assert!(vault.withdraw_ticket_issued == false, EWithdrawTicketIssued);

    if (payment.value() == 0) {
        payment.destroy_zero();
        return balance::zero()
    };

    // edge case -- appropriate any existing balances into performance
    // fees in case lp supply is 0.
    // this guarantees that lp supply is non-zero if total_available_balance
    // is positive.
    if (vault.lp_supply.supply_value() == 0) {
        // take any existing balances from time_locked_profit
        vault.time_locked_profit.change_unlock_per_second(
            0,
            clock,
        );

        let skimmed = vault.time_locked_profit.skim_extraneous_balance();
        let withdrawn = vault.time_locked_profit.withdraw_all(clock);
        vault.join_available_balance(skimmed);
        vault.join_available_balance(withdrawn);

        // appropriate everything to performance fees
        let total_available_balance = vault.total_available_balance(clock);

        vault.performance_fee_balance.join(
            vault.lp_supply.increase_supply(total_available_balance),
        );
    };

    let total_available_balance = vault.total_available_balance(clock);
    if (vault.tvl_cap.is_some()) {
        let tvl_cap = *vault.tvl_cap.borrow();
        assert!(total_available_balance + payment.value() <= tvl_cap, EDepositTooLarge);
    };

    let available_amount = vault.available_balance.value() - vault.reserved_funds;
    let lp_amount = if (available_amount == 0) {
        payment.value()
    } else {
        muldiv(
            vault.lp_supply.supply_value(),
            payment.value(),
            available_amount,
        )
    };

    event::emit(DepositEvent<T> {
        amount: payment.value(),
        lp_minted: lp_amount,
    });

    vault.available_balance.join(payment);
    vault.lp_supply.increase_supply(lp_amount)
}

/// Deposit directly to the vault without minting YieldToken
/// The deposit assert is direct join to available balance and add to reserved funds
/// For collateral and borrow, and DEX LP supply
public(package) fun deposit_direct<T>(
    vault: &mut Vault<T>,
    protocol_id: ID,
    payment: Balance<T>,
) {
    check_latest_version(vault);
    check_active_status(vault);

    vault.reserved_funds = vault.reserved_funds + payment.value();
    if (vault.reserved_protocols.contains(protocol_id)) {
        *vault.reserved_protocols.borrow_mut(protocol_id) = *vault.reserved_protocols.borrow(protocol_id) + payment.value();
    } else {
        vault.reserved_protocols.add(protocol_id, payment.value());
    };
    vault.available_balance.join(payment); 
}

fun create_withdraw_ticket<T>(vault: &Vault<T>): WithdrawTicket<T> {
    let mut strategy_infos: VecMap<ID, StrategyWithdrawInfo<T>> = vec_map::empty();
    let mut i = 0;
    let n = vault.strategy_withdraw_priority_order.length();
    while (i < n) {
        let strategy_id = *vault.strategy_withdraw_priority_order.borrow(i);
        let info = protocol::new_strategy_withdraw_info(0, balance::zero(), false);
        
        strategy_infos.insert(strategy_id, info);

        i = i + 1;
    };

    protocol::new_withdraw_ticket(0, strategy_infos, balance::zero())
}

public(package) fun withdraw_direct<T>(
    vault: &mut Vault<T>,
    protocol_id: ID,
    amount: u64,
): Balance<T> {
    check_latest_version(vault);
    check_active_status(vault);

    check_reserved_funds_enough(vault, amount);
    // Can't match the borrow case, because a protocol can borrow a asset with another assets
    // check_reserved_funds_enough_for_protocol(vault, protocol_id, amount);

    *vault.reserved_protocols.borrow_mut(protocol_id) = *vault.reserved_protocols.borrow(protocol_id) - amount;
    vault.reserved_funds = vault.reserved_funds - amount;
    vault.available_balance.split(amount)
}

public fun withdraw<T>(
    vault: &mut Vault<T>,
    payment: Balance<YieldToken<T>>,
    clock: &Clock,
): WithdrawTicket<T> {
    check_latest_version(vault);
    assert!(vault.withdraw_ticket_issued == false, EWithdrawTicketIssued);
    assert!(payment.value() > 0, EZeroAmount);
    vault.withdraw_ticket_issued = true;

    let mut ticket = create_withdraw_ticket(vault);
    ticket.join_lp_to_burn(payment);

    // join unlocked profits to free balance
    let balance = vault.time_locked_profit.withdraw_all(clock);
    vault.join_available_balance(balance);

    // calculate withdraw amount
    let total_available = total_available_balance(vault, clock) - vault.reserved_funds;
    let mut remaining_to_withdraw = muldiv(
        ticket.lp_to_burn_value(),
        total_available,
        vault.lp_supply.supply_value(),
    );

    // first withdraw everything possible from free balance
    ticket.set_to_withdraw_from_available_balance(
        u64::min(
            remaining_to_withdraw,
            vault.available_balance.value(),
        ),
    );

    remaining_to_withdraw = remaining_to_withdraw - ticket.to_withdraw_from_available_balance_value();

    if (remaining_to_withdraw == 0) {
        return ticket
    };

    // if this is not enough, start withdrawing from strategies
    // first withdraw from all the strategies that are over their target allocation
    let mut total_borrowed_after_excess_withdrawn = 0;
    let mut i = 0;
    let n = vault.strategy_withdraw_priority_order.length();

    while (i < n && remaining_to_withdraw > 0) {
        let strategy_id = *vault.strategy_withdraw_priority_order.borrow(i);
        let strategy_state = vault.strategies.get(&strategy_id);
        let strategy_withdraw_info = ticket.get_mut_strategy_info(&strategy_id);

        let over_cap = if (strategy_state.exists_max_borrow()) {
            let max_borrow = strategy_state.max_borrow();
            if (strategy_state.borrowed() > max_borrow) {
                strategy_state.borrowed() - max_borrow
            } else {
                0
            }
        } else {
            0
        };

        let to_withdraw = if (over_cap >= remaining_to_withdraw) {
            remaining_to_withdraw
        } else {
            over_cap
        };

        remaining_to_withdraw = remaining_to_withdraw - to_withdraw;

        total_borrowed_after_excess_withdrawn =
            total_borrowed_after_excess_withdrawn + strategy_state.borrowed() - to_withdraw;

        strategy_withdraw_info.set_to_withdraw(to_withdraw);

        i = i + 1;
    };

    // if that is not enough, withdraw from all strategies proportionally so that
    // the strategy borrowed amounts are kept at the same proportions as they were before
    if (remaining_to_withdraw == 0) {
        return ticket
    };
    let to_withdraw_propotionally_base = remaining_to_withdraw;

    let mut i = 0;
    let n = vector::length(&vault.strategy_withdraw_priority_order);
    while (i < n) {
        let strategy_id = vector::borrow(&vault.strategy_withdraw_priority_order, i);
        let strategy_state = vec_map::get(&vault.strategies, strategy_id);
        let strategy_withdraw_info = ticket.get_mut_strategy_info(strategy_id);

        let strategy_remaining = strategy_state.borrowed() - strategy_withdraw_info.to_withdraw();

        let to_withdraw = muldiv(
            strategy_remaining,
            to_withdraw_propotionally_base,
            total_borrowed_after_excess_withdrawn,
        );

        let current_to_withdraw = strategy_withdraw_info.to_withdraw();
        strategy_withdraw_info.set_to_withdraw(current_to_withdraw + to_withdraw);

        remaining_to_withdraw = remaining_to_withdraw - to_withdraw;

        i = i + 1;
    };

    // if that is not enough, start withdrawing all from strategies in priority order
    if (remaining_to_withdraw == 0) {
        return ticket
    };

    let mut i = 0;
    let n = vault.strategy_withdraw_priority_order.length();

    while (i < n) {
        let strategy_id = *vault.strategy_withdraw_priority_order.borrow(i);
        let strategy_state = vault.strategies.get(&strategy_id);
        let strategy_withdraw_info = ticket.get_mut_strategy_info(&strategy_id);

        let strategy_remaining = strategy_state.borrowed() - strategy_withdraw_info.to_withdraw();
        let to_withdraw = u64::min(strategy_remaining, remaining_to_withdraw);

        let current_to_withdraw = strategy_withdraw_info.to_withdraw();
        strategy_withdraw_info.set_to_withdraw(current_to_withdraw + to_withdraw);

        remaining_to_withdraw = remaining_to_withdraw - to_withdraw;

        if (remaining_to_withdraw == 0) {
            break
        };

        i = i + 1;
    };

    ticket
}

public(package) fun redeem_withdraw_ticket<T>(
    vault: &mut Vault<T>,
    ticket: WithdrawTicket<T>,
): Balance<T> {
    check_latest_version(vault);

    let mut out = balance::zero();

    let (to_withdraw_from_available_balance, mut strategy_infos, lp_to_burn) = ticket.extract_withdraw_ticket();

    let lp_to_burn_amt = balance::value(&lp_to_burn);

    while (vec_map::size(&strategy_infos) > 0) {
        let (strategy_id, withdraw_info) = vec_map::pop(&mut strategy_infos);

        let (
            to_withdraw,
            withdrawn_balance,
            has_withdrawn,
        ) = withdraw_info.extract_strategy_withdraw_info();

        if (to_withdraw > 0) {
            assert!(has_withdrawn, EStrategyNotWithdrawn);
        };

        if (withdrawn_balance.value() < to_withdraw) {
            event::emit(StrategyLossEvent<T> {
                strategy_id,
                to_withdraw,
                withdrawn: withdrawn_balance.value(),
            });
        };

        // Reduce strategy's borrowed amount. This calculation is intentionally based on
        // `to_withdraw` and not `withdrawn_balance` amount so that any losses generated
        // by the withdrawal are effectively covered by the user and considered paid back
        // to the vault. This also ensures that vault's `total_available_balance` before
        // and after withdrawal matches the amount of lp tokens burned.
        let strategy_state = vault.strategies.get_mut(&strategy_id);

        let current_borrowed = strategy_state.borrowed();
        strategy_state.set_borrowed(current_borrowed - to_withdraw);

        balance::join(&mut out, withdrawn_balance);
    };

    strategy_infos.destroy_empty();

    out.join(
        vault.available_balance.split(to_withdraw_from_available_balance),
    );

    vault.lp_supply.decrease_supply(
        lp_to_burn,
    );

    event::emit(WithdrawEvent<T> {
        amount: balance::value(&out),
        lp_burned: lp_to_burn_amt,
    });

    vault.withdraw_ticket_issued = false;

    out
}

public(package) fun withdraw_t_amt<T>(
    vault: &mut Vault<T>,
    t_amt: u64,
    balance: &mut Balance<YieldToken<T>>,
    clock: &Clock,
): WithdrawTicket<T> {
    let total_available = vault.total_available_balance(clock);

    let yt_amt = muldiv_round_up(
        t_amt,
        vault.lp_supply.supply_value(),
        total_available,
    );

    let balance = balance::split(balance, yt_amt);

    withdraw(vault, balance, clock)
}

/* ================= strategy operations ================= */

/// Makes the strategy deposit the withdrawn balance into the `WithdrawTicket`.
public(package) fun strategy_withdraw_to_ticket<T>(
    ticket: &mut WithdrawTicket<T>,
    access: &VaultAccess,
    balance: Balance<T>,
) {
    let strategy_id = access.vault_access_id();
    let withdraw_info = ticket.get_mut_strategy_info(&strategy_id);

    assert!(withdraw_info.has_withdrawn() == false, EStrategyAlreadyWithdrawn);
    withdraw_info.set_has_withdrawn(true);

    withdraw_info.join_withdrawn_balance(balance);
}

/// Get the target rebalance amounts the strategies should repay or can borrow.
/// It takes into account strategy target allocation weights and max borrow limits
/// and calculates the values so that the vault's balance allocations are kept
/// at the target weights and all of the vault's balance is allocated.
/// This function is idempotent in the sense that if you rebalance the pool with
/// the returned amounts and call it again, the result will require no further
/// rebalancing.
/// The strategies are not expected to repay / borrow the exact amounts suggested
/// as this may be dictated by their internal logic, but they should try to
/// get as close as possible. Since the strategies are trusted, there are no
/// explicit checks for this within the vault.
public(package) fun calc_rebalance_amounts<T>(vault: &Vault<T>, clock: &Clock): RebalanceAmounts {
    assert!(vault.withdraw_ticket_issued == false, EWithdrawTicketIssued);

    // calculate total available balance and prepare rebalance infos
    let mut rebalance_infos: VecMap<ID, RebalanceInfo> = vec_map::empty();
    let mut total_available_balance = 0;
    let mut max_borrow_idxs_to_process = vector::empty();
    let mut no_max_borrow_idxs = vector::empty();

    total_available_balance = total_available_balance + vault.available_balance.value();

    total_available_balance =
        total_available_balance + tlb::max_withdrawable(&vault.time_locked_profit, clock);

    let mut i = 0;
    let n = vault.strategies.size();
    
    while (i < n) {
        let (strategy_id, strategy_state) = vault.strategies.get_entry_by_idx(i);
        vec_map::insert(
            &mut rebalance_infos,
            *strategy_id,
            protocol::new_rebalance_info(0, 0),
        );

        total_available_balance = total_available_balance + strategy_state.borrowed();

        if (strategy_state.exists_max_borrow()) {
            vector::push_back(&mut max_borrow_idxs_to_process, i);
        } else {
            vector::push_back(&mut no_max_borrow_idxs, i);
        };

        i = i + 1;
    };

    // process strategies with max borrow limits iteratively until all who can
    // reach their cap have reached it
    let mut remaining_to_allocate = total_available_balance;
    let mut remaining_total_alloc_bps = BPS_IN_100_PCT;

    let mut need_to_reprocess = true;
    while (need_to_reprocess) {
        let mut i = 0;
        let n = vector::length(&max_borrow_idxs_to_process);
        let mut new_max_borrow_idxs_to_process = vector::empty();
        need_to_reprocess = false;
        while (i < n) {
            let idx = *vector::borrow(&max_borrow_idxs_to_process, i);
            let (_, strategy_state) = vec_map::get_entry_by_idx(&vault.strategies, idx);
            let (_, rebalance_info) = vec_map::get_entry_by_idx_mut(&mut rebalance_infos, idx);

            let max_borrow: u64 = strategy_state.max_borrow();
            let target_alloc_amt = muldiv(
                remaining_to_allocate,
                strategy_state.target_alloc_weight_bps(),
                remaining_total_alloc_bps,
            );

            if (
                target_alloc_amt <= strategy_state.borrowed() || max_borrow <= strategy_state.borrowed()
            ) {
                // needs to repay
                if (target_alloc_amt < max_borrow) {
                    vector::push_back(&mut new_max_borrow_idxs_to_process, idx);
                } else {
                    let target_alloc_amt = max_borrow;

                    rebalance_info.set_to_repay(strategy_state.borrowed() - target_alloc_amt);

                    remaining_to_allocate = remaining_to_allocate - target_alloc_amt;
                    remaining_total_alloc_bps =
                        remaining_total_alloc_bps - strategy_state.target_alloc_weight_bps();

                    // might add extra amounts to allocate so need to reprocess ones which
                    // haven't reached their cap
                    need_to_reprocess = true;
                };

                i = i + 1;
                continue
            };

            // can borrow
            if (target_alloc_amt >= max_borrow) {
                let target_alloc_amt = max_borrow;
                rebalance_info.set_can_borrow(target_alloc_amt - strategy_state.borrowed());

                remaining_to_allocate = remaining_to_allocate - target_alloc_amt;
                remaining_total_alloc_bps =
                    remaining_total_alloc_bps - strategy_state.target_alloc_weight_bps();

                // might add extra amounts to allocate so need to reprocess ones which
                // haven't reached their cap
                need_to_reprocess = true;

                i = i + 1;
                continue
            } else {
                vector::push_back(&mut new_max_borrow_idxs_to_process, idx);

                i = i + 1;
                continue
            }
        };

        max_borrow_idxs_to_process = new_max_borrow_idxs_to_process;
    };

    // the remaining strategies in `max_borrow_idxs_to_process` and `no_max_borrow_idxs` won't reach
    // their cap so we can easilly calculate the remaining amounts to allocate
    let mut i = 0;
    let n = vector::length(&max_borrow_idxs_to_process);
    while (i < n) {
        let idx = *vector::borrow(&max_borrow_idxs_to_process, i);
        let (_, strategy_state) = vec_map::get_entry_by_idx(&vault.strategies, idx);
        let (_, rebalance_info) = vec_map::get_entry_by_idx_mut(&mut rebalance_infos, idx);

        let target_borrow = muldiv(
            remaining_to_allocate,
            strategy_state.target_alloc_weight_bps(),
            remaining_total_alloc_bps,
        );
        if (target_borrow >= strategy_state.borrowed()) {
            rebalance_info.set_can_borrow(target_borrow - strategy_state.borrowed());
        } else {
            rebalance_info.set_to_repay(strategy_state.borrowed() - target_borrow);
        };

        i = i + 1;
    };

    let mut i = 0;
    let n = vector::length(&no_max_borrow_idxs);
    while (i < n) {
        let idx = *vector::borrow(&no_max_borrow_idxs, i);
        let (_, strategy_state) = vec_map::get_entry_by_idx(&vault.strategies, idx);
        let (_, rebalance_info) = vec_map::get_entry_by_idx_mut(&mut rebalance_infos, idx);

        let target_borrow = muldiv(
            remaining_to_allocate,
            strategy_state.target_alloc_weight_bps(),
            remaining_total_alloc_bps,
        );
        if (target_borrow >= strategy_state.borrowed()) {
            rebalance_info.set_can_borrow(target_borrow - strategy_state.borrowed());
        } else {
            rebalance_info.set_to_repay(strategy_state.borrowed() - target_borrow);
        };

        i = i + 1;
    };

    protocol::new_rebalance_amounts(rebalance_infos)
}

/// Strategies call this to repay loaned amounts.
public(package) fun strategy_repay<T>(
    vault: &mut Vault<T>,
    access: &VaultAccess,
    balance: Balance<T>,
) {
    check_latest_version(vault);
    assert!(vault.withdraw_ticket_issued == false, EWithdrawTicketIssued);

    // amounts are purposefully not checked here because the strategies
    // are trusted to repay the correct amounts based on `RebalanceInfo`.
    let strategy_id = access.vault_access_id();
    let strategy_state = vault.strategies.get_mut(&strategy_id);

    let current_borrowed = strategy_state.borrowed();
    strategy_state.set_borrowed(current_borrowed - balance.value());

    vault.available_balance.join(balance);
}

/// Strategies call this to borrow additional funds from the vault. Always returns
/// exact amount requested or aborts.
public(package) fun strategy_borrow<T>(
    vault: &mut Vault<T>,
    access: &VaultAccess,
    amount: u64,
): Balance<T> {
    check_latest_version(vault);
    assert!(vault.withdraw_ticket_issued == false, EWithdrawTicketIssued);

    // amounts are purpusfully not checked here because the strategies
    // are trusted to borrow the correct amounts based on `RebalanceInfo`.
    let strategy_id = access.vault_access_id();
    let strategy_state = vault.strategies.get_mut(&strategy_id);
    let balance = vault.available_balance.split(amount);

    let current_borrowed = strategy_state.borrowed();
    strategy_state.set_borrowed(current_borrowed + amount);

    balance
}

public(package) fun strategy_hand_over_profit<T>(
    vault: &mut Vault<T>,
    access: &VaultAccess,
    profit: Balance<T>,
    clock: &Clock,
) {
    check_latest_version(vault);
    assert!(vault.withdraw_ticket_issued == false, EWithdrawTicketIssued);
    let strategy_id = access.vault_access_id();
    assert!(vault.strategies.contains(&strategy_id), EInvalidVaultAccess);

    // collect performance fee
    let fee_amt_t = muldiv(
        balance::value(&profit),
        vault.performance_fee_bps,
        BPS_IN_100_PCT,
    );
    let fee_amt_yt = if (fee_amt_t > 0) {
        let total_available_balance = total_available_balance(vault, clock);
        // dL = L * f / (A - f)
        let fee_amt_yt = muldiv(
            vault.lp_supply.supply_value(),
            fee_amt_t,
            total_available_balance - fee_amt_t,
        );
        let fee_yt = vault.lp_supply.increase_supply(fee_amt_yt);
        balance::join(&mut vault.performance_fee_balance, fee_yt);

        fee_amt_yt
    } else {
        0
    };

    event::emit(StrategyProfitEvent<T> {
        strategy_id: access.vault_access_id(),
        profit: balance::value(&profit),
        fee_amt_yt: fee_amt_yt,
    });

    // reset profit unlock
    balance::join(
        &mut vault.available_balance,
        tlb::withdraw_all(&mut vault.time_locked_profit, clock),
    );

    tlb::change_unlock_per_second(&mut vault.time_locked_profit, 0, clock);
    let mut redeposit = tlb::skim_extraneous_balance(&mut vault.time_locked_profit);
    balance::join(&mut redeposit, profit);

    tlb::change_unlock_start_ts_sec(
        &mut vault.time_locked_profit,
        timestamp_sec(clock),
        clock,
    );
    let unlock_per_second = u64::divide_and_round_up(
        balance::value(&redeposit),
        vault.profit_unlock_duration_sec,
    );
    tlb::change_unlock_per_second(
        &mut vault.time_locked_profit,
        unlock_per_second,
        clock,
    );

    tlb::top_up(&mut vault.time_locked_profit, redeposit, clock);
}

#[test_only]
public fun new_for_testing<T>(
    available_balance: Balance<T>,
    time_locked_profit: TimeLockedBalance<T>,
    strategies: VecMap<ID, StrategyState>,
    strategy_withdraw_priority_order: vector<ID>,
    withdraw_ticket_issued: bool,
    tvl_cap: Option<u64>,
    profit_unlock_duration_sec: u64,
    performance_fee_bps: u64,
    version: u64,
    ctx: &mut TxContext,
): Vault<T> {
    new(
        available_balance, 
        0, 
        table::new(ctx), 
        time_locked_profit, 
        balance::create_supply(common::new_yield_token<T>()), 
        strategies, 
        strategy_withdraw_priority_order, 
        withdraw_ticket_issued, 
        tvl_cap, 
        profit_unlock_duration_sec, 
        performance_fee_bps, 
        version, 
        ctx
    )
}