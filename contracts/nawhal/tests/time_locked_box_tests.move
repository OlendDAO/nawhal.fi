#[test_only]
module nawhal::time_locked_box_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::balance::{Self, Balance};

use sui::clock::Clock;

use nawhal::time_locked_box::{Self, TimeLockedBox};
use nawhal::util::get_sec;

use sui::test_utils::{Self, assert_eq};

use nawhal::common_tests::{Self, alice, BTC, ETH, USD};

/// Constants
const INITIAL_AMOUNT: u64 = 1000;
const UNLOCK_PER_SEC: u64 = 10;
const UNLOCK_START_AT_SEC: u64 = 100;

// Helper function to create a new time locked box
fun create_time_locked_box_for_testing<T>(
    sc: &mut Scenario,
    amount: u64,
    start_at_sec: u64,
    unlock_per_sec: u64,
    sender: address,
): TimeLockedBox<T> {
    sc.next_tx(sender);

    // Create a balance for testing
    let balance = balance::create_for_testing<T>(amount);
    
    // Create a new time locked box
    time_locked_box::new(
        balance,
        start_at_sec,
        unlock_per_sec
    )
}

fun withdraw_from_box_for_testing<T>(
    sc: &mut Scenario,
    box: &mut TimeLockedBox<T>,
    amount: u64,
    sender: address,
): Balance<T> {
    sc.next_tx(sender);
    // Take Shared Clock
    let clock = ts::take_shared<Clock>(sc);
 
    let withdraw_balance = time_locked_box::withdraw(box, amount, &clock);

    ts::return_shared(clock);

    withdraw_balance
}

fun withdraw_all_from_box_for_testing<T>(
    sc: &mut Scenario,
    box: &mut TimeLockedBox<T>,
    sender: address,
): Balance<T> {
    sc.next_tx(sender);
    // Take Shared Clock
    let clock = ts::take_shared<Clock>(sc);
 
    let withdraw_balance = time_locked_box::withdraw_all(box, &clock);

    ts::return_shared(clock);

    withdraw_balance
}

/// Change unlock start time for testing
fun change_unlock_start_sec_for_testing<T>(
    sc: &mut Scenario,
    box: &mut TimeLockedBox<T>,
    new_unlock_start_sec: u64,
    sender: address,
) {
    sc.next_tx(sender);
    let clock = ts::take_shared<Clock>(sc);
    box.change_unlock_start_ts_sec(new_unlock_start_sec, &clock);
    ts::return_shared(clock);
}

fun check_time_locked_box_values<T>(
    box: &TimeLockedBox<T>,
    unlocked_balance: u64,
    locked_balance: u64,
    unlock_start_at_sec: u64,
    unlock_per_sec: u64,
    previous_unlocked_at_sec: u64,
    unlock_end_at_sec: u64,
    accumulated_total_amount: u64,
    accumulated_unlocked_amount: u64,
) {
    assert_eq(unlock_start_at_sec, box.unlock_start_at_sec());
    assert_eq(unlock_per_sec, box.unlock_per_sec());
    assert_eq(previous_unlocked_at_sec, box.previous_unlocked_at_sec());
    assert_eq(unlock_end_at_sec, box.unlock_end_at_sec());

    let (actual_accumulated_total_amount, actual_accumulated_unlocked_amount) = box.accumulated_amount_values();
    assert_eq(accumulated_total_amount, actual_accumulated_total_amount);
    assert_eq(accumulated_unlocked_amount, actual_accumulated_unlocked_amount);

    let (actual_locked_balance, actual_unlocked_balance) = box.locked_unlocked_balance_values();
    assert_eq(locked_balance, actual_locked_balance);
    assert_eq(unlocked_balance, actual_unlocked_balance);
}

fun get_max_withdrawable_amount<T>(
    sc: &mut Scenario,
    box: &TimeLockedBox<T>,
    sender: address,
): u64 {
    sc.next_tx(sender);
    let clock = ts::take_shared<Clock>(sc);
    let max_withdrawable_amount = box.max_withdrawable_amount(get_sec(&clock));
    ts::return_shared(clock);
    
    max_withdrawable_amount
}

#[test]
fun test_new_time_locked_box_should_work() {
    
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    let btc_box = create_time_locked_box_for_testing<BTC>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());
    
    check_time_locked_box_values<BTC>(
        &btc_box,
        0,
        INITIAL_AMOUNT,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC - 1,
        200,
        INITIAL_AMOUNT,
        0
    );

    let eth_box = create_time_locked_box_for_testing<ETH>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());   

    check_time_locked_box_values<ETH>(
        &eth_box,
        0,
        INITIAL_AMOUNT,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC - 1,
        200,
        INITIAL_AMOUNT,
        0
    );

    test_utils::destroy(btc_box);
    test_utils::destroy(eth_box);

    sc0.end();
}

#[test]
fun test_deposit_box_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    let mut usd_box = create_time_locked_box_for_testing<USD>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());

    // Create additional balance
    let additional_amount = 500;
    let additional_balance = balance::create_for_testing<USD>(additional_amount);
    
    // Deposit additional balance
    usd_box.deposit(additional_balance);
    
    check_time_locked_box_values<USD>(
        &usd_box,
        0,
        INITIAL_AMOUNT + additional_amount,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC - 1,
        250,
        INITIAL_AMOUNT + additional_amount,
        0
    );

    test_utils::destroy(usd_box);

    sc0.end();
}

#[test]
fun test_withdraw_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    let mut usd_box = create_time_locked_box_for_testing<USD>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());

    common_tests::increase_clock_for_testing(sc, UNLOCK_START_AT_SEC, alice());

    // Withdraw after create box
    let withdrawn_balance = withdraw_from_box_for_testing(
        sc,
        &mut usd_box,
        10,
        alice(),
    );

    assert_eq(withdrawn_balance.value(), 10);

    // Check box state after withdrawn
    check_time_locked_box_values<USD>(
        &usd_box,
        0,
        INITIAL_AMOUNT - 10,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC,
        200,
        INITIAL_AMOUNT ,
        10
    );

    common_tests::increase_clock_for_testing(sc, 3, alice());

    // Withdraw a specified amount after 3 seconds
    let withdrawn_balance3 = withdraw_from_box_for_testing(
        sc,
        &mut usd_box,
        10,
        alice(),
    );

    assert_eq(withdrawn_balance3.value(), 10);

    check_time_locked_box_values<USD>(
        &usd_box,
        20,
        INITIAL_AMOUNT - 40,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC + 3,
        200,
        INITIAL_AMOUNT ,
        40
    );

    // Withdraw all
    let withdrawn_balance2 = withdraw_from_box_for_testing(
        sc,
        &mut usd_box,
        20,
        alice(),
    );

    assert_eq(withdrawn_balance2.value(), 20);

    check_time_locked_box_values<USD>(
        &usd_box,
        0,
        INITIAL_AMOUNT - 40,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC + 3,
        200,
        INITIAL_AMOUNT ,
        40
    );

    test_utils::destroy(usd_box);
    test_utils::destroy(withdrawn_balance);
    test_utils::destroy(withdrawn_balance2);
    test_utils::destroy(withdrawn_balance3);

    sc0.end();
}

#[test, expected_failure(abort_code = time_locked_box::EInvalidUnlockTimestamp)]
fun test_withdraw_before_unlock_start() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    let mut usd_box = create_time_locked_box_for_testing<USD>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());

    common_tests::increase_clock_for_testing(sc, UNLOCK_START_AT_SEC - 1, alice());

    // Withdraw after create box
    let withdrawn_balance = withdraw_from_box_for_testing(
        sc,
        &mut usd_box,
        10,
        alice(),
    );

    test_utils::destroy(usd_box);
    test_utils::destroy(withdrawn_balance);

    sc0.end();
}

#[test]
fun test_withdraw_all_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    let mut usd_box = create_time_locked_box_for_testing<USD>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());

    common_tests::increase_clock_for_testing(sc, UNLOCK_START_AT_SEC + 3, alice());

    // Withdraw a specified amount after 3 seconds
    let withdrawn_balance3 = withdraw_all_from_box_for_testing(
        sc,
        &mut usd_box,
        alice(),
    );

    assert_eq(withdrawn_balance3.value(), 40);

    check_time_locked_box_values<USD>(
        &usd_box,
        0,
        INITIAL_AMOUNT - 40,
        UNLOCK_START_AT_SEC,
        UNLOCK_PER_SEC,
        UNLOCK_START_AT_SEC + 3,
        200,
        INITIAL_AMOUNT ,
        40
    );


    test_utils::destroy(usd_box);
    test_utils::destroy(withdrawn_balance3);

    sc0.end();
}

// Test change unlock start time
#[test]
fun test_change_unlock_start_ts_sec_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    let mut usd_box = create_time_locked_box_for_testing<USD>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());

    common_tests::increase_clock_for_testing(sc, UNLOCK_START_AT_SEC, alice());

    let new_start_sec = 200;
    change_unlock_start_sec_for_testing(sc, &mut usd_box, 200, alice());

    check_time_locked_box_values<USD>(
        &usd_box,
        UNLOCK_PER_SEC,
        INITIAL_AMOUNT - UNLOCK_PER_SEC,
        new_start_sec,
        UNLOCK_PER_SEC,
        new_start_sec - 1,
        INITIAL_AMOUNT / UNLOCK_PER_SEC + new_start_sec - 1,
        INITIAL_AMOUNT,
        UNLOCK_PER_SEC
    );
    
    test_utils::destroy(usd_box);

    sc0.end();
}

#[test]
fun test_max_withdrawable_amount_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    let usd_box = create_time_locked_box_for_testing<USD>(
        sc, 
        INITIAL_AMOUNT, 
        UNLOCK_START_AT_SEC, 
        UNLOCK_PER_SEC, 
        alice());

    let max_withdrawable_amount1 = get_max_withdrawable_amount(sc, &usd_box, alice());

    assert_eq(max_withdrawable_amount1, 0);

    common_tests::increase_clock_for_testing(sc, UNLOCK_START_AT_SEC - 1, alice());

    let max_withdrawable_amount2 = get_max_withdrawable_amount(sc, &usd_box, alice());

    assert_eq(max_withdrawable_amount2, 0);

    common_tests::increase_clock_for_testing(sc, 1, alice());

    let max_withdrawable_amount3 = get_max_withdrawable_amount(sc, &usd_box, alice());

    assert_eq(max_withdrawable_amount3, 10);

    common_tests::increase_clock_for_testing(sc, 10, alice());

    let max_withdrawable_amount4 = get_max_withdrawable_amount(sc, &usd_box, alice());

    assert_eq(max_withdrawable_amount4, 110);
    
    
    test_utils::destroy(usd_box);

    sc0.end();
}

// TODO:
#[test]
fun test_withdraw_after_unlock_end_should_work() {

}
