
module narval::access;

/* ================= AdminCap ================= */

/// There can only ever be one `AdminCap` for a `Vault`
public struct AdminCap<phantom YT> has key, store {
    id: UID,
}

/// Create a new `AdminCap`
public(package) fun new_admin_cap<YT>(ctx: &mut TxContext): AdminCap<YT> {
    AdminCap {
        id: object::new(ctx),
    }
}

/* ================= VaultAccess ================= */

/// Strategies store this and it gives them access to deposit and withdraw
/// from the vault
#[allow(lint(missing_key))]
public struct VaultAccess has store {
    id: UID,
}

/// Create a new `VaultAccess`
public(package) fun new_vault_access(ctx: &mut TxContext): VaultAccess {
    VaultAccess {
        id: object::new(ctx),
    }
}

/// Destroy a `VaultAccess`
public(package) fun destroy_vault_access(access: VaultAccess) {
    let VaultAccess { id: uid } = access;
    object::delete(uid);
}

/* ================= Getter ================= */
/// Get the `ID` of a `VaultAccess`
public(package) fun vault_access_id(access: &VaultAccess): ID {
    object::uid_to_inner(&access.id)
}