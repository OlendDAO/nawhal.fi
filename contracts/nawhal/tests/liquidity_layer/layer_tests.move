#[test_only]
module narval::layer_tests;

use sui::balance::Balance;
use sui::coin;
use sui::clock::Clock;


use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::{Self as tu};

use narval::admin::AdminCap;
use narval::liquidity::{Self, LiquidityLayer, Status};
use narval::protocol;
use narval::common_tests::{Self, alice, TBTC, TSUI};
use narval::common::YieldToken;

#[test]
fun test_liquidity_layer_main_flow_should_work() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    common_tests::init_account_registry_for_testing(sc, alice());
    common_tests::init_ytbtc_and_ytsui_for_testing(sc, alice());

    common_tests::init_liquidity_layer_for_testing(sc, alice());

    // Register a new asset type
    common_tests::register_asset_vault_for_testing<TSUI>(sc, alice()); 

    // Check if the asset type is registered
    check_liquidity_layer_status(sc, liquidity::new_active_status(), alice());

    check_asset_vault_balance<TSUI>(sc, 0, alice());

    // Register a new protocol
    let protocol_uid = object::new(sc.ctx());
    let protocol_id = object::uid_to_inner(&protocol_uid);
    
    // Deposit liquidity
    common_tests::register_asset_vault_for_testing<TBTC>(sc, alice());
    register_protocol(sc, protocol_id, alice());

    check_protocol_registered(sc, protocol_id, alice());

    let deposit_payload = coin::mint_for_testing<TBTC>(1_000_000_000, sc.ctx());

    let yt = deposit_liquidity<TBTC>(sc, protocol_id, deposit_payload.into_balance(), alice());
    
    // std::debug::print(&yt);

    check_asset_vault_balance<TBTC>(sc, 1_000_000_000, alice());

    // Withdraw liquidity
    let withdraw_amount = yt.value();
    // let withdraw_shares = coin::mint_for_testing<YTBTC>(withdraw_amount, sc.ctx()).into_balance();
    let withdrawn_balance = withdraw_liquidity<TBTC>(sc, protocol_id, yt, alice());

    // assert!(withdrawn_balance.value() == withdraw_amount, 0);

    check_asset_vault_balance<TBTC>(sc, 1_000_000_000 - withdraw_amount, alice());

    tu::destroy(protocol_uid);
    tu::destroy(withdrawn_balance);

    sc0.end();
}

// Test Register Asset Vault
#[test]
fun test_register_liquidity_vault_should_work() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    common_tests::init_account_registry_for_testing(sc, alice());
    common_tests::init_ytbtc_and_ytsui_for_testing(sc, alice());

    init_liquidity_layer_for_testing(sc, alice());

    register_asset_vault_for_testing<TSUI>(sc, alice());

    check_asset_vault_balance<TSUI>(sc, 0, alice());

    sc0.end();
}

// Register a new protocol
fun register_protocol(sc: &mut Scenario, protocol_id: ID, sender: address) {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let admin_cap = sc.take_from_sender<AdminCap>();

    liquidity::register_protocol_by_admin_cap(&mut layer, &admin_cap, protocol_id, protocol::new_lending_protocol_type(), sc.ctx());

    ts::return_shared(layer);
    sc.return_to_sender(admin_cap);
}

// Deposit liquidity
fun deposit_liquidity<T>(sc: &mut Scenario, protocol_id: ID, payload: Balance<T>, sender: address): Balance<YieldToken<T>> {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let clock = sc.take_shared<Clock>();

    let yt = liquidity::deposit<T>(&mut layer, protocol_id, payload, &clock, sc.ctx());

    ts::return_shared(layer);
    ts::return_shared(clock);

    yt
}

// Withdraw liquidity
fun withdraw_liquidity<T>(sc: &mut Scenario, protocol_id: ID, shares: Balance<YieldToken<T>>, sender: address): Balance<T> {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let clock = sc.take_shared<Clock>();

    let withdrawn_balance = liquidity::withdraw<T>(&mut layer, protocol_id, shares, &clock, sc.ctx());

    ts::return_shared(layer);
    ts::return_shared(clock);
    withdrawn_balance
}   

// --- Check helpers --- //
// Check the liquidity layer status
fun check_liquidity_layer_status(sc: &mut Scenario, exptected_status: Status, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();

    assert!(layer.status() == exptected_status, 0);

    ts::return_shared(layer);
}

// Check the asset vault balance
fun check_asset_vault_balance<T>(
    sc: &mut Scenario, 
    expected_vault_balance: u64,
    sender: address
) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();
    
    let balance_value = layer.vault_available_balance<T>();

    assert!(balance_value == expected_vault_balance, 0);

    ts::return_shared(layer);
}

// Check the protocol registered
fun check_protocol_registered(sc: &mut Scenario, protocol_id: ID, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();

    assert!(layer.contains_protocol(&protocol_id), 0);

    ts::return_shared(layer);
}

// initialize a new LiquidityLayer for testing
public fun init_liquidity_layer_for_testing(sc: &mut Scenario, sender: address) {
    sc.next_tx(sender);

    liquidity::init_for_testing(sc.ctx());
}

// Register an asset vault in LiquidityLayer for testing
public fun register_asset_vault_for_testing<T>(sc: &mut Scenario, sender: address) {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let admin_cap = sc.take_from_sender<AdminCap>();
    let vault_cap = liquidity::register_vault_by_admin_cap<T>(&mut layer, &admin_cap, sc.ctx());

    ts::return_shared(layer);
    sc.return_to_sender(admin_cap);
    transfer::public_transfer(vault_cap, sender);
}