
#[test_only]
module nawhal::account_tests;

use std::ascii::String;

use nawhal::account;
use nawhal::account_ds::{AccountRegistry, AccountOwnerCap};
use sui::test_scenario::{Self as ts, Scenario};

use nawhal::common_tests::{Self, alice, bob};


#[test]
fun register_account_should_work() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    account::init_for_testing(sc.ctx());

    common_tests::register_user_for_testing(sc, option::none(), alice());

    check_account_exists(sc, alice().to_ascii_string(), alice());

    common_tests::register_user_for_testing(sc, option::some(b"bob".to_ascii_string()), bob());

    check_account_exists(sc, b"bob".to_ascii_string(), bob());

    sc0.end();
}

#[test, expected_failure(abort_code = ::nawhal::account_ds::EAccountAlreadyExists)]
fun registry_twice_should_fail() {
    let mut sc0 = ts::begin(alice());

    let sc = &mut sc0;

    account::init_for_testing(sc.ctx());

    common_tests::register_user_for_testing(sc, option::none(), alice());

    // Should fail
    common_tests::register_user_for_testing(sc, option::none(), alice());

    sc0.end();
}

fun check_account_exists(sc: &mut Scenario, name: String, sender: address) {
    sc.next_tx(sender);

    let registry = sc.take_shared<AccountRegistry>();
    let owner_cap = sc.take_from_sender<AccountOwnerCap>();
    let account_id = owner_cap.account_of();

    assert!(registry.contains_account(account_id), 0);

    let profile = registry.borrow_account(account_id);
    assert!(profile.name() == name, 0);
    
    ts::return_shared(registry);
    sc.return_to_sender(owner_cap);
}