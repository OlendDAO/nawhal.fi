
module nawhal::time_locked_box;

use sui::balance::{Self, Balance};
use sui::clock::Clock;

/// ------ Errors ------ ///
const EInvalidUnlockPerSec: u64 = 1;
const EInvalidUnlockTimestamp: u64 = 2;
const ELockedBalanceLessThanUnlockableAmount: u64 = 3;
const EAccumulatedAmountInvalid: u64 = 4;

/// ------ Structs ------ ///
public struct TimeLockedBox<phantom T> has store {
    // the time when the balance will start to be unlocked
    unlock_start_at_sec: u64,
    // the time when the balance will be unlocked and withdrawable
    unlock_end_at_sec: u64,
    // the amount of balance that will be unlocked per second
    unlock_per_sec: u64,
    // the time when the last balance was unlocked
    previous_unlocked_at_sec: u64,
    // the balance that is locked, 
    // it will be unlocked after the unlock_start_at_sec
    locked_balance: Balance<T>,
    // the balance that is unlocked
    unlocked_balance: Balance<T>,
    // Accumulated amount of dposited balance
    accumulated_total_amount: u64,
    // Accumulated amount of unlocked balance
    accumulated_unlocked_amount: u64,
}

// ------ Functions ------ //
public fun new<T>(
    locked_balance: Balance<T>,
    unlock_start_at_sec: u64,
    unlock_per_sec: u64,
): TimeLockedBox<T> {
    let unlock_period_sec = calculate_unlock_period_at_sec(
        locked_balance.value(),
        unlock_per_sec,
    );

    let accumulated_total_amount = locked_balance.value();

    TimeLockedBox {
        locked_balance,
        unlock_start_at_sec,
        unlock_end_at_sec: unlock_start_at_sec + unlock_period_sec,
        unlock_per_sec,
        previous_unlocked_at_sec: unlock_start_at_sec - 1,
        unlocked_balance: balance::zero(),
        accumulated_total_amount,
        accumulated_unlocked_amount: 0,
    }
}

// ------ Mutations ------ //
/// Deposit additional balance to distribute to the time locked balance.
/// Abort if the timestamp is before the unlock start time or before the previous unlocked time.
public fun deposit<T>(
    self: &mut TimeLockedBox<T>,
    additional_balance: Balance<T>,
) {
    let additional_amount = additional_balance.value();
    self.locked_balance.join(additional_balance);

    self.unlock_end_at_sec = self.unlock_start_at_sec + calculate_unlock_period_at_sec(
        self.locked_balance.value(),
        self.unlock_per_sec,
    );

    self.accumulated_total_amount = self.accumulated_total_amount + additional_amount;

    check_accumulated_amount_is_valid(self);
}

/// Withdraw specified amount from the unlocked balance, 
/// Abort if the amount is more than the unlocked balance,
public fun withdraw<T>(
    self: &mut TimeLockedBox<T>,
    amount: u64,
    clock: &Clock,
): Balance<T> {
    unlock(self, clock.timestamp_ms() / 1000);

    let withdraw_balance = self.unlocked_balance.split(amount);

    check_accumulated_amount_is_valid(self);

    withdraw_balance
}

/// Change the unlock per second if necessary.
/// Abort if the new unlock per second is not positive.
public fun change_unlock_per_sec<T>(
    self: &mut TimeLockedBox<T>,
    new_unlock_per_sec: u64,
) {
    check_unlock_per_sec_must_be_positive(new_unlock_per_sec);

    self.unlock_per_sec = new_unlock_per_sec;
}

/// Unlocks the balance that is unlockable based on the time passed since previous unlock.
/// Moves the amount from `locked_balance` to `unlocked_balance`.
fun unlock<T>(
    self: &mut TimeLockedBox<T>,
    timestamp_sec: u64,
) {
    
    check_unlock_timestamp_is_more_than_start_at_and_previous_unlocked_at(self, timestamp_sec);

    let unlockable_amount = calculate_unlockable_amount(self, timestamp_sec);

    check_locked_balance_more_than_unlockable_amount(self, unlockable_amount);

    self.unlocked_balance.join(self.locked_balance.split(unlockable_amount));
    
    self.previous_unlocked_at_sec = timestamp_sec;
    self.accumulated_unlocked_amount = self.accumulated_unlocked_amount + unlockable_amount;

    check_accumulated_amount_is_valid(self);
}

// ------ Getters ------ //
public fun unlock_start_at_sec<T>(
    self: &TimeLockedBox<T>,
): u64 {
    self.unlock_start_at_sec
}

public fun unlock_end_at_sec<T>(
    self: &TimeLockedBox<T>,
): u64 {
    self.unlock_end_at_sec
}

public fun unlock_per_sec<T>(
    self: &TimeLockedBox<T>,
): u64 {
    self.unlock_per_sec
}

public fun previous_unlocked_at_sec<T>(
    self: &TimeLockedBox<T>,
): u64 {
    self.previous_unlocked_at_sec
}

public fun locked_unlocked_balance_values<T>(
    self: &TimeLockedBox<T>,
): (u64, u64) {
    (self.locked_balance.value(), self.unlocked_balance.value())
}

public fun accumulated_amount_values<T>(
    self: &TimeLockedBox<T>,
): (u64, u64) {
    (self.accumulated_total_amount, self.accumulated_unlocked_amount)
}



// ------ Reads ------ //

/// Returns the value of extraneous balance.
/// Since `locked_balance` amount might not be evenly divisible by `unlock_per_sec`, there will
/// be some
/// extraneous balance. E.g. if `locked_balance` is 21 and `unlock_per_sec` is 10, this function
/// will
/// return 1. Extraneous balance can be withdrawn by calling `skim_extraneous_balance` at any time.
/// When `unlock_per_sec` is 0, all balance in `locked_balance` is considered extraneous. This
/// makes it possible to empty the `locked_balance` by setting `unlock_per_second` to 0 and then skimming.
public fun extraneous_locked_amount<T>(self: &TimeLockedBox<T>): u64 {
    balance::value(&self.locked_balance) % self.unlock_per_sec
}

/// Returns the max available amount that can be withdrawn with given timestamp.
public fun max_withdrawable_amount<T>(self: &TimeLockedBox<T>, timestamp_sec: u64): u64 {
    self.unlocked_balance.value() + calculate_unlockable_amount(self, timestamp_sec)
}

// ------ Helpers ------ //
/// Calculate the unlock period at given amount to issue and unlock per second.
fun calculate_unlock_period_at_sec(
    amount_to_issue: u64,
    unlock_per_sec: u64,
): u64 {
    check_unlock_per_sec_must_be_positive(unlock_per_sec);

    if (amount_to_issue == 0) {
        0
    } else if (amount_to_issue % unlock_per_sec == 0) {
        amount_to_issue / unlock_per_sec
    } else {
        amount_to_issue / unlock_per_sec + 1
    }
}

/// Calculate the unlockable amount at given timestamp.
/// Return 0 if the timestamp is before the unlock start time. 
/// Or return the total amount of locked balance value if the timestamp is after the unlock end time.
/// Otherwise, return the amount of unlockable balance at the given timestamp.
fun calculate_unlockable_amount<T>(self: &TimeLockedBox<T>, timestamp_sec: u64): u64 {
    if (timestamp_sec < self.unlock_start_at_sec || timestamp_sec <= self.previous_unlocked_at_sec) {
        0
    } else if (timestamp_sec >= self.unlock_end_at_sec) {
        self.locked_balance.value()
    } else {
        (timestamp_sec - self.previous_unlocked_at_sec) * self.unlock_per_sec
    }
}

// ------ Checks ------ //
/// Check that the unlock per second is positive.
public fun check_unlock_per_sec_must_be_positive(
    unlock_per_sec: u64,
) {
    assert!(unlock_per_sec > 0, EInvalidUnlockPerSec);
}

/// Check the unlock time is valid
public fun check_unlock_timestamp_is_more_than_start_at_and_previous_unlocked_at<T>(self: &TimeLockedBox<T>, unlock_ts_sec: u64) {
    assert!(
        self.unlock_start_at_sec <= unlock_ts_sec && unlock_ts_sec >= self.previous_unlocked_at_sec,
        EInvalidUnlockTimestamp
    );
}

/// Check that the locked balance is more than the unlockable amount
public fun check_locked_balance_more_than_unlockable_amount<T>(self: &TimeLockedBox<T>, unlockable_amount: u64) {
    assert!(self.locked_balance.value() >= unlockable_amount, ELockedBalanceLessThanUnlockableAmount);
}

/// Check that the accumulated amount is valid, the accumulated total amount should be always equal 
/// the sum of the accumulated unlocked amount and the locked balance value
public fun check_accumulated_amount_is_valid<T>(self: &TimeLockedBox<T>) {
    assert!(self.accumulated_total_amount == self.accumulated_unlocked_amount + self.locked_balance.value(), EAccumulatedAmountInvalid);
}

#[test_only]
public fun destroy_for_testing<T>(self: TimeLockedBox<T>) {
    let TimeLockedBox { locked_balance, unlock_start_at_sec:_, unlock_end_at_sec:_, unlock_per_sec:_, previous_unlocked_at_sec:_, unlocked_balance, accumulated_total_amount:_, accumulated_unlocked_amount:_ } = self;
    balance::destroy_for_testing(locked_balance);
    balance::destroy_for_testing(unlocked_balance);
}

#[test_only]
public struct USD has drop {}

#[test]
fun test_calc_unlock_period_sec_should_work() {
    assert!(calculate_unlock_period_at_sec(30, 20) == 2, 0);
    assert!(calculate_unlock_period_at_sec(60, 30) == 2, 0);
    assert!(calculate_unlock_period_at_sec(29, 30) == 1, 0);
    assert!(calculate_unlock_period_at_sec(30, 30) == 1, 0);
    assert!(calculate_unlock_period_at_sec(0, 20) == 0, 0);
}

#[test, expected_failure(abort_code = EInvalidUnlockPerSec)]
fun test_check_unlock_per_sec_must_be_positive_should_fail() {
    check_unlock_per_sec_must_be_positive(0);
}

#[test, expected_failure(abort_code = EInvalidUnlockPerSec)]
fun test_calculate_unlock_period_at_sec_with_zero_should_fail() {
    assert!(calculate_unlock_period_at_sec(0, 0) == 0, 0);
}

#[test, expected_failure(abort_code = ::nawhal::time_locked_box::EInvalidUnlockPerSec)]
fun test_create_box_with_unlock_per_sec_of_zero() {
    let box = new(balance::create_for_testing<USD>(1000), 100, 0);

    destroy_for_testing(box);
}

#[test]
fun test_change_unlock_per_sec_should_work() {
    let mut box = new(balance::create_for_testing<USD>(1000), 100, 10);
    assert!(box.unlock_per_sec() == 10, 0);

    change_unlock_per_sec(&mut box, 20);
    assert!(box.unlock_per_sec() == 20, 0);

    destroy_for_testing(box);
}

#[test, expected_failure(abort_code = ::nawhal::time_locked_box::EInvalidUnlockPerSec)]
fun test_change_unlock_per_sec_with_zero_should_fail() {
    let mut box = new(balance::create_for_testing<USD>(1000), 100, 10);
    assert!(box.unlock_per_sec() == 10, 0);

    change_unlock_per_sec(&mut box, 0);

    destroy_for_testing(box);
}

#[test]
fun test_extraneous_locked_amount_should_work() {
    let box = new(balance::create_for_testing<USD>(1000), 100, 10);
    
    assert!(extraneous_locked_amount(&box) == 0, 0);

    destroy_for_testing(box);

    let box = new(balance::create_for_testing<USD>(1002), 100, 10);
    assert!(extraneous_locked_amount(&box) == 2, 0);

    destroy_for_testing(box);
}

/// Test getters
#[test]
fun test_getters() {
    let box = new(balance::create_for_testing<USD>(30000), 200, 100);
    assert!(box.unlock_per_sec() == 100, 0);
    assert!(box.unlock_start_at_sec() == 200, 0);
    assert!(box.unlock_end_at_sec() == 500, 0);
    assert!(box.previous_unlocked_at_sec() == 199, 0);

    let (locked_balance, unlocked_balance) = box.locked_unlocked_balance_values();
    assert!(locked_balance == 30000, 0);
    assert!(unlocked_balance == 0, 0);

    let (accumulated_total_amount, accumulated_unlocked_amount) = box.accumulated_amount_values();
    assert!(accumulated_total_amount == 30000, 0);
    assert!(accumulated_unlocked_amount == 0, 0);

    let box2 = new(balance::create_for_testing<USD>(30005), 200, 100);
    assert!(box2.unlock_per_sec() == 100, 0);
    assert!(box2.unlock_start_at_sec() == 200, 0);
    assert!(box2.unlock_end_at_sec() == 501, 0);
    assert!(box2.previous_unlocked_at_sec() == 199, 0);
    
    box.destroy_for_testing();
    box2.destroy_for_testing();
}   



