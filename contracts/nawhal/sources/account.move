
/// This module is used to manage the account of the user
/// 
module nawhal::account;

use std::ascii::String;

use sui::clock::Clock;
use nawhal::account_ds::{Self, AccountRegistry};

/// Init Account context
fun init(ctx: &mut TxContext) {
    initialize(ctx);
}

public(package) fun initialize(ctx: &mut TxContext) {
    let registry = account_ds::new_registry(ctx);

    registry.share();
}

/// Create a new account and register it
public fun create_account_and_register(
    registry: &mut AccountRegistry,
    name: Option<String>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let cap = registry.new_account_and_register(name, ctx.sender(), clock.timestamp_ms(), ctx);
    let account_id = cap.account_of();

    cap.transfer(ctx.sender());

    account_id
}

/// For testing
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    initialize(ctx);
}





