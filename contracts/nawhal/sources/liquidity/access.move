
module narval::access;


/* ================= VaultAccess ================= */

/// There can only ever be one `VaultCap` for a `Vault`
/// `T` is the type of the asset in the vault
/// `YT` is the type of the yield token in the vault
public struct VaultCap<phantom T, phantom YT> has key, store {
    id: UID,
}

/// Create a new `VaultCap`
public(package) fun new_vault_cap<T, YT>(ctx: &mut TxContext): VaultCap<T, YT> {
    VaultCap {
        id: object::new(ctx),
    }
}

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