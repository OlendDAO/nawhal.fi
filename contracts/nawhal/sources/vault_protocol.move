

module narval::vault_protocol;

// use sui::balance::Balance;

// use narval::liquidity_layer_model::{LiquidityLayer};

// // ----- Structs ----- //
// /// Vault protocol is a protocol that allows users to borrow assets from the protocol
// public struct VaultProtocol<phantom Collateral, phantom T> has key, store {
//     id: UID,
//     collateral_vault: LiquidityVault<Collateral, YTCollateral>,
//     asset_vault: LiquidityVault<T, YT>,
// }

// // ----- Logic functions ----- //
// /// Borrow a specified amount of a given asset from the vault.
// public fun borrow<Collateral, YTCollateral, T, YT>(
//     vault: &mut VaultProtocol<Collateral, T>,
//     liquidity_layer: &mut LiquidityLayer,
//     protocol_id: ID,
//     account_
//     amount: u64,
//     ctx: &mut TxContext
// ): Balance<T> {
//     let vault = liquidity_layer.borrow_vault_mut<Collateral, YTCollateral>();
//     let balance = vault.borrow<T>(amount, ctx);
//     balance
// }