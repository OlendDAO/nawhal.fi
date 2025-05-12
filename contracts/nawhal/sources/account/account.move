/// This module is used to manage the account of the user
/// 
module narval::account;

use narval::account_ds;

/// Init Account context
fun init(ctx: &mut TxContext) {
    initialize(ctx);
}

public(package) fun initialize(ctx: &mut TxContext) {
    let registry = account_ds::new_registry(ctx);

    registry.share();
}

/// For testing
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    initialize(ctx);
}





