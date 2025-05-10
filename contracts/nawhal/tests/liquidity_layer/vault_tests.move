#[test_only]
module narval::vault_tests;

/* =================================================== tests =================================================== */

use sui::coin::{Self, CoinMetadata, TreasuryCap};
use sui::balance::{Self, Balance};
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};
use sui::clock;

use narval::access::{Self, VaultAccess};
use narval::protocol::{Self, WithdrawTicket, StrategyState};

public struct A has drop {}

public struct VAULT has drop {}


fun create_a_treasury(ctx: &mut TxContext): (TreasuryCap<VAULT>, CoinMetadata<VAULT>) {
    coin::create_currency(VAULT {}, 6, b"ywhUSDC.e", b"", b"", option::none(), ctx)
}

fun mint_a_balance(amount: u64): Balance<A> {
    let mut supply = balance::create_supply(A {});
    let balance = balance::increase_supply(&mut supply, amount);
    sui::test_utils::destroy(supply);
    balance
}

#[test]
fun test_total_available_balance() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        object::id_from_address(@0xA),
        StrategyState {
            borrowed: 100,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        object::id_from_address(@0xB),
        StrategyState {
            borrowed: 50,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, object::id_from_address(@0xA));
    vector::push_back(&mut strategy_withdraw_priority_order, object::id_from_address(@0xB));

    let vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(10),
        time_locked_profit: tlb::create(mint_a_balance(200), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 100 * 1000);
    assert!(total_available_balance(&vault, &clock) == 260, 0);

    sui::test_utils::destroy(meta);
    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(clock);
}

#[test_only]
fun assert_ticket_values<T, TY>(
    ticket: &WithdrawTicket<T, TY>,
    to_withdraw_from_free_balance: u64,
    keys: vector<ID>,
    to_withdraw_values: vector<u64>,
    lp_to_burn_amount: u64,
) {
    assert!(vector::length(&keys) == vector::length(&to_withdraw_values), 0);
    assert!(ticket.to_withdraw_from_free_balance == to_withdraw_from_free_balance, 0);
    let mut seen: VecSet<ID> = vec_set::empty();
    let mut i = 0;
    let n = vector::length(&keys);
    while (i < n) {
        let strategy_id = *vector::borrow(&keys, i);
        vec_set::insert(&mut seen, strategy_id);
        let strategy_withdraw_info = vec_map::get(&ticket.strategy_infos, &strategy_id);
        assert!(strategy_withdraw_info.to_withdraw == *vector::borrow(&to_withdraw_values, i), 0);
        i = i + 1;
    };
    assert!(balance::value(&ticket.lp_to_burn) == lp_to_burn_amount, 0);
}

#[test_only]
fun assert_ticket_total_withdraw<T, YT>(ticket: &WithdrawTicket<T, YT>, total: u64) {
    let mut i = 0;
    let n = vec_map::size(&ticket.strategy_infos);
    let mut total_withdraw = ticket.to_withdraw_from_free_balance;
    while (i < n) {
        let (_, strategy_withdraw_info) = vec_map::get_entry_by_idx(&ticket.strategy_infos, i);
        total_withdraw = total_withdraw + strategy_withdraw_info.to_withdraw;
        i = i + 1;
    };
    assert!(total_withdraw == total, 0);
}

#[test_only]
fun create_vault_for_testing(ctx: &mut TxContext): (Vault<A, VAULT>, Balance<VAULT>) {
    let (ya_treasury, meta) = create_a_treasury(ctx);

    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 1000,
            target_alloc_weight_bps: 4000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 2000,
            target_alloc_weight_bps: 1000,
            max_borrow: option::some(1500),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = Vault<A, VAULT> {
        id: object::new(ctx),
        free_balance: mint_a_balance(1000),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 10000);

    sui::test_utils::destroy(meta);

    (vault, lp)
}

#[test]
fun test_withdraw_from_free_balance() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut lp, 500);
    let ticket = withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 0);
    assert_ticket_values(
        &ticket,
        500,
        keys,
        values,
        500,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_over_cap() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut lp, 2200);
    let ticket = withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 200);
    assert_ticket_values(
        &ticket,
        2000,
        keys,
        values,
        2200,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_proportional_tiny() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut lp, 2501);
    let ticket = withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 1);
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 500);
    assert_ticket_values(
        &ticket,
        2000,
        keys,
        values,
        2501,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_proportional_exact() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut lp, 3250);
    let ticket = withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 500);
    vector::push_back(&mut values, 100);
    vector::push_back(&mut values, 650);
    assert_ticket_values(
        &ticket,
        2000,
        keys,
        values,
        3250,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_proportional_undivisible() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut lp, 3251);
    let ticket = withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 501);
    vector::push_back(&mut values, 100);
    vector::push_back(&mut values, 650);
    assert_ticket_values(
        &ticket,
        2000,
        keys,
        values,
        3251,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_almost_all() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut lp, 9999);
    let ticket = withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 5000);
    vector::push_back(&mut values, 1000);
    vector::push_back(&mut values, 1999);
    assert_ticket_values(
        &ticket,
        2000,
        keys,
        values,
        9999,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_all() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let ticket = withdraw(&mut vault, lp, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 5000);
    vector::push_back(&mut values, 1000);
    vector::push_back(&mut values, 2000);
    assert_ticket_values(
        &ticket,
        2000,
        keys,
        values,
        10000,
    );

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_t_amt() {
    let mut ctx = tx_context::dummy();

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 2000);

    let ticket = withdraw_t_amt(&mut vault, 3800, &mut lp, &clock);

    assert_ticket_total_withdraw(&ticket, 3800);
    assert!(balance::value(&ticket.lp_to_burn) == 3455, 0);
    assert!(balance::value(&lp) == 10000 - 3455, 0);

    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_ticket_redeem() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut lp) = create_vault_for_testing(&mut ctx);

    let mut strategy_infos = vec_map::empty();
    vec_map::insert(
        &mut strategy_infos,
        id_a,
        StrategyWithdrawInfo {
            to_withdraw: 2500,
            withdrawn_balance: balance::create_for_testing(2500),
            has_withdrawn: true,
        },
    );
    vec_map::insert(
        &mut strategy_infos,
        id_b,
        StrategyWithdrawInfo {
            to_withdraw: 0,
            withdrawn_balance: balance::zero(),
            has_withdrawn: false,
        },
    );
    vec_map::insert(
        &mut strategy_infos,
        id_c,
        StrategyWithdrawInfo {
            to_withdraw: 1000,
            withdrawn_balance: balance::create_for_testing(500),
            has_withdrawn: true,
        },
    );
    let ticket = WithdrawTicket {
        to_withdraw_from_free_balance: 1000,
        strategy_infos,
        lp_to_burn: balance::split(&mut lp, 4500),
    };

    let out = redeem_withdraw_ticket(&mut vault, ticket);

    assert!(balance::value(&out) == 4000, 0);

    let strat_state_a = vec_map::get(&vault.strategies, &id_a);
    assert!(strat_state_a.borrowed == 2500, 0);
    let strat_state_a = vec_map::get(&vault.strategies, &id_b);
    assert!(strat_state_a.borrowed == 1000, 0);
    let strat_state_a = vec_map::get(&vault.strategies, &id_c);
    assert!(strat_state_a.borrowed == 1000, 0);

    assert!(balance::value(&vault.free_balance) == 0, 0);
    assert!(coin::total_supply(&vault.lp_treasury) == 5500, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(out);
}

#[test]
fun test_strategy_get_rebalance_amounts_one_strategy() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 10000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(1000),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 10000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    // free_balance: 1000
    // released from profits: 1000
    // strategies:
    //   - borrowed: 5000/inf, weight: 100%
    // expect:
    //   - can_borrow: 2000, to_repay: 0

    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 2000, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
}

#[test]
fun test_strategy_get_rebalance_amounts_two_strategies_balanced() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(1000),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 12000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    // free_balance: 1000
    // released from profits: 1000
    // strategies:
    //   - borrowed: 5000/inf, weight: 50%
    //   - borrowed: 5000/inf, weight: 50%
    // expect:
    //   - can_borrow: 1000, to_repay: 0
    //   - can_borrow: 1000, to_repay: 0

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
}

#[test]
fun test_strategy_get_rebalance_amounts_two_strategies_one_balanced() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 6000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(0),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 12000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    // free_balance: 0
    // released from profits: 1000
    // strategies:
    //   - borrowed: 5000/inf, weight: 50%
    //   - borrowed: 6000/inf, weight: 50%
    // expect:
    //   - can_borrow: 1000, to_repay: 0
    //   - can_borrow: 0, to_repay: 0

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
}

#[test]
fun test_strategy_get_rebalance_amounts_two_strategies_both_unbalanced() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 5000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(50),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 9100);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 50 * 1000);

    // free_balance: 50
    // released from profits: 50
    // strategies:
    //   - borrowed: 4000/inf, weight: 50%
    //   - borrowed: 5000/inf, weight: 50%
    // expect:
    //   - can_borrow: 550, to_repay: 0
    //   - can_borrow: 0, to_repay: 450

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 550, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 450, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_balanced() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_c = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);
    let id_c = object::uid_to_inner(&vault_access_c.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 2000,
            target_alloc_weight_bps: 2000,
            max_borrow: option::some(2000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 4000,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 4000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(0),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 10000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 0 * 1000);

    // free_balance: 0
    // released from profits: 0
    // strategies:
    //   - borrowed: 2000/2000, weight: 20%
    //   - borrowed: 4000/inf, weight: 40%
    //   - borrowed: 4000/inf, weight: 40%
    // expect:
    //   - can_borrow: 0, to_repay: 0
    //   - can_borrow: 0, to_repay: 0
    //   - can_borrow: 0, to_repay: 0

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
    sui::test_utils::destroy(vault_access_c);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_cap() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_c = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);
    let id_c = object::uid_to_inner(&vault_access_c.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 1000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::some(500),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 40_00,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 40_00,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(2500),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 15000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 2500 * 1000);

    // free_balance: 2500
    // released from profits: 2500
    // strategies:
    //   - borrowed: 1000/500, weight: 20%
    //   - borrowed: 4000/inf, weight: 40%
    //   - borrowed: 5000/inf, weight: 40%
    // expect:
    //   - can_borrow: 0, to_repay: 500
    //   - can_borrow: 3250, to_repay: 0
    //   - can_borrow: 2250, to_repay: 0

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 500, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 3250, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 2250, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
    sui::test_utils::destroy(vault_access_c);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_and_under_cap() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_c = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_d = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);
    let id_c = object::uid_to_inner(&vault_access_c.id);
    let id_d = object::uid_to_inner(&vault_access_d.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 1000,
            target_alloc_weight_bps: 10_00,
            max_borrow: option::some(500),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 30_00,
            max_borrow: option::some(5000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 30_00,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_d,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 30_00,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);
    vector::push_back(&mut strategy_withdraw_priority_order, id_d);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(2500),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 20000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 2500 * 1000);

    // free_balance: 2500
    // released from profits: 2500
    // strategies:
    //   - borrowed: 1000/500, weight: 10%
    //   - borrowed: 4000/5000, weight: 30%
    //   - borrowed: 5000/inf, weight: 30%
    //   - borrowed: 5000/inf, weight: 30%
    // expect:
    //   - can_borrow: 0, to_repay: 500
    //   - can_borrow: 1000, to_repay: 0
    //   - can_borrow: 2250, to_repay: 0
    //   - can_borrow: 2250, to_repay: 0

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 500, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 2250, 0);
    assert!(to_repay == 0, 0);
    // d
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_d);
    assert!(can_borrow == 2250, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
    sui::test_utils::destroy(vault_access_c);
    sui::test_utils::destroy(vault_access_d);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_and_two_under_cap() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_c = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_d = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_e = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);
    let id_c = object::uid_to_inner(&vault_access_c.id);
    let id_d = object::uid_to_inner(&vault_access_d.id);
    let id_e = object::uid_to_inner(&vault_access_e.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 1000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::some(500),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::some(5000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::some(10000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_d,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_e,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);
    vector::push_back(&mut strategy_withdraw_priority_order, id_d);
    vector::push_back(&mut strategy_withdraw_priority_order, id_e);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(2500),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 25000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 2500 * 1000);

    // free_balance: 2500
    // released from profits: 2500
    // strategies:
    //   - borrowed: 1000/500, weight: 10%
    //   - borrowed: 4000/5000, weight: 20%
    //   - borrowed: 5000/10000, weight: 20%
    //   - borrowed: 5000/inf, weight: 20%
    //   - borrowed: 5000/inf, weight: 20%
    // expect:
    //   - can_borrow: 0, to_repay: 500
    //   - can_borrow: 1000, to_repay: 0
    //   - can_borrow: 1500, to_repay: 0
    //   - can_borrow: 1500, to_repay: 0
    //   - can_borrow: 1500, to_repay: 0

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 500, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 1500, 0);
    assert!(to_repay == 0, 0);
    // d
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_d);
    assert!(can_borrow == 1500, 0);
    assert!(to_repay == 0, 0);
    // e
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_e);
    assert!(can_borrow == 1500, 0);
    assert!(to_repay == 0, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
    sui::test_utils::destroy(vault_access_c);
    sui::test_utils::destroy(vault_access_d);
    sui::test_utils::destroy(vault_access_e);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_reduce_and_two_under_cap() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_c = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_d = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_e = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);
    let id_c = object::uid_to_inner(&vault_access_c.id);
    let id_d = object::uid_to_inner(&vault_access_d.id);
    let id_e = object::uid_to_inner(&vault_access_e.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 6000,
            target_alloc_weight_bps: 4_00,
            max_borrow: option::some(5000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 4000,
            target_alloc_weight_bps: 24_00,
            max_borrow: option::some(5000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 22_00,
            max_borrow: option::some(10000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_d,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 30_00,
            max_borrow: option::none(),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_e,
        StrategyState {
            borrowed: 10000,
            target_alloc_weight_bps: 20_00,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);
    vector::push_back(&mut strategy_withdraw_priority_order, id_d);
    vector::push_back(&mut strategy_withdraw_priority_order, id_e);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(2500),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 35000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 2500 * 1000);

    // free_balance: 2500
    // released from profits: 2500
    // strategies:
    //   - borrowed: 6000/5000, weight: 4%
    //   - borrowed: 4000/5000, weight: 24%
    //   - borrowed: 5000/10000, weight: 22%
    //   - borrowed: 5000/inf, weight: 30%
    //   - borrowed: 5000/inf, weight: 20%
    // expect:
    //   - can_borrow: 0, to_repay: 4600
    //   - can_borrow: 1000, to_repay: 0
    //   - can_borrow: 3738, to_repay: 0
    //   - can_borrow: 6916, to_repay: 0
    //   - can_borrow: 0, to_repay: 2056

    // a
    let amts = calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 4422, 0);
    // b
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 3684, 0);
    assert!(to_repay == 0, 0);
    // d
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_d);
    assert!(can_borrow == 6842, 0);
    assert!(to_repay == 0, 0);
    // e
    let (can_borrow, to_repay) = rebalance_amounts_get(&amts, &vault_access_e);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 2106, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_b);
    sui::test_utils::destroy(vault_access_c);
    sui::test_utils::destroy(vault_access_d);
    sui::test_utils::destroy(vault_access_e);
}

#[test]
fun test_strategy_hand_over_profit() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 1000,
            target_alloc_weight_bps: 10000,
            max_borrow: option::none(),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(1000),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 10_00,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 3000);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let profit = balance::create_for_testing<A>(5000);
    strategy_hand_over_profit(
        &mut vault,
        &vault_access_a,
        profit,
        &clock,
    );

    assert!(balance::value(&vault.free_balance) == 2000, 0);
    assert!(tlb::remaining_unlock(&vault.time_locked_profit, &clock) == 13998, 0);
    assert!(tlb::extraneous_locked_amount(&vault.time_locked_profit) == 2, 0);
    assert!(tlb::unlock_start_ts_sec(&vault.time_locked_profit) == timestamp_sec(&clock), 0);
    assert!(tlb::unlock_per_second(&vault.time_locked_profit) == 3, 0);
    assert!(tlb::final_unlock_ts_sec(&vault.time_locked_profit) == timestamp_sec(&clock) + 4666, 0);
    assert!(balance::value(&vault.performance_fee_balance) == 600, 0);

    let fee_yt = balance::create_for_testing<VAULT>(600);
    let ticket = withdraw(&mut vault, fee_yt, &clock);
    let fee_t = redeem_withdraw_ticket(&mut vault, ticket);
    assert!(balance::value(&fee_t) == 500, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(clock);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(fee_t);
}

#[test]
fun test_remove_strategy() {
    let mut ctx = tx_context::dummy();
    let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let vault_access_a = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_b = VaultAccess { id: object::new(&mut ctx) };
    let vault_access_c = VaultAccess { id: object::new(&mut ctx) };
    let id_a = object::uid_to_inner(&vault_access_a.id);
    let id_b = object::uid_to_inner(&vault_access_b.id);
    let id_c = object::uid_to_inner(&vault_access_c.id);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        StrategyState {
            borrowed: 6000,
            target_alloc_weight_bps: 4_00,
            max_borrow: option::some(5000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        StrategyState {
            borrowed: 1000,
            target_alloc_weight_bps: 50_00,
            max_borrow: option::some(5000),
        },
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        StrategyState {
            borrowed: 5000,
            target_alloc_weight_bps: 46_00,
            max_borrow: option::some(10000),
        },
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = Vault<A, VAULT> {
        id: object::new(&mut ctx),
        free_balance: mint_a_balance(2500),
        time_locked_profit: tlb::create(mint_a_balance(10000), 0, 1),
        lp_treasury: ya_treasury,
        strategies,
        performance_fee_balance: balance::zero(),
        strategy_withdraw_priority_order,
        withdraw_ticket_issued: false,
        tvl_cap: option::none(),
        profit_unlock_duration_sec: DEFAULT_PROFIT_UNLOCK_DURATION_SEC,
        performance_fee_bps: 0,
        version: MODULE_VERSION,
    };
    let lp = coin::mint_balance(&mut vault.lp_treasury, 15500);

    sui::test_utils::destroy(meta);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let admin_cap = AdminCap<VAULT> { id: object::new(&mut ctx) };
    let ticket = new_strategy_removal_ticket(vault_access_b, mint_a_balance(10000));
    let mut ids_for_weights = vector::empty();
    vector::push_back(&mut ids_for_weights, id_a);
    vector::push_back(&mut ids_for_weights, id_c);
    let mut new_weights = vector::empty();
    vector::push_back(&mut new_weights, 30_00);
    vector::push_back(&mut new_weights, 70_00);
    remove_strategy(&admin_cap, &mut vault, ticket, ids_for_weights, new_weights, &clock);

    assert!(vec_map::size(&vault.strategies) == 2, 0);
    assert!(vec_map::get(&vault.strategies, &id_a).target_alloc_weight_bps == 30_00, 0);
    assert!(vec_map::get(&vault.strategies, &id_c).target_alloc_weight_bps == 70_00, 0);
    let mut exp_priority_order = vector::empty();
    vector::push_back(&mut exp_priority_order, id_a);
    vector::push_back(&mut exp_priority_order, id_c);
    assert!(vault.strategy_withdraw_priority_order == exp_priority_order, 0);

    sui::test_utils::destroy(vault);
    sui::test_utils::destroy(lp);
    sui::test_utils::destroy(admin_cap);
    sui::test_utils::destroy(vault_access_a);
    sui::test_utils::destroy(vault_access_c);
    sui::test_utils::destroy(clock);
}
