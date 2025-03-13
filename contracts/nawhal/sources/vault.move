

// //! `vault` module is the core module of the nawhal protocol.
// //! It should be responsible for hold the user's collateral

// module nawhal::vault;

// /// move std

// /// sui libs
// use sui::balance::{Self, Balance};

// /// self modules
// // use nawhal::decimal::{Self, Decimal};

// /// ------ Errors ------ ///
// const EInsufficientBalance: u64 = 1;

// /// ------ Structs ------ ///
// public struct Vault<phantom Collateral> has key {
//     id: UID,
//     balance: Balance<Collateral>,
//     balance_value: Decimal,
// }

// /// ------ Functions ------ ///
// public fun create_vault<Collateral>(
//     ctx: &mut TxContext,
// ): Vault<Collateral> {
//     Vault {
//         id: object::new(ctx),
//         balance: balance::zero(),
//         balance_value: decimal::from_u64(0),
//     }
// }

// public(package) fun share_vault<Collateral>(
//     vault: Vault<Collateral>,
// ) {
//     transfer::share_object(vault);
// }

// // Deposit collateral to vault, and return the total value of the vault
// public fun deposit<Collateral>(
//     vault: &mut Vault<Collateral>,
//     payment: Balance<Collateral>,
// ): Decimal {
//     let new_balance_value = decimal::add(vault.balance_value, decimal::from_u64(payment.value()));

//     vault.balance.join(payment);
//     vault.balance_value = new_balance_value;

//     assert!(
//         decimal::eq(&vault.balance_value, &decimal::from_u64(vault.balance.value())), 
//         EInsufficientBalance
//     );

//     new_balance_value
// }

// /// ------ Getters ------ ///
// public fun balance_value<Collateral: key>(
//     vault: &Vault<Collateral>,
// ): Decimal {
//     vault.balance_value
// }
