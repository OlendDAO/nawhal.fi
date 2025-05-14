module narval::admin;

public struct AdminCap has key {
    id: UID,
}

/// Create a new `AdminCap` and return it
public fun create_admin_cap(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}   

/// Create a new `AdminCap` and transfer it to the sender(publisher)
public(package) fun create_admin_cap_and_transfer(ctx: &mut TxContext) {
    let cap = create_admin_cap(ctx);

    transfer::transfer<AdminCap>(cap, tx_context::sender(ctx));
}
