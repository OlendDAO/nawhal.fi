#[test_only]
module narval::lending_protocol_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::{Self as tu};
use sui::coin;
use sui::balance::Balance;
use sui::clock::Clock;

use narval::lending_protocol::{Self, LendingProtocol};
use narval::liquidity::{LiquidityLayer};
use narval::admin::AdminCap;
use narval::account_ds::{AccountRegistry, AccountProfileCap};

use sui::test_utils::assert_eq;

use narval::common_tests::{Self as ct, alice, TBTC, TSUI};

// === Helper Functions ===

// Setup: Initializes LiquidityLayer, AccountRegistry, and registers the LendingProtocol
// Returns the ID of the registered LendingProtocol<T>
fun setup_lending_protocol<T>(sc: &mut Scenario, sender: address, supply_cap: u64): ID {
    sc.next_tx(sender);
    let mut layer = sc.take_shared<LiquidityLayer>();
    let admin_cap = sc.take_from_sender<AdminCap>();

    // Call the combined registration function which returns the ID
    let protocol_id = lending_protocol::register_lending_protocol<T>(&mut layer, &admin_cap, supply_cap, sc.ctx());

    ts::return_shared(layer);
    sc.return_to_sender(admin_cap);
    protocol_id // Return the ID
}

// Deposit Helper: Mints coin and performs deposit
fun deposit_helper<T>(sc: &mut Scenario, protocol_id: ID, amount: u64, sender: address) {
    let deposit_coin = coin::mint_for_testing<T>(amount, sc.ctx());

    sc.next_tx(sender);
    let mut protocol = sc.take_shared_by_id<LendingProtocol<T>>(protocol_id);
    let mut layer = sc.take_shared<LiquidityLayer>();
    let mut registry = sc.take_shared<AccountRegistry>();
    let clock = sc.take_shared<Clock>();
    
    lending_protocol::deposit<T>(&mut protocol, &mut layer, &mut registry, deposit_coin, &clock, sc.ctx());

    ts::return_shared(protocol);
    ts::return_shared(layer);
    ts::return_shared(registry);
    ts::return_shared(clock);
}

// Withdraw Helper: Performs withdraw operation
fun withdraw_helper<T>(
    sc: &mut Scenario, 
    protocol_id: ID,
    amount: u64, 
    sender: address
): Balance<T> {
    sc.next_tx(sender);
    let mut protocol = sc.take_shared_by_id<LendingProtocol<T>>(protocol_id);
    let mut layer = sc.take_shared<LiquidityLayer>();
    let mut registry = sc.take_shared<AccountRegistry>();
    let profile_cap = sc.take_from_sender<AccountProfileCap>();
    let clock = sc.take_shared<Clock>();

    let withdrawn_balance = lending_protocol::withdraw<T>(
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
fun check_state_after_op<T>(
    sc: &mut Scenario, 
    protocol_id: ID,
    expected_layer_balance: u64, 
    expected_profile_stake: u64,
    sender: address
) {
    // Check Liquidity Layer state
    sc.next_tx(sender);
    let layer = sc.take_shared<LiquidityLayer>();

    assert_eq(layer.vault_available_balance<T>(), expected_layer_balance);
    
    // Check protocol amount using the known protocol ID
    let protocol = sc.take_shared_by_id<LendingProtocol<T>>(protocol_id);
    // let actual_protocol_id = protocol_obj.protocol_id();
    // assert!(actual_protocol_id == protocol_id, 99); // Sanity check

    assert_eq(layer.get_protocol_amount(&protocol_id), expected_layer_balance); 

    ts::return_shared(layer);
    // ts::return_shared(protocol_obj); // Not needed when taking by ID

    // Check Account Registry state
    sc.next_tx(sender);

    let registry = sc.take_shared<AccountRegistry>();
    let profile_cap = sc.take_from_sender<AccountProfileCap>();
    
    assert_eq(protocol.staking_total_amount<T>(profile_cap.account_of()), expected_profile_stake);
    
    sc.return_to_sender(profile_cap);
    ts::return_shared(registry);
    ts::return_shared(protocol); // Not needed when taking by ID
}

// === Test Functions ===

#[test]
/// Test depositing assets into the lending protocol
fun test_lending_protocol_deposit() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    ct::create_clock_and_share(sc);
    ct::init_ytbtc_and_ytsui_for_testing(sc, alice());
    ct::init_liquidity_layer_for_testing(sc, alice());
    ct::register_asset_vault_for_testing<TBTC>(sc, alice());
    ct::init_account_registry_for_testing(sc, alice());

    let btc_protocol_id = setup_lending_protocol<TBTC>(sc, alice(), 1_000_000_000_000_000_000);

    let deposit_amount = 1_000_000_000;
    deposit_helper<TBTC>(sc, btc_protocol_id, deposit_amount, alice());

    check_state_after_op<TBTC>(sc, btc_protocol_id, deposit_amount, deposit_amount, alice());

    sc0.end();
}

/// Test multiple deposits and withdrawals with multiple Coin types(TSUI, YTSUI), and (TBTC, YTBTC)
#[test]
fun test_multiple_deposits_and_withdrawals() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;
    let alice_addr = alice();

    // --- Setup ---
    ct::create_clock_and_share(sc);
    // Initialize core infrastructure
    ct::init_liquidity_layer_for_testing(sc, alice_addr);
    ct::init_account_registry_for_testing(sc, alice_addr);
    // Initialize yield token modules (important to do this *before* vault registration which takes TreasuryCaps)
    ct::init_ytbtc_and_ytsui_for_testing(sc, alice_addr);

    ct::register_asset_vault_for_testing<TBTC>(sc, alice_addr);
    ct::register_asset_vault_for_testing<TSUI>(sc, alice_addr);

    // Register lending protocols for both assets and store their IDs
    // These calls will internally register vaults first, then the protocol.
    // Ensure Alice has AdminCap and necessary TreasuryCaps before these calls.
    // Assuming init_ytbtc_and_ytsui_for_testing provides TreasuryCaps implicitly to sender.
    let btc_protocol_id = setup_lending_protocol<TBTC>(sc, alice_addr, 1_000_000_000_000_000_000); // 1e18 cap for BTC
    let sui_protocol_id = setup_lending_protocol<TSUI>(sc, alice_addr, 5_000_000_000_000_000_000); // 5e18 cap for SUI

    // --- Operations ---
    // 1. Deposit TBTC
    let deposit_btc_1 = 1_000_000_000; // 1 BTC (assuming 9 decimals for TBTC)
    deposit_helper<TBTC>(sc, btc_protocol_id, deposit_btc_1, alice_addr);
    check_state_after_op<TBTC>(sc, btc_protocol_id, deposit_btc_1, deposit_btc_1, alice_addr);

    // 2. Deposit TSUI
    let deposit_sui_1 = 5_000_000_000; // 5 SUI (assuming 9 decimals for TSUI)
    deposit_helper<TSUI>(sc, sui_protocol_id, deposit_sui_1, alice_addr);
    check_state_after_op<TSUI>(sc, sui_protocol_id, deposit_sui_1, deposit_sui_1, alice_addr);
    // Re-check BTC state (should be unchanged)
    check_state_after_op<TBTC>(sc, btc_protocol_id, deposit_btc_1, deposit_btc_1, alice_addr);

    // 3. Withdraw half TBTC
    let withdraw_btc_1 = deposit_btc_1 / 2;
    let withdrawn_btc_balance = withdraw_helper<TBTC>(sc, btc_protocol_id, withdraw_btc_1, alice_addr);
    assert_eq(withdrawn_btc_balance.value(), withdraw_btc_1);
    let expected_btc_remaining = deposit_btc_1 - withdraw_btc_1;
    check_state_after_op<TBTC>(sc, btc_protocol_id, expected_btc_remaining, expected_btc_remaining, alice_addr);
    tu::destroy(withdrawn_btc_balance); // Clean up withdrawn balance

    // 4. Deposit more TSUI
    let deposit_sui_2 = 2_000_000_000; // 2 SUI
    deposit_helper<TSUI>(sc, sui_protocol_id, deposit_sui_2, alice_addr);
    let expected_sui_total = deposit_sui_1 + deposit_sui_2;
    check_state_after_op<TSUI>(sc, sui_protocol_id, expected_sui_total, expected_sui_total, alice_addr);

    // 5. Withdraw all TSUI
    let withdrawn_sui_balance = withdraw_helper<TSUI>(sc, sui_protocol_id, expected_sui_total, alice_addr);
    assert_eq(withdrawn_sui_balance.value(), expected_sui_total);
    check_state_after_op<TSUI>(sc, sui_protocol_id, 0, 0, alice_addr); // Should be 0 SUI left
    tu::destroy(withdrawn_sui_balance); // Clean up withdrawn balance

    // 6. Withdraw remaining TBTC
    let withdrawn_btc_balance_2 = withdraw_helper<TBTC>(sc, btc_protocol_id, expected_btc_remaining, alice_addr);
    assert_eq(withdrawn_btc_balance_2.value(), expected_btc_remaining);
    check_state_after_op<TBTC>(sc, btc_protocol_id, 0, 0, alice_addr); // Should be 0 BTC left
    tu::destroy(withdrawn_btc_balance_2); // Clean up withdrawn balance

    // --- Cleanup ---
    sc0.end();
}

#[test, expected_failure(abort_code = lending_protocol::EInsufficientBalance)]
/// Test withdrawing more assets than deposited
fun test_lending_protocol_withdraw_insufficient() {
    let mut sc0 = ts::begin(alice());
    let sc = &mut sc0;

    ct::create_clock_and_share(sc);
    ct::init_ytbtc_and_ytsui_for_testing(sc, alice());
    ct::init_liquidity_layer_for_testing(sc, alice());
    ct::register_asset_vault_for_testing<TBTC>(sc, alice());
    ct::init_account_registry_for_testing(sc, alice());

    let btc_protocol_id = setup_lending_protocol<TBTC>(sc, alice(), 1_000_000_000_000_000_000);

    let deposit_amount = 1_000_000_000;
    deposit_helper<TBTC>(sc, btc_protocol_id, deposit_amount, alice());

    // Alice tries to withdraw more than deposited
    let withdraw_amount = deposit_amount + 1;
    let withdrawn_balance = withdraw_helper<TBTC>(sc, btc_protocol_id, withdraw_amount, alice());

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
    ct::init_ytbtc_and_ytsui_for_testing(sc, alice());
    ct::init_liquidity_layer_for_testing(sc, alice());
    ct::register_asset_vault_for_testing<TBTC>(sc, alice());
    ct::init_account_registry_for_testing(sc, alice());

    let btc_protocol_id = setup_lending_protocol<TBTC>(sc, alice(), 1_000_000_000_000_000_000);
    
    let deposit_amount = 1_000_000_000_000_000_000 + 1;
    deposit_helper<TBTC>(sc, btc_protocol_id, deposit_amount, alice());
    
    sc0.end();
}