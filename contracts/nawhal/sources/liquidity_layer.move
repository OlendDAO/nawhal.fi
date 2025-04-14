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

use std::type_name::{Self, TypeName};

use sui::balance::Balance;
use sui::object_bag::{Self, ObjectBag};

use sui::vec_map::{Self, VecMap};

use nawhal::admin::{Self, AdminCap};

// ------- errors ------- //
const EAssetTypeAlreadyRegistered: u64 = 10001;
const EInvalidLiquidityStatus: u64 = 10002;
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
}

public struct LiquidityVault<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    borrow_status: BorrowStatus,
    withdraw_status: WithdrawStatus,
    created_at_ms: u64,
    created_at_epoch: u64,
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
    let liquidity_layer = create_liquidity_layer(ctx);

    transfer::share_object(liquidity_layer);

    admin::create_admin_cap_and_transfer(ctx);
}

/// Create a new LiquidityLayer
public fun create_liquidity_layer(ctx: &mut TxContext): LiquidityLayer {
    LiquidityLayer {
        id: object::new(ctx),
        liquidity_vaults: object_bag::new(ctx),
        asset_types: vec_map::empty(),
        status: LiquidityStatus::Active,
    }
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
public(package) fun register_asset_vault<T>(liquidity_layer: &mut LiquidityLayer, payload: Balance<T>, ctx: &mut TxContext) {
    let asset_type = type_name::get<T>();
    check_asset_type_is_not_registered(liquidity_layer, &asset_type);

    let liquidity_vault = LiquidityVault {
        id: object::new(ctx),
        balance: payload,
        borrow_status: BorrowStatus::Borrowable,
        withdraw_status: WithdrawStatus::Withdrawable,
        created_at_ms: ctx.epoch(),
        created_at_epoch: ctx.epoch(),
    };  
            
    let liquidity_vault_id = liquidity_vault.vault_id();

    liquidity_layer.asset_types.insert(asset_type, liquidity_vault_id);
    liquidity_layer.liquidity_vaults.add(liquidity_vault_id, liquidity_vault);  
}

// ------- Checks ------- //
/// Checks if an asset type is already registered in the liquidity layer.
/// Aborts with `EAssetTypeAlreadyRegistered` if the asset type is found in the `asset_types` set.
public fun check_asset_type_is_not_registered(liquidity_layer: &LiquidityLayer, asset_type: &TypeName) {
    assert!(!contains_asset_type(liquidity_layer, asset_type), EAssetTypeAlreadyRegistered);
}

// ------- Getters ------- //
public fun layer_id(liquidity_layer: &LiquidityLayer): ID {
    object::id(liquidity_layer)
}

public fun vault_id<T>(liquidity_vault: &LiquidityVault<T>): ID {
    object::id(liquidity_vault)
}

public fun vault_balance<T>(liquidity_vault: &LiquidityVault<T>): u64 {
    liquidity_vault.balance.value()
}

// ------- Views ------- //
/// Get assets amount registered in the liquidity layer.
public fun assets_amount(liquidity_layer: &LiquidityLayer): u64 {
    liquidity_layer.asset_types.size()
}

/// Contains the given asset type in the liquidity layer or not.
public fun contains_asset_type(liquidity_layer: &LiquidityLayer, asset_type: &TypeName): bool {
    liquidity_layer.asset_types.contains(asset_type)
}

// ------- Setters ------- //
public fun set_status(liquidity_layer: &mut LiquidityLayer, status: LiquidityStatus) {
    liquidity_layer.status = status;
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
    } = layer;

    id.delete();
    liquidity_vaults.destroy_empty();
}

#[test]
fun test_create_liquidity_layer_should_work() {
    let mut ctx = tx_context::dummy();

    let layer = create_liquidity_layer(&mut ctx);

    assert!(layer.status == LiquidityStatus::Active, EInvalidLiquidityStatus);
    assert!(layer.asset_types.size() == 0, 0);

    destroy_liquidity_layer_for_testing(layer);
}