#[test_only]
module nawhal::lending_protocol_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::{Self as tu};
use sui::coin;
use sui::balance::Balance;
use sui::clock::Clock;

use nawhal::lending_protocol::{Self, LendingProtocol};
use nawhal::liquidity_layer_model::{LiquidityLayer};
use nawhal::admin::AdminCap;
use nawhal::account_ds::{AccountRegistry, AccountProfileCap};
use nawhal::ytbtc::YTBTC;

use sui::test_utils::assert_eq;

use nawhal::common_tests::{Self as ct, alice, TBTC};


// === Helper Functions ===

// Setup: Initializes LiquidityLayer, AccountRegistry, and registers the LendingProtocol
fun setup_lending_protocol<T, YT>(sc: &mut Scenario, sender: address, supply_cap: u64) {
    ct::create_clock_and_share(sc);
    ct::init_ytbtc_and_ytsui_for_testing(sc, sender);
    ct::init_liquidity_layer_for_testing(sc, sender);
    ct::register_asset_vault_for_testing<T, YT>(sc, sender);
    ct::init_account_registry_for_testing(sc, sender);

    sc.next_tx(sender);
    let mut layer = sc.take_shared<LiquidityLayer>();
    let admin_cap = sc.take_from_sender<AdminCap>();
    lending_protocol::register_lending_protocol<T>(&mut layer, &admin_cap, supply_cap, sc.ctx());
    ts::return_shared(layer);
    sc.return_to_sender(admin_cap);
}

// Deposit Helper: Mints coin and performs deposit
fun deposit_helper<T, YT>(sc: &mut Scenario, amount: u64, sender: address) {
    let deposit_coin = coin::mint_for_testing<T>(amount, sc.ctx());

    sc.next_tx(sender);
    let mut protocol = sc.take_shared<LendingProtocol<T>>();
    let mut layer = sc.take_shared<LiquidityLayer>();
    let mut registry = sc.take_shared<AccountRegistry>();
    let clock = sc.take_shared<Clock>();
    
    lending_protocol::deposit<T, YT>(&mut protocol, &mut layer, &mut registry, deposit_coin, &clock, sc.ctx());

    ts::return_shared(protocol);
    ts::return_shared(layer);
    ts::return_shared(registry);
    ts::return_shared(clock);
}

// Withdraw Helper: Performs withdraw operation
fun withdraw_helper<T, YT>(
    sc: &mut Scenario, 
    amount: u64, 
    sender: address
): Balance<T> {
    sc.next_tx(sender);
    let mut protocol = sc.take_shared<LendingProtocol<T>>();
    let mut layer = sc.take_shared<LiquidityLayer>();
    let mut registry = sc.take_shared<AccountRegistry>();
    let profile_cap = sc.take_from_sender<AccountProfileCap>();
    let clock = sc.take_shared<Clock>();

    let withdrawn_balance = lending_protocol::withdraw<T, YT>(
        &mut protocol, &mut layer, &mut registry, &profile_cap, amount, &clock, sc.ctx()
    );

    ts::return_shared(protocol);
    ts::return_shared(layer);
    ts::return_shared(registry);
    sc.return_to_sender(profile_cap);
    ts::return_shared(clock);
    
    withdrawn_balance
}

// Check State Helper: Verifies balances in LiquidityLayer and AccountRegistry
fun check_state_after_op<T, YT>(
    sc: &mut Scenario, 
    expected_layer_balance: u64, 
    expected_profile_stake: u64,
    sender: address
) {
    // Check Liquidity Layer state
    sc.next_tx(sender);
    let layer = sc.take_shared<LiquidityLayer>();

    assert_eq(layer.vault_cash_balance<T, YT>(), expected_layer_balance);
    let protocol_obj = sc.take_shared<LendingProtocol<T>>();
    let protocol_id = protocol_obj.protocol_id();

    assert_eq(layer.get_protocol_amount(&protocol_id), expected_layer_balance); 

    ts::return_shared(layer);
    ts::return_shared(protocol_obj);

    // Check Account Registry state
    sc.next_tx(sender);

    let mut registry = sc.take_shared<AccountRegistry>();
    let profile_cap = sc.take_from_sender<AccountProfileCap>();
    let profile = registry.borrow_account_mut(profile_cap.account_of());
    let protocol_obj = sc.take_shared<LendingProtocol<T>>(); // Take again as it was returned
    let protocol_id = protocol_obj.protocol_id(); // Get ID here
    
    assert_eq(profile.stake_total_amount<T, YT>(protocol_id), expected_profile_stake);
    
    sc.return_to_sender(profile_cap);
    ts::return_shared(registry);
    ts::return_shared(protocol_obj); // protocol_obj not taken if assert is commented out
}

// === Test Functions ===

#[test]
/// Test depositing assets into the lending protocol
fun test_lending_protocol_deposit() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    ct::create_clock_and_share(sc);
    setup_lending_protocol<TBTC, YTBTC>(sc, alice(), 1_000_000_000_000_000_000);

    let deposit_amount = 1_000_000_000;
    deposit_helper<TBTC, YTBTC>(sc, deposit_amount, alice());

    check_state_after_op<TBTC, YTBTC>(sc, deposit_amount, deposit_amount, alice());

    sc0.end();
}

#[test]
/// Test withdrawing assets from the lending protocol
fun test_lending_protocol_withdraw() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    ct::create_clock_and_share(sc);
    setup_lending_protocol<TBTC, YTBTC>(sc, alice(), 1_000_000_000_000_000_000);

    let deposit_amount = 1_000_000_000;
    deposit_helper<TBTC, YTBTC>(sc, deposit_amount, alice());

    check_state_after_op<TBTC, YTBTC>(sc, deposit_amount, deposit_amount, alice());

    // Alice withdraws half
    let withdraw_amount = deposit_amount / 2;
    let withdrawn_balance = withdraw_helper<TBTC, YTBTC>(sc, withdraw_amount, alice());

    assert_eq(withdrawn_balance.value(), withdraw_amount);

    let expected_remaining = deposit_amount - withdraw_amount;
    check_state_after_op<TBTC, YTBTC>(sc, expected_remaining, expected_remaining, alice());

    tu::destroy(withdrawn_balance);
    sc0.end();
}

#[test, expected_failure(abort_code = lending_protocol::EInsufficientBalance)]
/// Test withdrawing more assets than deposited
fun test_lending_protocol_withdraw_insufficient() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    ct::create_clock_and_share(sc);
    setup_lending_protocol<TBTC, YTBTC>(sc, alice(), 1_000_000_000_000_000_000);

    let deposit_amount = 1_000_000_000;
    deposit_helper<TBTC, YTBTC>(sc, deposit_amount, alice());

    // Alice tries to withdraw more than deposited
    let withdraw_amount = deposit_amount + 1;
    let withdrawn_balance = withdraw_helper<TBTC, YTBTC>(sc, withdraw_amount, alice());

    // Cleanup (will likely not be reached)
    tu::destroy(withdrawn_balance);
    sc0.end();
}

#[test, expected_failure(abort_code = lending_protocol::ESupplyCapReached)]
/// Test depositing more assets than the supply cap
fun test_lending_protocol_deposit_exceeds_supply_cap() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    ct::create_clock_and_share(sc);
    setup_lending_protocol<TBTC, YTBTC>(sc, alice(), 1_000_000_000_000_000_000);
    
    let deposit_amount = 1_000_000_000_000_000_000 + 1;
    deposit_helper<TBTC, YTBTC>(sc, deposit_amount, alice());
    
    sc0.end();
}