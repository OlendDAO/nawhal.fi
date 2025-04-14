
#[test_only]
module nawhal::liquidity_layer_tests;

use sui::balance::Balance;
use sui::coin;

use nawhal::liquidity_layer::{Self, LiquidityLayer, LiquidityStatus};

use sui::test_scenario::{Self as ts, Scenario};

use sui::test_utils::{Self as tu};

use nawhal::common_tests::{Self, alice, TSUI};

#[test]
fun test_liquidity_layer_main_flow_should_work() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    common_tests::init_liquidity_layer_for_testing(sc, alice());

    // Register a new asset type
    let payment = coin::mint_for_testing<TSUI>(1_000_000_000, sc.ctx());
    let payment_value = payment.value();

    register_asset_vault<TSUI>(sc, payment.into_balance(), alice());

    // Check if the asset type is registered
    check_liquidity_layer_status(sc, liquidity_layer::new_active_liquidity_status(), alice());

    check_asset_vault_registered<TSUI>(sc, payment_value, alice());

    // Check if the asset balance is 0
    sc0.end();
}

// Test Register Asset Vault
#[test]
fun test_register_liquidity_vault_should_work() {
    use sui::sui::SUI;
    use sui::balance;
    let mut ctx = tx_context::dummy();

    let mut layer = liquidity_layer::new_liquidity_layer(&mut ctx);

    let payload = balance::zero<SUI>();

    liquidity_layer::register_asset_vault(&mut layer, payload, &mut ctx);

    assert!(liquidity_layer::asset_amount(&layer) == 1, 0);

    tu::destroy(layer);
}

public fun register_asset_vault<T>(sc: &mut Scenario, payload: Balance<T>, sender: address) {
    sc.next_tx(sender);

    let mut layer = sc.take_shared<LiquidityLayer>();

    layer.register_asset_vault<T>(payload, sc.ctx());

    ts::return_shared(layer);
}

fun check_liquidity_layer_status(sc: &mut Scenario, exptected_status: LiquidityStatus, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();

    assert!(layer.layer_status() == exptected_status, 0);

    ts::return_shared(layer);
}

fun check_asset_vault_registered<T>(sc: &mut Scenario, expected_value: u64, sender: address) {
    sc.next_tx(sender);

    let layer = sc.take_shared<LiquidityLayer>();

    assert!(layer.get_asset_balance<T>() == expected_value, 0);

    ts::return_shared(layer);
}