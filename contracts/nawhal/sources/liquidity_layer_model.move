
module nawhal::liquidity_layer_model;

use std::ascii::String;
use std::type_name::{Self, TypeName};

use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::TreasuryCap;
use sui::object_bag::{Self, ObjectBag};
use sui::vec_map::{Self, VecMap};

use nawhal::liquidity_vault::{Self, LiquidityVault, VaultCap};

// ------- constants ------- //
// const DEFAULT_RATE_LIMITING_IN_DAY: u64 = 1_000_000_000_000_000;    // 1 million

// ------- errors ------- //
const EInvalidLiquidityStatus: u64 = 10001;
const EProtocolAlreadyExisted: u64 = 10002;
const EProtocolNotFound: u64 = 10003;
const EAssetTypeAlreadyExisted: u64 = 10004;
const EAssetTypeNotFound: u64 = 10005;
const EProtocolAssetTypeMismatch: u64 = 10006;
const EVaultRateLimitingExceeded: u64 = 10007;

// ------- structs ------- //
/// `LiquidityLayer` struct holding the global liquidity of the protocol, and registering the assets types and its vaults.
public struct LiquidityLayer has key {
    id: UID,
    // Stores (LiquidityVault id, LiquidityVault)
    liquidity_vaults: ObjectBag,
    // Stores (AssetType, LiquidityVault id)
    asset_types: VecMap<TypeName, ID>,

    // Status
    status: LiquidityStatus,

    // Stores Protocols, including lending protocols and vault protocols and etc.
    protocols: VecMap<ID, ProtocolConfig>,

    // Swap price TODO:
}


public struct ProtocolConfig has copy, drop, store {
    protocol_id: ID,
    asset_type: TypeName,
    amount: u64,
    protocol_type: ProtocolType,
}

public enum ProtocolType has copy, drop, store {
    Lending,
    Vault,
    DEX,
}

public struct VaultConfig has copy, drop, store {
    latest_epoch: u64,
    latest_epoch_amount: u64,
    // Interest rate
    interest_rate_bps: u64,
    // a epoch is 1 day in Sui
    rate_limiting_in_epoch: u64,
}

public enum LiquidityStatus has copy, drop, store {
    Active,
    Paused,
    Closed,
}

public enum BorrowStatus has copy, drop, store {
    Borrowable,
    UnBorrowable,
}

public enum WithdrawStatus has copy, drop, store {
    Withdrawable,
    UnWithdrawable,
}

// ------- new structs ------- //
/// New a new LiquidityLayer
public fun new_liquidity_layer(ctx: &mut TxContext): LiquidityLayer {
    LiquidityLayer {
        id: object::new(ctx),
        liquidity_vaults: object_bag::new(ctx),
        asset_types: vec_map::empty(),
        status: LiquidityStatus::Active,
        protocols: vec_map::empty(),
    }
}

/// New a new LiquidityVault
public fun new_liquidity_vault<T, YT>(lp_treasury: TreasuryCap<YT>, ctx: &mut TxContext): (LiquidityVault<T, YT>, VaultCap<YT>) {
    let (vault, admin_cap) = liquidity_vault::new<T, YT>(lp_treasury, ctx);
    (vault, admin_cap)      
}   

/// New an Active LiquidityStatus 
public fun new_active_liquidity_status(): LiquidityStatus {
    LiquidityStatus::Active
}

/// New a Paused LiquidityStatus 
public fun new_paused_liquidity_status(): LiquidityStatus {
    LiquidityStatus::Paused
}

/// New a VaultConfig
public fun new_vault_config(interest_rate_bps: u64, rate_limiting_in_day: u64): VaultConfig {
    VaultConfig {     
        latest_epoch_amount: 0,
        latest_epoch: 0,
        interest_rate_bps,
        rate_limiting_in_epoch: rate_limiting_in_day,
    }
}

/// New a new ProtocolConfig
public fun new_protocol_config(protocol_id: ID, asset_type: TypeName, amount: u64, protocol_type: ProtocolType): ProtocolConfig {
    ProtocolConfig {
        protocol_id,
        asset_type,
        amount,
        protocol_type,
    }
}

/// Share the LiquidityLayer
public(package) fun share_object(self: LiquidityLayer) {
    transfer::share_object(self);
}

/// New a new LendingProtocolType
public fun new_lending_protocol_type(): ProtocolType {
    ProtocolType::Lending
}

/// New a new VaultProtocolType
public fun new_vault_protocol_type(): ProtocolType {
    ProtocolType::Vault
}

/// New a new DEXProtocolType
public fun new_dex_protocol_type(): ProtocolType {
    ProtocolType::DEX
}

/// New a new Closed LiquidityStatus
public fun new_closed_liquidity_status(): LiquidityStatus {
    LiquidityStatus::Closed
}

/// LiquidityLayerStatusToString 
public fun layer_status_to_string(status: LiquidityStatus): String {
    match (status) {
        LiquidityStatus::Active => b"Active".to_ascii_string(),
        LiquidityStatus::Paused => b"Paused".to_ascii_string(),
        LiquidityStatus::Closed => b"Closed".to_ascii_string(),
    }
}

// ------- Checks ------- //
/// Checks if a protocol is already registered in the liquidity layer.
/// Aborts with `EProtocolNotRegistered` if the protocol is found in the `protocols` set.
public fun check_protocol_exists(self: &LiquidityLayer, protocol_id: &ID) {
    assert!(self.contains_protocol(protocol_id), EProtocolNotFound);
}

/// Checks if a protocol is not registered in the liquidity layer.
/// Aborts with `EProtocolNotRegistered` if the protocol is not found in the `protocols` set.
public fun check_protocol_not_exists(self: &LiquidityLayer, protocol_id: &ID) {
    assert!(!self.contains_protocol(protocol_id), EProtocolAlreadyExisted);
}

/// Checks if an asset type is already registered in the liquidity layer.
/// Aborts with `EAssetTypeNotFound` if the asset type is found in the `asset_types` set.
public fun check_asset_type_exists(self: &LiquidityLayer, asset_type: &TypeName) {
    assert!(self.contains_asset_type(asset_type), EAssetTypeNotFound);
}

/// Checks if an asset type is not registered in the liquidity layer.
/// Aborts with `EAssetTypeNotFound` if the asset type is not found in the `asset_types` set.
public fun check_asset_type_not_exists(self: &LiquidityLayer, asset_type: &TypeName) {
    assert!(!self.contains_asset_type(asset_type), EAssetTypeAlreadyExisted);
}

/// Checks if the protocol asset type match the asset type.
/// Aborts with `EProtocolAssetTypeMismatch` if the protocol asset type does not match the asset type.
public fun check_protocol_asset_type_match(self: &LiquidityLayer, protocol_id: &ID, asset_type: &TypeName) {
    assert!(self.protocols.get(protocol_id).asset_type == asset_type, EProtocolAssetTypeMismatch);
}

/// Checks if the liquidity layer is active.
/// Aborts with `EInvalidLiquidityStatus` if the liquidity layer is not active.
public fun check_liquidity_layer_is_active(self: &LiquidityLayer) {
    assert!(self.status == LiquidityStatus::Active, EInvalidLiquidityStatus);
}

/// Checks if the vault rate limiting is exceeded.
/// Aborts with `EVaultRateLimitingExceeded` if the vault rate limiting is exceeded.
public fun check_vault_rate_limiting(vault_config: &VaultConfig) {
    assert!(vault_config.latest_epoch_amount <= vault_config.rate_limiting_in_epoch, EVaultRateLimitingExceeded);
}

// ------- Getters ------- //
/// Get the liquidity layer id
public fun layer_id(self: &LiquidityLayer): ID {
    object::id(self)
}

/// Get the liquidity layer status
public fun layer_status(self: &LiquidityLayer): LiquidityStatus {
    self.status
}

// /// Get the total_deposits of the given asset type
// public fun total_deposits<T>(self: &LiquidityLayer): u64 {
//     let liquidity_vault_id = self.vault_id_of_asset<T>();
//     self.liquidity_vaults
//         .borrow<ID, LiquidityVault<T>>(liquidity_vault_id)
//         .total_deposits
// }

// /// Get the total_collateral of the given asset type
// public fun total_collateral<T>(self: &LiquidityLayer): u64 {
//     let liquidity_vault_id = self.vault_id_of_asset<T>();
//     self.liquidity_vaults
//         .borrow<ID, LiquidityVault<T>>(liquidity_vault_id)
//         .total_collateral
// }

// /// Get the total_in of the given asset type
// public fun total_in<T>(self: &LiquidityLayer): u64 {
//     let liquidity_vault_id = self.vault_id_of_asset<T>();
//     self.liquidity_vaults
//         .borrow<ID, LiquidityVault<T>>(liquidity_vault_id)
//         .cumulative_in
// }

// /// Get the total_out of the given asset type
// public fun total_out<T>(self: &LiquidityLayer): u64 {
//     let liquidity_vault_id = self.vault_id_of_asset<T>();
//     self.liquidity_vaults
//         .borrow<ID, LiquidityVault<T>>(liquidity_vault_id)
//         .cumulative_out
// }

/// Get the LiquidityVault id of the given asset type
public fun vault_id_of_asset<T>(self: &LiquidityLayer): ID {
    let asset_type = type_name::get<T>();
    *self.asset_types.get(&asset_type)
}


// /// Get the cash value
// public fun cash_value<T>(self: &LiquidityVault<T>): u64 {
//     self.cash.value()
// }

/// Get the protocol amount
public fun get_protocol_amount(self: &LiquidityLayer, protocol_id: &ID): u64 {
    self.protocols.get(protocol_id).amount
}

// ------- Views ------- //
/// Get assets amount registered in the liquidity layer.
public fun asset_type_amount(self: &LiquidityLayer): u64 {
    self.asset_types.size()
}

/// Contains the given asset type in the liquidity layer or not.
public fun contains_asset_type(self: &LiquidityLayer, asset_type: &TypeName): bool {
    self.asset_types.contains(asset_type)
}

/// Contains the given protocol in the liquidity layer or not.
public fun contains_protocol(self: &LiquidityLayer, protocol_id: &ID): bool {
    self.protocols.contains(protocol_id)
}

/// Get the liquidity layer is active or not.
public fun is_active(self: &LiquidityLayer): bool {
    self.status == LiquidityStatus::Active
}

/// Borrow the asset balance of the given asset type.
public fun borrow_vault<T, YT>(self: &LiquidityLayer): &LiquidityVault<T, YT> {
    let liquidity_vault_id = self.vault_id_of_asset<T>();
    self.liquidity_vaults.borrow<ID, LiquidityVault<T, YT>>(liquidity_vault_id)
}

/// Borrow mut the vault of the given asset type.
public(package) fun borrow_vault_mut<T, YT>(self: &mut LiquidityLayer): &mut LiquidityVault<T, YT> {
    let liquidity_vault_id = self.vault_id_of_asset<T>();
    self.liquidity_vaults.borrow_mut<ID, LiquidityVault<T, YT>>(liquidity_vault_id)
}

/// Borrow mut the protocol config of the given protocol id.
public(package) fun get_protocol_mut(self: &mut LiquidityLayer, protocol_id: &ID): &mut ProtocolConfig {
    self.protocols.get_mut(protocol_id)
}

/// Get the asset balance of the given asset type.
public fun vault_cash_balance<T, YT>(self: &LiquidityLayer): u64 {
    let liquidity_vault = self.borrow_vault<T, YT>();
    liquidity_vault.free_balance_value()
}

// ------- Setters ------- //
public(package) fun set_status(self: &mut LiquidityLayer, status: LiquidityStatus) {
    self.status = status;
}

/// Add a protocol to the liquidity layer
public(package) fun add_protocol(self: &mut LiquidityLayer, protocol_id: ID, protocol_config: ProtocolConfig) {
    self.protocols.insert(protocol_id, protocol_config);
}

/// Add a LiquidityVault to the liquidity layer
public(package) fun add_liquidity_vault<T, YT>(self: &mut LiquidityLayer, liquidity_vault_id: ID, liquidity_vault: LiquidityVault<T, YT>) {
    self.liquidity_vaults.add(liquidity_vault_id, liquidity_vault);
}

/// Add an asset type to the liquidity layer
public(package) fun add_asset_type(self: &mut LiquidityLayer, asset_type: TypeName, liquidity_vault_id: ID) {
    self.asset_types.insert(asset_type, liquidity_vault_id);
}

/// Add asset to vault balance
public(package) fun add_asset_to_vault_balance<T, YT>(self: &mut LiquidityLayer, payload: Balance<T>, clock: &Clock): Balance<YT> {
    let asset_type = type_name::get<T>();
    let liquidity_vault_id = self.asset_types.get(&asset_type);
    let liquidity_vault = self.liquidity_vaults.borrow_mut<ID, LiquidityVault<T, YT>>(*liquidity_vault_id);
    
    liquidity_vault.deposit(payload, clock)
}

/// Increment the protocol amount
public(package) fun increment_protocol_amount(self: &mut LiquidityLayer, protocol_id: ID, amount: u64) {
    // let vault = self.borrow_vault_mut<T, YT>();
    // vault.cumulative_in = vault.cumulative_in + amount;
    // vault.total_deposits = vault.total_deposits + amount;

    let protocol_config = self.get_protocol_mut(&protocol_id);
    protocol_config.amount = protocol_config.amount + amount;
}

// /// Decrement the protocol amount
// public(package) fun decrement_protocol_amount<T>(self: &mut LiquidityLayer, protocol_id: ID, amount: u64) {
//     let vault = self.borrow_vault_mut<T>();
//     vault.cumulative_out = vault.cumulative_out + amount;
//     vault.total_deposits = vault.total_deposits - amount;
//     let protocol_config = self.get_protocol_mut(&protocol_id);
//     protocol_config.amount = protocol_config.amount - amount;
// }

/// Withdraw from LiquidityVault
public(package) fun withdraw_from_liquidity_vault<T, YT>(self: &mut LiquidityLayer, shares: Balance<YT>, clock: &Clock): Balance<T> {
    let liquidity_vault_id = self.asset_types.get(&type_name::get<T>());
    let liquidity_vault = self.liquidity_vaults.borrow_mut<ID, LiquidityVault<T, YT>>(*liquidity_vault_id);

    let tick = liquidity_vault.withdraw(shares, clock);

    // TODO: Rate limiting for 1 epoch(1 day)
    // let vault_config = &mut liquidity_vault.config;
    // if (vault_config.latest_epoch != current_epoch) {
    //     vault_config.latest_epoch = current_epoch;
    //     vault_config.latest_epoch_amount = amount;
    // } else {
    //     vault_config.latest_epoch_amount = vault_config.latest_epoch_amount + amount;
    // };

    // check_vault_rate_limiting(vault_config);

    liquidity_vault.redeem_withdraw_ticket(tick)
}

#[test_only]
public fun destroy_liquidity_layer_for_testing(layer: LiquidityLayer) {
    let LiquidityLayer {
        id,
        liquidity_vaults,
        asset_types: _,
        status: _,
        protocols: _,
    } = layer;

    id.delete();
    liquidity_vaults.destroy_empty();
}

// #[test_only]
// public fun destroy_liquidity_vault_for_testing<T, YT>( vault: LiquidityVault<T, YT>) {
//     let LiquidityVault {
//         id,
//         free_balance,
//         time_locked_profit,
//         lp_treasury,
//         strategies,
//         performance_fee_balance,
//         strategy_withdraw_priority_order,
//         withdraw_ticket_issued,
//     } = vault;

//     id.delete();
//     cash.destroy_for_testing();
// }

// ------- Unit tests ------- //
#[test]
fun test_create_liquidity_layer_should_work() {
    let mut ctx = tx_context::dummy();

    let layer = new_liquidity_layer(&mut ctx);

    assert!(layer.status == LiquidityStatus::Active, EInvalidLiquidityStatus);
    assert!(layer.asset_types.size() == 0, 0);

    destroy_liquidity_layer_for_testing(layer);
}

// Test Set Liquidity Layer Status
#[test]
fun test_set_liquidity_layer_status_should_work() {
    let mut ctx = tx_context::dummy();

    let mut layer = new_liquidity_layer(&mut ctx);

    set_status(&mut layer, LiquidityStatus::Paused);

    assert!(layer.status == LiquidityStatus::Paused, EInvalidLiquidityStatus);

    destroy_liquidity_layer_for_testing(layer);
}

// // Test Create Liquidity Vault
// #[test]
// fun test_create_liquidity_vault_should_work() {
//     use sui::sui::SUI;

//     let mut ctx = tx_context::dummy();

//     let interest_rate_bps = 10000;
//     let (vault, _) = new_liquidity_vault<SUI, SUI>(interest_rate_bps, &mut ctx);

//     assert!(vault.cash_value() == 0, 0);

//     destroy_liquidity_vault_for_testing<SUI>(vault);
// }

