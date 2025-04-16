
#[test_only]
module nawhal::liquidity_layer_tests;

use sui::balance::Balance;
use sui::coin;
use sui::clock::Clock;
use nawhal::liquidity_layer;
use nawhal::liquidity_layer_model::{Self,LiquidityLayer, LiquidityStatus};

use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::{Self as tu};

use nawhal::admin::AdminCap;

use nawhal::common_tests::{Self, alice, TBTC,TSUI};

#[test]
fun test_liquidity_layer_main_flow_should_work() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    common_tests::create_clock_and_share(sc);

    common_tests::init_liquidity_layer_for_testing(sc, alice());

    // Register a new asset type
    register_asset_vault<TSUI>(sc, alice()); 

    // Check if the asset type is registered
    check_liquidity_layer_status(sc, liquidity_layer_model::new_active_liquidity_status(), alice());

    check_asset_vault_balance<TSUI>(sc, 0, 0, 0, 0, 0, alice());

    // Register a new protocol
    let protocol_uid = object::new(sc.ctx());
    let protocol_id = object::uid_to_inner(&protocol_uid);
    
    // Deposit liquidity
    register_asset_vault<TBTC>(sc, alice());

    register_protocol<TBTC>(sc, protocol_id, alice());

    check_protocol_registered(sc, protocol_id, alice());

    let deposit_payload = coin::mint_for_testing<TBTC>(1_000_000_000, sc.ctx());

    deposit_liquidity(sc, protocol_id, deposit_payload.into_balance(), alice());
    
    check_asset_vault_balance<TBTC>(sc, 1_000_000_000, 1_000_000_000, 0, 1_000_000_000, 0, alice());

    // Withdraw liquidity
    let withdraw_amount = 500_000_000;
    let withdrawn_balance = withdraw_liquidity<TBTC>(sc, protocol_id, withdraw_amount, alice());

    assert!(withdrawn_balance.value() == withdraw_amount, 0);

    check_asset_vault_balance<TBTC>(sc, 1_000_000_000 - withdraw_amount, 1_000_000_000 - withdraw_amount, 0, 1_000_000_000, withdraw_amount, alice());

    tu::destroy(protocol_uid);
    tu::destroy(withdrawn_balance);

    sc0.end();
}

// Test Register Asset Vault
#[test]
fun test_register_liquidity_vault_should_work() {
    // use sui::sui::SUI;
    // use sui::balance;
    let mut ctx = tx_context::dummy();

    let mut layer = liquidity_layer_model::new_liquidity_layer(&mut ctx);

    liquidity_layer::register_asset_vault<TSUI>(&mut layer, &mut ctx);

    assert!(liquidity_layer_model::asset_type_amount(&layer) == 1, 0);

    tu::destroy(layer);
}

public fun register_asset_vault<T>(sc: &mut Scenario, sender: address) {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();

    liquidity_layer::register_asset_vault<T>(&mut layer, sc.ctx());

    ts::return_shared(layer);
}

// Register a new protocol
fun register_protocol<T>(sc: &mut Scenario, protocol_id: ID, sender: address) {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let admin_cap = sc.take_from_sender<AdminCap>();

    liquidity_layer::register_protocol<T>(&mut layer, &admin_cap, protocol_id, liquidity_layer_model::new_lending_protocol_type(), sc.ctx());

    ts::return_shared(layer);
    sc.return_to_sender(admin_cap);
}

// Deposit liquidity
fun deposit_liquidity<T>(sc: &mut Scenario, protocol_id: ID, payload: Balance<T>, sender: address) {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let clock = sc.take_shared<Clock>();

    liquidity_layer::deposit<T>(&mut layer, protocol_id, payload, &clock, sc.ctx());

    ts::return_shared(layer);
    ts::return_shared(clock);
}

// Withdraw liquidity
fun withdraw_liquidity<T>(sc: &mut Scenario, protocol_id: ID, amount: u64, sender: address): Balance<T> {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();
    let clock = sc.take_shared<Clock>();

    let withdrawn_balance = liquidity_layer::withdraw<T>(&mut layer, protocol_id, amount, &clock, sc.ctx());

    ts::return_shared(layer);
    ts::return_shared(clock);
    withdrawn_balance
}   

// --- Check helpers --- //
// Check the liquidity layer status
fun check_liquidity_layer_status(sc: &mut Scenario, exptected_status: LiquidityStatus, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();

    assert!(layer.layer_status() == exptected_status, 0);

    ts::return_shared(layer);
}

// Check the asset vault balance
fun check_asset_vault_balance<T>(sc: &mut Scenario, expected_cash_balance: u64, total_deposits: u64, total_collateral: u64, expected_total_in: u64, expected_total_out: u64, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();
    
    let balance_value = layer.vault_cash_balance<T>();

    assert!(balance_value == expected_cash_balance, 0);
    assert!(layer.total_deposits<T>() == total_deposits, 0);
    assert!(layer.total_collateral<T>() == total_collateral, 0);
    assert!(layer.total_in<T>() == expected_total_in, 0);
    assert!(layer.total_out<T>() == expected_total_out, 0);

    ts::return_shared(layer);
}

// Check the protocol registered
fun check_protocol_registered(sc: &mut Scenario, protocol_id: ID, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();

    assert!(layer.contains_protocol(&protocol_id), 0);

    ts::return_shared(layer);
}
