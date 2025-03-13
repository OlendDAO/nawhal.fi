#[test_only]
module nawhal::time_locked_box_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::balance::{Self, Balance};

use sui::sui::SUI;
use sui::clock::{Self, Clock};

use nawhal::time_locked_box::{Self, TimeLockedBox};

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

#[test]
fun new_time_locked_box_should_work() {
    
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
fun deposit_box_should_work() {
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
fun withdraw_should_work() {
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



// #[test]
// fun test_max_withdrawable_amount() {
//     let (time_locked_box, scenario) = create_time_locked_box();
    
//     // Test before unlock start time
//     let timestamp_before = UNLOCK_START_AT_SEC - 10;
//     assert_eq(time_locked_box::max_withdrawable_amount(&time_locked_box, timestamp_before), 0);
    
//     // Test during unlock period
//     let timestamp_during = UNLOCK_START_AT_SEC + 30;
//     assert_eq(time_locked_box::max_withdrawable_amount(&time_locked_box, timestamp_during), 30 * UNLOCK_PER_SEC);
    
//     // Test after unlock end time
//     let unlock_end = time_locked_box::unlock_end_at_sec(&time_locked_box);
//     let timestamp_after = unlock_end + 10;
//     assert_eq(time_locked_box::max_withdrawable_amount(&time_locked_box, timestamp_after), INITIAL_AMOUNT);
    
//     ts::end(scenario);
// }




// #[test]
// fun test_withdraw_after_unlock_end() {
//     let (mut time_locked_box, mut scenario) = create_time_locked_box();
    
//     // Calculate unlock end time
//     let unlock_end = time_locked_box::unlock_end_at_sec(&time_locked_box);
    
//     // Create a clock with timestamp after unlock end time
//     let timestamp_ms = (unlock_end + 10) * 1000;
//     ts::next_tx(&mut scenario, ADMIN);
//     let ctx = ts::ctx(&mut scenario);
//     let clock = clock::create_for_testing(ctx);
//     clock::set_for_testing(&mut clock, timestamp_ms);
    
//     // Withdraw all
//     let withdraw_balance = time_locked_box::withdraw(&mut time_locked_box, INITIAL_AMOUNT, &clock);
    
//     // Check withdrawn balance
//     assert_eq(balance::value(&withdraw_balance), INITIAL_AMOUNT);
    
//     // Check updated balance values
//     let (locked, unlocked) = time_locked_box::balance_values(&time_locked_box);
//     assert_eq(locked, 0);
//     assert_eq(unlocked, 0);
    
//     // Clean up
//     balance::destroy_for_testing(withdraw_balance);
//     clock::destroy_for_testing(clock);
//     ts::end(scenario);
// }

// #[test]
// fun test_getters() {
//     let (time_locked_box, scenario) = create_time_locked_box();
    
//     // Test all getter functions
//     assert_eq(time_locked_box::unlock_start_at_sec(&time_locked_box), UNLOCK_START_AT_SEC);
//     assert_eq(time_locked_box::unlock_per_sec(&time_locked_box), UNLOCK_PER_SEC);
//     assert_eq(time_locked_box::previous_unlocked_at_sec(&time_locked_box), 0);
    
//     // Calculate expected unlock end time
//     // Since we can't call the internal function directly, we'll calculate it ourselves
//     let expected_unlock_period = if (INITIAL_AMOUNT == 0) {
//         0
//     } else if (INITIAL_AMOUNT % UNLOCK_PER_SEC == 0) {
//         INITIAL_AMOUNT / UNLOCK_PER_SEC
//     } else {
//         INITIAL_AMOUNT / UNLOCK_PER_SEC + 1
//     };
//     let expected_unlock_end = UNLOCK_START_AT_SEC + expected_unlock_period;
//     assert_eq(time_locked_box::unlock_end_at_sec(&time_locked_box), expected_unlock_end);
    
//     ts::end(scenario);
// }

// #[test]
// fun test_check_functions() {
//     // Test check_unlock_per_sec_must_be_positive
//     time_locked_box::check_unlock_per_sec_must_be_positive(1);
//     time_locked_box::check_unlock_per_sec_must_be_positive(100);
    
//     // Create a time locked box for other checks
//     let balance = balance::create_for_testing<SUI>(INITIAL_AMOUNT);
//     let time_locked_box = time_locked_box::new(
//         balance,
//         UNLOCK_START_AT_SEC,
//         UNLOCK_PER_SEC
//     );
    
//     // Test check_unlock_timestamp_is_more_than_start_at_and_previous_unlocked_at
//     time_locked_box::check_unlock_timestamp_is_more_than_start_at_and_previous_unlocked_at(
//         &time_locked_box,
//         UNLOCK_START_AT_SEC + 1
//     );
    
//     // Test check_locked_balance_more_than_unlockable_amount
//     time_locked_box::check_locked_balance_more_than_unlockable_amount(
//         &time_locked_box,
//         INITIAL_AMOUNT
//     );
    
//     // Test check_accumulated_amount_is_valid
//     time_locked_box::check_accumulated_amount_is_valid(&time_locked_box);
// }

// #[test, expected_failure(abort_code = time_locked_box::EInvalidUnlockTimestamp)]
// fun test_check_unlock_timestamp_failure() {
//     let balance = balance::create_for_testing<SUI>(INITIAL_AMOUNT);
//     let time_locked_box = time_locked_box::new(
//         balance,
//         UNLOCK_START_AT_SEC,
//         UNLOCK_PER_SEC
//     );
    
//     // Should fail because timestamp is before unlock_start_at_sec
//     time_locked_box::check_unlock_timestamp_is_more_than_start_at_and_previous_unlocked_at(
//         &time_locked_box,
//         UNLOCK_START_AT_SEC - 1
//     );
// }

// #[test, expected_failure(abort_code = time_locked_box::ELockedBalanceLessThanUnlockableAmount)]
// fun test_check_locked_balance_failure() {
//     let balance = balance::create_for_testing<SUI>(INITIAL_AMOUNT);
//     let time_locked_box = time_locked_box::new(
//         balance,
//         UNLOCK_START_AT_SEC,
//         UNLOCK_PER_SEC
//     );
    
//     // Should fail because unlockable amount is more than locked balance
//     time_locked_box::check_locked_balance_more_than_unlockable_amount(
//         &time_locked_box,
//         INITIAL_AMOUNT + 1
//     );
// }

// // We can't directly test the internal calculate_unlock_period_at_sec function,
// // but we can test the behavior through the TimeLockedBox API
// #[test]
// fun test_unlock_period_calculation() {
//     // Test with amount divisible by unlock_per_sec
//     let balance1 = balance::create_for_testing<SUI>(60);
//     let time_locked_box1 = time_locked_box::new(
//         balance1,
//         UNLOCK_START_AT_SEC,
//         30
//     );
//     // Expected: 60/30 = 2
//     assert_eq(
//         time_locked_box::unlock_end_at_sec(&time_locked_box1) - UNLOCK_START_AT_SEC,
//         2
//     );
    
//     // Test with amount not divisible by unlock_per_sec
//     let balance2 = balance::create_for_testing<SUI>(29);
//     let time_locked_box2 = time_locked_box::new(
//         balance2,
//         UNLOCK_START_AT_SEC,
//         30
//     );
//     // Expected: 29/30 + 1 = 1
//     assert_eq(
//         time_locked_box::unlock_end_at_sec(&time_locked_box2) - UNLOCK_START_AT_SEC,
//         1
//     );
    
//     // Test with zero amount
//     let balance3 = balance::create_for_testing<SUI>(0);
//     let time_locked_box3 = time_locked_box::new(
//         balance3,
//         UNLOCK_START_AT_SEC,
//         20
//     );
//     // Expected: 0
//     assert_eq(
//         time_locked_box::unlock_end_at_sec(&time_locked_box3) - UNLOCK_START_AT_SEC,
//         0
//     );
// }

// #[test, expected_failure(abort_code = time_locked_box::EInvalidUnlockPerSec)]
// fun test_new_with_zero_unlock_per_sec() {
//     let balance = balance::create_for_testing<SUI>(100);
//     let time_locked_box = time_locked_box::new(
//         balance,
//         UNLOCK_START_AT_SEC,
//         0 // This should cause a failure
//     );
// }

