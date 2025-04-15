//! The Liquidity Layer is a "base" layer, also is a module that manage the global liquidity of the protocol.
//! This "base" layer can be responsible for:
//! - Holding the underlying assets
//! - Deposit  assets to the LiquidityVaults
//! - Withdraw assets from the LiquidityVaults
//! - Register assets to the protocol
//! - Providing oracle prices
//! - Implementing some defensive functions (such as rate limiting, status management, etc.)
//! - Transfer the assets to the protocol layer
//! 
//! It calls for simpler, more readable, and reliable code - at least at the base layer - to ensure safety.

module nawhal::liquidity_layer;

use std::ascii::String;
use std::type_name::{Self, TypeName};

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::object_bag::{Self, ObjectBag};
use sui::vec_map::{Self, VecMap};

use nawhal::admin::{Self, AdminCap};
use nawhal::liquidity_event;

// ------- errors ------- //
const EInvalidLiquidityStatus: u64 = 10001;
const EProtocolAlreadyExisted: u64 = 10002;
const EProtocolNotFound: u64 = 10003;
const EAssetTypeAlreadyExisted: u64 = 10004;
const EAssetTypeNotFound: u64 = 10005;
const EProtocolAssetTypeMismatch: u64 = 10006;
const EProtocolInsufficientBalance: u64 = 10007;

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

    // Stores Protocols
    protocols: VecMap<ID, ProtocolConfig>,
}

public struct LiquidityVault<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    borrow_status: BorrowStatus,
    withdraw_status: WithdrawStatus,
    config: VaultConfig,
    created_at_ms: u64,
    created_at_epoch: u64,
}

public struct ProtocolConfig has copy, drop, store {
    protocol_id: ID,
    asset_type: TypeName,
    amount: u64,
}

public struct VaultConfig has copy, drop, store {

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

// ------- functions ------- //
/// Initialize the LiquidityLayer
/// Create a `LiquidityLayer` and share it,
/// Create a `AdminCap` and transfer it to the sender(publisher)
fun init(ctx: &mut TxContext) {
    let liquidity_layer = new_liquidity_layer(ctx);
    let layer_id = liquidity_layer.layer_id();

    transfer::share_object(liquidity_layer);

    admin::create_admin_cap_and_transfer(ctx);

    // Emit liquidity layer created event
    liquidity_event::emit_liquidity_layer_created_event(layer_id, ctx.epoch_timestamp_ms(), ctx.epoch());
}

// ------- Logic functions ------- //
/// The Protocol deposits the assets to the LiquidityLayer.
/// And update the protocol amount with protocol_id.
public fun deposit<T>(self: &mut LiquidityLayer, protocol_id: ID, payload: Balance<T>, clock: &Clock, ctx: &mut TxContext) {
    if (payload.value() == 0) {
        payload.destroy_zero();
    } else {
        let asset_type = type_name::get<T>();
        self.check_protocol_exists(&protocol_id);
        self.check_protocol_asset_type_match(&protocol_id, &asset_type);

        // Update the protocol config
        let protocol_config = self.protocols.get_mut(&protocol_id);
        protocol_config.amount = protocol_config.amount + payload.value();

        // Get the vault ID using the asset type
        let liquidity_vault_id = self.asset_types.get(&asset_type);
        let liquidity_vault = self.liquidity_vaults.borrow_mut<ID, LiquidityVault<T>>(*liquidity_vault_id);
        
        let deposit_value = payload.value();
        liquidity_vault.balance.join(payload);

        // Emit protocol deposited event
        liquidity_event::emit_protocol_deposited_event(self.layer_id(), protocol_id, deposit_value, clock.timestamp_ms(), ctx.epoch());
    }  
}

/// The Protocol withdraws the assets from the LiquidityLayer.
/// And update the protocol amount with protocol_id.
/// Ignore the amount if the protocol amount is less than the amount.
public fun withdraw<T>(self: &mut LiquidityLayer, protocol_id: ID, amount: u64, clock: &Clock, ctx: &mut TxContext): Balance<T> {
    if (amount == 0) {
        return balance::zero<T>()
    };

    let asset_type = type_name::get<T>();
    self.check_protocol_exists(&protocol_id);
    self.check_protocol_asset_type_match(&protocol_id, &asset_type);

    let protocol_config = self.protocols.get_mut(&protocol_id);

    assert!(protocol_config.amount >= amount, EProtocolInsufficientBalance);
    
    protocol_config.amount = protocol_config.amount - amount;

    // Get the vault ID using the asset type
    let liquidity_vault_id = self.asset_types.get(&asset_type);
    let liquidity_vault = self.liquidity_vaults.borrow_mut<ID, LiquidityVault<T>>(*liquidity_vault_id);

    let withdrawn_balance = liquidity_vault.balance.split(amount);

    // TODO: Rate limiting

    // Emit protocol withdrawn event
    liquidity_event::emit_protocol_withdrawn_event(self.layer_id(), protocol_id, amount, clock.timestamp_ms(), ctx.epoch());

    withdrawn_balance
}

/// Register a new asset vault to the LiquidityLayer.
/// 
/// # Arguments
/// * `liquidity_layer`: The LiquidityLayer to register the asset vault to.
/// * `payload`: The payload to register the asset vault to.
/// * `ctx`: The transaction context.
/// 
/// # Ignores
/// * If the asset type is already registered.
public(package) fun register_asset_vault<T>(self: &mut LiquidityLayer, ctx: &mut TxContext) {
    let asset_type = type_name::get<T>();
    check_liquidity_layer_is_active(self);
    check_asset_type_not_exists(self, &asset_type);

    let liquidity_vault = new_liquidity_vault<T>(ctx);
            
    let liquidity_vault_id = liquidity_vault.vault_id();

    self.asset_types.insert(asset_type, liquidity_vault_id);
    self.liquidity_vaults.add(liquidity_vault_id, liquidity_vault);  

    // Emit vault registered event
    liquidity_event::emit_vault_registered_event(self.layer_id(), liquidity_vault_id, asset_type.into_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
}

/// Register a new asset vault to the LiquidityLayer by AdminCap
public fun register_vault_by_admin_cap<T>(self: &mut LiquidityLayer, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    self.register_asset_vault<T>(ctx);
}

/// Register a new protocol to the LiquidityLayer
/// Pause the liquidity layer
public fun register_protocol<T>(self: &mut LiquidityLayer, _admin_cap: &AdminCap, protocol_id: ID, ctx: &mut TxContext) {
    let asset_type = type_name::get<T>();

    self.check_liquidity_layer_is_active();
    self.check_asset_type_exists(&asset_type);
    self.check_protocol_not_exists(&protocol_id);
    
    self.protocols.insert(
        protocol_id, 
        new_protocol_config(protocol_id, asset_type, 0)
    );

    // Emit protocol registered event
    liquidity_event::emit_protocol_registered_event(self.layer_id(), protocol_id, asset_type.into_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
}

/// Pause the liquidity layer
public fun pause_liquidity_layer(self: &mut LiquidityLayer, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let old_status = self.status;
    let new_status = LiquidityStatus::Paused;
    self.set_status(new_status);

    // Emit liquidity layer paused event
    liquidity_event::emit_liquidity_layer_paused_event(self.layer_id(), old_status.layer_status_to_string(), new_status.layer_status_to_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
}

/// Resume the liquidity layer
public fun resume_liquidity_layer(self: &mut LiquidityLayer, _admin_cap: &AdminCap, ctx: &mut TxContext) {
    let old_status = self.status;
    let new_status = LiquidityStatus::Active;
    self.set_status(new_status);

    // Emit liquidity layer resumed event
    liquidity_event::emit_liquidity_layer_resumed_event(self.layer_id(), old_status.layer_status_to_string(), new_status.layer_status_to_string(), ctx.epoch_timestamp_ms(), ctx.epoch());
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
public fun new_liquidity_vault<T>(ctx: &mut TxContext): LiquidityVault<T> {
    LiquidityVault {
        id: object::new(ctx),
        balance: balance::zero<T>(),
        borrow_status: BorrowStatus::Borrowable,
        withdraw_status: WithdrawStatus::Withdrawable,
        config: new_vault_config(),
        created_at_ms: ctx.epoch(),
        created_at_epoch: ctx.epoch(),
    }
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
public fun new_vault_config(): VaultConfig {
    VaultConfig {     
    }
}

/// New a new ProtocolConfig
public fun new_protocol_config(protocol_id: ID, asset_type: TypeName, amount: u64): ProtocolConfig {
    ProtocolConfig {
        protocol_id,
        asset_type,
        amount,
    }
}

/// LiquidityLayerStatusToString 
public fun layer_status_to_string(status: LiquidityStatus): String {
    match (status) {
        LiquidityStatus::Active => b"Active".to_ascii_string(),
        LiquidityStatus::Paused => b"Paused".to_ascii_string(),
        LiquidityStatus::Closed => b"Closed".to_ascii_string(),
    }
}

// ------- Getters ------- //
public fun layer_id(self: &LiquidityLayer): ID {
    object::id(self)
}

public fun layer_status(self: &LiquidityLayer): LiquidityStatus {
    self.status
}

public fun vault_id<T>(self: &LiquidityVault<T>): ID {
    object::id(self)
}

public fun vault_balance<T>(self: &LiquidityVault<T>): u64 {
    self.balance.value()
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
public fun borrow_vault<T>(self: &LiquidityLayer): &LiquidityVault<T> {
    let asset_type = type_name::get<T>();
    let liquidity_vault_id = self.asset_types.get(&asset_type);
    self.liquidity_vaults.borrow<ID, LiquidityVault<T>>(*liquidity_vault_id)
}

/// Get the asset balance of the given asset type.
public fun get_asset_balance<T>(self: &LiquidityLayer): u64 {
    let liquidity_vault = self.borrow_vault<T>();
    liquidity_vault.balance.value()
}

// ------- Setters ------- //
public(package) fun set_status(self: &mut LiquidityLayer, status: LiquidityStatus) {
    self.status = status;
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
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

#[test_only]
public fun destroy_liquidity_vault_for_testing<T>(vault: LiquidityVault<T>) {
    let LiquidityVault {
        id,
        balance,
        borrow_status: _,
        withdraw_status: _,
        config: _,
        created_at_ms: _,
        created_at_epoch: _,
    } = vault;

    id.delete();
    balance.destroy_for_testing();
}

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

// Test Create Liquidity Vault
#[test]
fun test_create_liquidity_vault_should_work() {
    use sui::sui::SUI;

    let mut ctx = tx_context::dummy();

    let vault = new_liquidity_vault<SUI>(&mut ctx);

    assert!(vault.balance.value() == 0, 0);

    destroy_liquidity_vault_for_testing<SUI>(vault);
}

