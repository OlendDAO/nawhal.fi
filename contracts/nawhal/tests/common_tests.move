
#[test_only]
module nawhal::common_tests;

use sui::clock::{Self, Clock};

use sui::test_scenario::{Self as ts, Scenario};

/// Coins for testing
public struct BTC has drop { }

public struct ETH has drop { }

public struct USD has drop { }

/// Alice address for testing
public fun alice(): address {
    @0xabc
}

/// Bob address for testing
public fun bob(): address {
    @0xdef
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

