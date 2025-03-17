
#[test_only]
module nawhal::common_tests;

use std::ascii::String;

use sui::clock::{Self, Clock};

use sui::test_scenario::{Self as ts, Scenario};

use nawhal::account_ds::{Self, AccountRegistry};

use nawhal::account;

/// Coins for testing
public struct BTC has drop { }

public struct ETH has drop { }

public struct USD has drop { }

/// Alice address for testing
public fun alice(): address {
    @0x619640c96ee005ca6fa7530006b34358f1e638a386071ce229bb99db9486962d
}

/// Bob address for testing
public fun bob(): address {
    @0xdae2f56afc119ebddf5ca4ba80cd8a42fced9a74a7bb139c2bf6d0f3a77c497a
}

public fun create_clock_and_share(sc: &mut Scenario) {
    let clock = clock::create_for_testing(sc.ctx());
    
    clock.share_for_testing();
}

public fun increase_clock_for_testing(
    sc: &mut Scenario,
    seconds: u64,
    sender: address,
) {
    sc.next_tx(sender);
    let mut clock = sc.take_shared<Clock>();
    clock.increment_for_testing(seconds * 1000);
    ts::return_shared(clock);
}


/// Register a user to the registry
public fun register_user_for_testing(
    sc: &mut Scenario,
    name: Option<String>,
    sender: address,
): ID {
    sc.next_tx(sender);

    let mut registry = sc.take_shared<AccountRegistry>();
    let account_id = account::create_account_and_register(&mut registry, name, sc.ctx());

    ts::return_shared(registry);

    account_id
}
