
#[test_only]

module nawhal::staking_tests;

use std::type_name;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin;

use nawhal::account;
use nawhal::account_ds::{AccountProfileCap, AccountRegistry};
use nawhal::staking::{Self, StakingRegistry};
use nawhal::vault::{Self, Vault};

use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::assert_eq;

use nawhal::common_tests::{Self, alice, LP_SUI, TSUI};

#[test]
fun deposit_and_withdraw_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    account::init_for_testing(sc.ctx());
    staking::init_for_testing(sc.ctx());

    common_tests::create_clock_and_share(sc);

    let _account_id = common_tests::register_user_for_testing(sc, option::none(), alice());

    create_vault_for_testing<TSUI, LP_SUI>(sc, option::some(1_000_000_000), alice());

    deposit_for_testing<TSUI, LP_SUI>(sc, 1_000_000_000, alice());

    check_staking_info<TSUI, LP_SUI>(sc, 1_000_000_000, alice());
    check_account_profile<TSUI, LP_SUI>(sc, 1_000_000_000, alice());

    let withdrawn_balance = withdraw_for_testing<TSUI, LP_SUI>(sc, 300_000_000, alice());

    assert_eq(withdrawn_balance.value(), 300_000_000);

    check_staking_info<TSUI, LP_SUI>(sc, 700_000_000, alice());
    check_account_profile<TSUI, LP_SUI>(sc, 700_000_000, alice());

    let withdrawn_balance2 = withdraw_for_testing<TSUI, LP_SUI>(sc, 700_000_000, alice());

    assert_eq(withdrawn_balance2.value(), 700_000_000);

    check_account_vault_not_exists_in_staking_registry<TSUI, LP_SUI>(sc, alice());
    check_staking_info_not_exists_in_account_profile<TSUI, LP_SUI>(sc, alice());

    withdrawn_balance.destroy_for_testing();
    withdrawn_balance2.destroy_for_testing();

    sc0.end();
}

fun deposit_for_testing<T, LPT>(sc: &mut Scenario, amount: u64, sender: address) {
    sc.next_tx(sender);
    let mut registry = sc.take_shared<StakingRegistry>();
    let clock = sc.take_shared<Clock>(); 
    let mut account_cap = sc.take_from_sender<AccountProfileCap>();
    let mut account_registry = sc.take_shared<AccountRegistry>();
    let mut vault = sc.take_shared<Vault<T, LPT>>();

    let payment = balance::create_for_testing<T>(amount);
    staking::deposit(&mut vault, &mut account_cap, &mut registry, &mut account_registry, payment, &clock, sc.ctx());

    ts::return_shared(vault);
    ts::return_shared(account_registry);
    ts::return_shared(clock);
    ts::return_shared(registry);
    sc.return_to_sender(account_cap);
}

fun withdraw_for_testing<T, LPT>(sc: &mut Scenario, amount: u64, sender: address): Balance<T> {
    sc.next_tx(sender);

    let mut registry = sc.take_shared<StakingRegistry>();
    let mut account_cap = sc.take_from_sender<AccountProfileCap>();
    let mut account_registry = sc.take_shared<AccountRegistry>();
    let mut vault = sc.take_shared<Vault<T, LPT>>();
    let clock = sc.take_shared<Clock>();
    let withdrawn_balance = staking::withdraw(&mut vault, &mut account_cap, &mut registry, &mut account_registry, amount, &clock, sc.ctx());

    ts::return_shared(vault);
    ts::return_shared(account_registry);
    ts::return_shared(clock);
    ts::return_shared(registry);
    sc.return_to_sender(account_cap);

    withdrawn_balance
}

fun create_vault_for_testing<T, LPT>(sc: &mut Scenario, tvl_cap: Option<u64>, sender: address) {
    sc.next_tx(sender);

    let lp_treasury = coin::create_treasury_cap_for_testing<LPT>(sc.ctx());
    let clock = sc.take_shared<Clock>();
    let vault_cap = vault::new_vault_and_share<T, LPT>(lp_treasury, b"test name".to_ascii_string(), b"test description".to_ascii_string(), tvl_cap, &clock, sc.ctx());

    transfer::public_transfer(vault_cap, sc.sender());

    ts::return_shared(clock);
}

fun check_staking_info<T, LPT>(sc: &mut Scenario, amount: u64, sender: address) {
    sc.next_tx(sender);

    let account_cap = sc.take_from_sender<AccountProfileCap>();
    let account_registry = sc.take_shared<AccountRegistry>();
    let vault = sc.take_shared<Vault<T, LPT>>();

    let account_id = account_cap.account_of();
    let profile = account_registry.borrow_account(account_id);
    
    let mut staking_info = profile.get_staking_info(&vault.vault_id());

    assert!(staking_info.is_some(), 0);

    let staking_info = staking_info.extract();

    assert_eq(staking_info.staking_value(), amount);
    assert_eq(staking_info.staking_type(), type_name::get<T>());

    ts::return_shared(account_registry);
    sc.return_to_sender(account_cap);
    ts::return_shared(vault);
}

fun check_account_profile<T, LPT>(sc: &mut Scenario, amount: u64, sender: address) {
    sc.next_tx(sender);

    let account_cap = sc.take_from_sender<AccountProfileCap>();
    let account_registry = sc.take_shared<AccountRegistry>();
    let vault = sc.take_shared<Vault<T, LPT>>();
    let account_id = account_cap.account_of();
    let profile = account_registry.borrow_account(account_id);
    
    assert_eq(profile.get_staking_info(&vault.vault_id()).extract().staking_value(), amount);

    ts::return_shared(account_registry);
    sc.return_to_sender(account_cap);
    ts::return_shared(vault);
}   

fun check_account_vault_not_exists_in_staking_registry<T, LPT>(
    sc: &mut Scenario,
    sender: address,
) {
    sc.next_tx(sender);

    let registry = sc.take_shared<StakingRegistry>();
    let account_cap = sc.take_from_sender<AccountProfileCap>();
    let account_id = account_cap.account_of();
    let vault = sc.take_shared<Vault<T, LPT>>();

    assert!(!registry.contains(&account_id, &vault.vault_id()), 0);

    ts::return_shared(registry);
    sc.return_to_sender(account_cap);
    ts::return_shared(vault);
}

fun check_staking_info_not_exists_in_account_profile<T, LPT>(
    sc: &mut Scenario,
    sender: address,
) {
    sc.next_tx(sender);

    let account_cap = sc.take_from_sender<AccountProfileCap>();
    let account_registry = sc.take_shared<AccountRegistry>();
    let vault = sc.take_shared<Vault<T, LPT>>();

    assert!(account_registry.borrow_account(account_cap.account_of()).get_staking_info(&vault.vault_id()).is_none(), 0);
    
    ts::return_shared(account_registry);
    sc.return_to_sender(account_cap);
    ts::return_shared(vault);
}