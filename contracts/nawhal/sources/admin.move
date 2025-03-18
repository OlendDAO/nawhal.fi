
module nawhal::admin;

public struct AdminCap has key {
    id: UID,
}

public(package) fun create_admin_cap(ctx: &mut TxContext) {
    let cap = AdminCap { id: object::new(ctx) };

    transfer::transfer<AdminCap>(cap, tx_context::sender(ctx));
}

	 