#[test_only]
module narval::vault_tests;

/* =================================================== tests =================================================== */

use sui::coin;
use sui::balance::{Self, Balance};
use sui::vec_map;
use sui::vec_set::{Self, VecSet};
use sui::clock;

use narval::access;
use narval::protocol::{Self, WithdrawTicket};
use narval::tlb::{Self};
use narval::util;
use narval::vault::{Self, Vault};
use narval::common::YieldToken;

use sui::test_utils;

public struct A has drop {}

fun mint_a_balance(amount: u64, ctx: &mut TxContext): Balance<A> {
    coin::mint_for_testing(amount, ctx).into_balance()
}

#[test]
fun test_deposit_withdraw_direct_should_work() {
    let protocol_id_a = object::id_from_address(@0xabc);
    let protocol_id_b = object::id_from_address(@0xdef);

    let mut ctx = tx_context::dummy();
    let (mut vault, yb) = create_vault_for_testing(&mut ctx);

    // Add direct deposit and withdraw
    let payment = mint_a_balance(500, &mut ctx);
    vault.deposit_direct(protocol_id_a, payment);

    assert!(vault.reserved_funds() == 500, 0);
    assert!(vault.reserved_funds_for_protocol(protocol_id_a) == 500, 0);

    let withdraw_balance = vault.withdraw_direct(protocol_id_a, 100);
    assert!(balance::value(&withdraw_balance) == 100, 0);

    let payment_b = mint_a_balance(800, &mut ctx);
    vault.deposit_direct(protocol_id_b, payment_b);

    assert!(vault.reserved_funds() == 1200, 0);
    assert!(vault.reserved_funds_for_protocol(protocol_id_a) == 400, 0);
    assert!(vault.reserved_funds_for_protocol(protocol_id_b) == 800, 0);
    
    test_utils::destroy(withdraw_balance);
    test_utils::destroy(vault);
    test_utils::destroy(yb);
}

#[test]
#[expected_failure(abort_code = vault::EReservedFundsNotEnough)]
fun test_deposit_withdraw_direct_should_fail_if_reserved_funds_not_enough() {
    let protocol_id_a = object::id_from_address(@0xabc);
    let mut ctx = tx_context::dummy();
    let (mut vault, yb) = create_vault_for_testing(&mut ctx);

    // Add direct deposit and withdraw
    let payment = mint_a_balance(500, &mut ctx);
    vault.deposit_direct(protocol_id_a, payment);

    let withdraw_balance = vault.withdraw_direct(protocol_id_a, 500);

    // Should fail
    let withdraw_balance_2 = vault.withdraw_direct(protocol_id_a, 1);

    test_utils::destroy(withdraw_balance);
    test_utils::destroy(withdraw_balance_2);
    test_utils::destroy(vault);
    test_utils::destroy(yb);
}

#[test]
fun test_total_available_balance() {
    let mut ctx = tx_context::dummy();
    // let (ya_treasury, meta) = create_a_treasury(&mut ctx);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        object::id_from_address(@0xA),
        protocol::new_strategy_state(100, 5000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        object::id_from_address(@0xB),
        protocol::new_strategy_state(50, 5000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, object::id_from_address(@0xA));
    vector::push_back(&mut strategy_withdraw_priority_order, object::id_from_address(@0xB));

    let vault = vault::new_for_testing<A>(
        mint_a_balance(10, &mut ctx),
        tlb::create(mint_a_balance(200, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 100 * 1000);

    assert!(vault.total_available_balance(&clock) == 260, 0);

    test_utils::destroy(vault);
    test_utils::destroy(clock);
}

fun assert_ticket_values<T>(
    ticket: &WithdrawTicket<T>,
    to_withdraw_from_available_balance: u64,
    keys: vector<ID>,
    to_withdraw_values: vector<u64>,
    lp_to_burn_amount: u64,
) {
    assert!(vector::length(&keys) == vector::length(&to_withdraw_values), 0);
    assert!(ticket.to_withdraw_from_available_balance_value() == to_withdraw_from_available_balance, 0);
    let mut seen: VecSet<ID> = vec_set::empty();
    let mut i = 0;
    let n = vector::length(&keys);
    while (i < n) {
        let strategy_id = *vector::borrow(&keys, i);
        vec_set::insert(&mut seen, strategy_id);
        
        let strategy_withdraw_info = protocol::get_strategy_info(ticket, &strategy_id);

        assert!(strategy_withdraw_info.to_withdraw() == *vector::borrow(&to_withdraw_values, i), 0);

        i = i + 1;
    };
    assert!(ticket.lp_to_burn_value() == lp_to_burn_amount, 0);
}

fun assert_ticket_total_withdraw<T>(ticket: &WithdrawTicket<T>, total: u64) {
    let mut i = 0;
    let n = ticket.strategy_infos_size();
    let mut total_withdraw =    ticket.to_withdraw_from_available_balance_value();

    while (i < n) {
        let (_, strategy_withdraw_info) = protocol::get_strategy_info_by_idx(ticket, i);
        total_withdraw = total_withdraw + strategy_withdraw_info.to_withdraw();
        i = i + 1;
    };

    assert!(total_withdraw == total, 0);
}

fun create_vault_for_testing(ctx: &mut TxContext): (Vault<A>, Balance<YieldToken<A>>) {

    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(5000, 5000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(1000, 4000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(2000, 1000, option::some(1500)),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(1000, ctx),
        tlb::create(mint_a_balance(10000, ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        ctx,
    );
        
    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(10000);

    (vault, yb)
}

#[test]
fun test_withdraw_from_free_balance() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut yb, 500);
    let ticket = vault::withdraw(&mut vault, to_withdraw, &clock);

    let mut keys = vector::empty();
    vector::push_back(&mut keys, id_a);
    vector::push_back(&mut keys, id_b);
    vector::push_back(&mut keys, id_c);
    let mut values = vector::empty();
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 0);
    vector::push_back(&mut values, 0);

    // Add direct deposit and withdraw
    let payment = mint_a_balance(500, &mut ctx);
    vault.deposit_direct(id_a, payment);

    assert_ticket_values(
        &ticket,
        500,
        keys,
        values,
        500,
    );

    let withdraw_balance = vault.withdraw_direct(id_a, 500);

    assert!(balance::value(&withdraw_balance) == 500, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
    test_utils::destroy(withdraw_balance);
}

#[test]
fun test_withdraw_over_cap() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut yb, 2200);
    let ticket = vault::withdraw(&mut vault, to_withdraw, &clock);

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

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_proportional_tiny() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut yb, 2501);
    let ticket = vault::withdraw(&mut vault, to_withdraw, &clock);

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

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_proportional_exact() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut yb, 3250);
    let ticket = vault::withdraw(&mut vault, to_withdraw, &clock);

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

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_proportional_undivisible() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut yb, 3251);
    let ticket = vault::withdraw(&mut vault, to_withdraw, &clock);

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

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_almost_all() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let to_withdraw = balance::split(&mut yb, 9999);
    let ticket = vault::withdraw(&mut vault, to_withdraw, &clock);

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

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
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

    let ticket = vault::withdraw(&mut vault, lp, &clock);

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

    test_utils::destroy(vault);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_t_amt() {
    let mut ctx = tx_context::dummy();

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 2000);

    let ticket = vault::withdraw_t_amt(&mut vault, 3800, &mut yb, &clock);

    assert_ticket_total_withdraw(&ticket, 3800);
    assert!(ticket.lp_to_burn_value() == 3455, 0);
    assert!(balance::value(&yb) == 10000 - 3455, 0);

    test_utils::destroy(yb);
    test_utils::destroy(vault);
    test_utils::destroy(clock);
    test_utils::destroy(ticket);
}

#[test]
fun test_withdraw_ticket_redeem() {
    let mut ctx = tx_context::dummy();
    let id_a = object::id_from_address(@0xA);
    let id_b = object::id_from_address(@0xB);
    let id_c = object::id_from_address(@0xC);

    let (mut vault, mut yb) = create_vault_for_testing(&mut ctx);

    let mut strategy_infos = vec_map::empty();
    vec_map::insert(
        &mut strategy_infos,
        id_a,
        protocol::new_strategy_withdraw_info<A>(2500, balance::create_for_testing(2500), true),
    );
    vec_map::insert(
        &mut strategy_infos,
        id_b,
        protocol::new_strategy_withdraw_info<A>(0, balance::zero(), false),
    );
    
    vec_map::insert(
        &mut strategy_infos,
        id_c,
        protocol::new_strategy_withdraw_info<A>(1000, balance::create_for_testing(500), true),
    );

    let ticket = protocol::new_withdraw_ticket(1000, strategy_infos, balance::split(&mut yb, 4500));

    let out = vault::redeem_withdraw_ticket(&mut vault, ticket);

    assert!(balance::value(&out) == 4000, 0);

    let strat_state_a = vault::get_strategy_by_id(&vault, &id_a);
    assert!(strat_state_a.borrowed() == 2500, 0);
    let strat_state_b = vault::get_strategy_by_id(&vault, &id_b);
    assert!(strat_state_b.borrowed() == 1000, 0);
    let strat_state_c = vault::get_strategy_by_id(&vault, &id_c);
    assert!(strat_state_c.borrowed() == 1000, 0);

    assert!(vault.available_balance<A>() == 0, 0);
    assert!(vault.total_yt_supply<A>() == 5500, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(out);
}

#[test]
fun test_strategy_get_rebalance_amounts_one_strategy() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(5000, 10000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(1000, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );
     
    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(10000);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    // free_balance: 1000
    // released from profits: 1000
    // strategies:
    //   - borrowed: 5000/inf, weight: 100%
    // expect:
    //   - can_borrow: 2000, to_repay: 0

    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 2000, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
}

#[test]
fun test_strategy_get_rebalance_amounts_two_strategies_balanced() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(5000, 5000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(5000, 5000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(1000, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(12000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
}

#[test]
fun test_strategy_get_rebalance_amounts_two_strategies_one_balanced() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(5000, 5000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(6000, 5000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(0, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(12000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
}

#[test]
fun test_strategy_get_rebalance_amounts_two_strategies_both_unbalanced() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(4000, 5000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(5000, 5000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(50, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(9100);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 550, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 450, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_balanced() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let vault_access_c = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();
    let id_c = vault_access_c.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(2000, 2000, option::some(2000)),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(4000, 4000, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(4000, 4000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(0, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(10000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
    test_utils::destroy(vault_access_c);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_cap() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let vault_access_c = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();
    let id_c = vault_access_c.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(1000, 20_00, option::some(500)),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(4000, 40_00, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(5000, 40_00, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(2500, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(15000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 500, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 3250, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 2250, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
    test_utils::destroy(vault_access_c);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_and_under_cap() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let vault_access_c = access::new_vault_access(&mut ctx);
    let vault_access_d = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();
    let id_c = vault_access_c.vault_access_id();
    let id_d = vault_access_d.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(1000, 10_00, option::some(500)),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(4000, 30_00, option::some(5000)),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(5000, 30_00, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_d,
        protocol::new_strategy_state(5000, 30_00, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);
    vector::push_back(&mut strategy_withdraw_priority_order, id_d);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(2500, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(20000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 500, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 2250, 0);
    assert!(to_repay == 0, 0);
    // d
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_d);
    assert!(can_borrow == 2250, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
    test_utils::destroy(vault_access_c);
    test_utils::destroy(vault_access_d);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_and_two_under_cap() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let vault_access_c = access::new_vault_access(&mut ctx);
    let vault_access_d = access::new_vault_access(&mut ctx);
    let vault_access_e = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();
    let id_c = vault_access_c.vault_access_id();
    let id_d = vault_access_d.vault_access_id();
    let id_e = vault_access_e.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(1000, 20_00, option::some(500)),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(4000, 20_00, option::some(5000)),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(5000, 20_00, option::some(10000)),
    );
    vec_map::insert(
        &mut strategies,
        id_d,
        protocol::new_strategy_state(5000, 20_00, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_e,
        protocol::new_strategy_state(5000, 20_00, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);
    vector::push_back(&mut strategy_withdraw_priority_order, id_d);
    vector::push_back(&mut strategy_withdraw_priority_order, id_e);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(2500, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(25000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 500, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 1500, 0);
    assert!(to_repay == 0, 0);
    // d
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_d);
    assert!(can_borrow == 1500, 0);
    assert!(to_repay == 0, 0);
    // e
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_e);
    assert!(can_borrow == 1500, 0);
    assert!(to_repay == 0, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
    test_utils::destroy(vault_access_c);
    test_utils::destroy(vault_access_d);
    test_utils::destroy(vault_access_e);
}

#[test]
fun test_strategy_get_rebalance_amounts_with_cap_over_reduce_and_two_under_cap() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let vault_access_c = access::new_vault_access(&mut ctx);
    let vault_access_d = access::new_vault_access(&mut ctx);
    let vault_access_e = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();
    let id_c = vault_access_c.vault_access_id();
    let id_d = vault_access_d.vault_access_id();
    let id_e = vault_access_e.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(6000, 4_00, option::some(5000)),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(4000, 24_00, option::some(5000)),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(5000, 22_00, option::some(10000)),
    );
    vec_map::insert(
        &mut strategies,
        id_d,
        protocol::new_strategy_state(5000, 30_00, option::none()),
    );
    vec_map::insert(
        &mut strategies,
        id_e,
        protocol::new_strategy_state(10000, 20_00, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);
    vector::push_back(&mut strategy_withdraw_priority_order, id_d);
    vector::push_back(&mut strategy_withdraw_priority_order, id_e);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(2500, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(35000);

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
    let amts = vault::calc_rebalance_amounts(&vault, &clock);
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_a);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 4422, 0);
    // b
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_b);
    assert!(can_borrow == 1000, 0);
    assert!(to_repay == 0, 0);
    // c
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_c);
    assert!(can_borrow == 3684, 0);
    assert!(to_repay == 0, 0);
    // d
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_d);
    assert!(can_borrow == 6842, 0);
    assert!(to_repay == 0, 0);
    // e
    let (can_borrow, to_repay) = protocol::rebalance_amounts_get(&amts, &vault_access_e);
    assert!(can_borrow == 0, 0);
    assert!(to_repay == 2106, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_b);
    test_utils::destroy(vault_access_c);
    test_utils::destroy(vault_access_d);
    test_utils::destroy(vault_access_e);
}

#[test]
fun test_strategy_hand_over_profit() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(1000, 10000, option::none()),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(1000, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        1000,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(3000);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let profit = balance::create_for_testing<A>(5000);
    vault::strategy_hand_over_profit(&mut vault, &vault_access_a, profit, &clock);

    assert!(vault::available_balance_value(&vault) == 2000, 0);
    assert!(tlb::remaining_unlock(vault.time_locked_profit(), &clock) == 13998, 0);
    assert!(tlb::extraneous_locked_amount(vault.time_locked_profit()) == 2, 0);
    assert!(tlb::unlock_start_ts_sec(vault.time_locked_profit()) == util::timestamp_sec(&clock), 0);
    assert!(tlb::unlock_per_second(vault.time_locked_profit()) == 3, 0);
    assert!(tlb::final_unlock_ts_sec(vault.time_locked_profit()) == util::timestamp_sec(&clock) + 4666, 0);
    // std::debug::print(&vault::performance_fee_balance_value(&vault));
    assert!(vault::performance_fee_balance_value(&vault) == 600, 0);

    let fee_yt = balance::create_for_testing<YieldToken<A>>(600);
    let ticket = vault.withdraw<A>( fee_yt, &clock);
    let fee_t = vault.redeem_withdraw_ticket(ticket);
    assert!(balance::value(&fee_t) == 500, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(clock);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(fee_t);
}

#[test]
fun test_remove_strategy() {
    let mut ctx = tx_context::dummy();

    let vault_access_a = access::new_vault_access(&mut ctx);
    let vault_access_b = access::new_vault_access(&mut ctx);
    let vault_access_c = access::new_vault_access(&mut ctx);
    let id_a = vault_access_a.vault_access_id();
    let id_b = vault_access_b.vault_access_id();
    let id_c = vault_access_c.vault_access_id();

    let mut strategies = vec_map::empty();
    vec_map::insert(
        &mut strategies,
        id_a,
        protocol::new_strategy_state(6000, 4_00, option::some(5000)),
    );
    vec_map::insert(
        &mut strategies,
        id_b,
        protocol::new_strategy_state(1000, 50_00, option::some(5000)),
    );
    vec_map::insert(
        &mut strategies,
        id_c,
        protocol::new_strategy_state(5000, 46_00, option::some(10000)),
    );

    let mut strategy_withdraw_priority_order = vector::empty();
    vector::push_back(&mut strategy_withdraw_priority_order, id_a);
    vector::push_back(&mut strategy_withdraw_priority_order, id_b);
    vector::push_back(&mut strategy_withdraw_priority_order, id_c);

    let mut vault = vault::new_for_testing<A>(
        mint_a_balance(2500, &mut ctx),
        tlb::create(mint_a_balance(10000, &mut ctx), 0, 1),
        strategies,
        strategy_withdraw_priority_order,
        false,
        option::none(),
        vault::default_profit_unlock_duration_sec(),
        0,
        vault::module_version(),
        &mut ctx,
    );

    let yb = vault::borrow_mut_lp_supply(&mut vault).increase_supply(15500);

    let mut clock = clock::create_for_testing(&mut ctx);
    clock::increment_for_testing(&mut clock, 1000 * 1000);

    let admin_cap = access::new_vault_cap(&mut ctx);
    let ticket = protocol::new_strategy_removal_ticket<A>(vault_access_b, mint_a_balance(10000, &mut ctx));
    let mut ids_for_weights = vector::empty();
    
    vector::push_back(&mut ids_for_weights, id_a);
    vector::push_back(&mut ids_for_weights, id_c);
    let mut new_weights = vector::empty();
    vector::push_back(&mut new_weights, 30_00);
    vector::push_back(&mut new_weights, 70_00);
    vault::remove_strategy(&admin_cap, &mut vault, ticket, ids_for_weights, new_weights, &clock);

    assert!(vault::strategies_size(&vault) == 2, 0);
    assert!(vault::get_mut_strategy_state(&mut vault, &id_a).target_alloc_weight_bps() == 30_00, 0);
    assert!(vault::get_mut_strategy_state(&mut vault, &id_c).target_alloc_weight_bps() == 70_00, 0);

    let mut exp_priority_order = vector::empty();
    vector::push_back(&mut exp_priority_order, id_a);
    vector::push_back(&mut exp_priority_order, id_c);

    assert!(vault.strategy_withdraw_priority_order() == exp_priority_order, 0);

    test_utils::destroy(vault);
    test_utils::destroy(yb);
    test_utils::destroy(admin_cap);
    test_utils::destroy(vault_access_a);
    test_utils::destroy(vault_access_c);
    test_utils::destroy(clock);
}
