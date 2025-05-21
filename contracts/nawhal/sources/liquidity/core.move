module narval::liquidity;

use std::type_name::{Self,TypeName};

use sui::balance::{Self,Balance};
use sui::clock::{Clock};
use sui::object_bag::{Self, ObjectBag};
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};

use narval::access::VaultCap;
use narval::admin::{Self, AdminCap};
use narval::common::{Self, PoolPairItem};
use narval::layer_event;
use narval::vault::{Self, Vault};
use narval::protocol::{Self, ProtocolConfig, ProtocolType};
use narval::common::YieldToken;

/* ================= Errors ================= */
const EInvalidLiquidityStatus: u64 = 0;
const EAssetTypeAlreadyExisted: u64 = 1;
const EProtocolNotFound: u64 = 2;
const EProtocolAlreadyExisted: u64 = 3;
// const EProtocolAssetTypeMismatch: u64 = 4;
const EPoolAlreadyExists: u64 = 5;
const EInvalidPair: u64 = 6;
// const EProtocolInsufficientBalance: u64 = 6;

const EAssetTypeNotFound: u64 = 7;
/* ================= Structs ================= */

/// `LiquidityLayer` struct holding the global liquidity of the protocol, and registering the assets types and its vaults.
public struct LiquidityLayer has key {
    id: UID,
    // Stores (Vault id, Vault)
    vault_registry: ObjectBag,

    // Stores (AssetType, Vault id)
    asset_types: VecMap<TypeName, ID>,

    // Store Protocol registry
    protocol_registry: VecMap<ID, ProtocolConfig>,

    // Stores DEX registry
    dex_registry: Table<PoolPairItem, bool>,

    // Status
    status: Status,
}

public struct VaultItem has store, copy, drop {
    // Principal Token
    pt: TypeName,
    // Yield Token
    yt: TypeName,
}

public enum Status has copy, drop, store {
    Active,
    Paused,
    Closed,
}

/// New a new LiquidityLayer
public fun new_liquidity_layer(ctx: &mut TxContext): LiquidityLayer {
    LiquidityLayer {
        id: object::new(ctx),
        vault_registry: object_bag::new(ctx),
        asset_types: vec_map::empty(),
        protocol_registry: vec_map::empty(),
        dex_registry: table::new(ctx),
        status: new_active_status(),
    }
}

/// New a new VaultItem
public fun new_vault_item(pt: TypeName, yt: TypeName): VaultItem {
    VaultItem { pt, yt }
}

/// New an Active LiquidityStatus 
public fun new_active_status(): Status {
    Status::Active
}

/// New a Paused LiquidityStatus 
public fun new_paused_status(): Status {
    Status::Paused
}

/// New a Closed LiquidityStatus 
public fun new_closed_status(): Status {
    Status::Closed
}

/* ================= Getters ================= */
/// Get the `id` of the `LiquidityLayer`
public fun layer_id(self: &LiquidityLayer): ID {
    object::id(self)
}

/// Get the status of the `LiquidityLayer`
public fun status(self: &LiquidityLayer): Status {
    self.status
}

/// Get the LiquidityVault id of the given asset type
public fun vault_id_of_asset<T>(self: &LiquidityLayer): ID {
    let pt = type_name::get<T>();

    *self.asset_types.get(&pt)
}

/// Get the protocol amount
public fun get_protocol_amount(self: &LiquidityLayer, protocol_id: &ID): u64 {
    self.protocol_registry.get(protocol_id).amount()
}

/// Get the asset balance of the given asset type.
public fun vault_available_balance<T>(self: &LiquidityLayer): u64 {
    let vault = self.borrow_vault<T>();
    vault.available_balance()
}

/// Borrow the asset balance of the given asset type.
public fun borrow_vault<T>(self: &LiquidityLayer): &Vault<T> {
    let vault_id = self.vault_id_of_asset<T>();
    self.vault_registry.borrow<ID, Vault<T>>(vault_id)
}

/// Borrow mut the vault of the given asset type.
public(package) fun borrow_vault_mut<T>(self: &mut LiquidityLayer): &mut Vault<T> {
    let vault_id = self.vault_id_of_asset<T>();
    self.vault_registry.borrow_mut<ID, Vault<T>>(vault_id)
}

/// Borrow mut the protocol config of the given protocol id.
public(package) fun get_protocol_mut(self: &mut LiquidityLayer, protocol_id: &ID): &mut ProtocolConfig {
    self.protocol_registry.get_mut(protocol_id)
}
/// Contains the given asset type in the liquidity layer or not.
public fun contains_asset_type(self: &LiquidityLayer, pt: TypeName): bool {
    self.asset_types.contains(&pt)
}

/// Contains the given protocol in the liquidity layer or not.
public fun contains_protocol(self: &LiquidityLayer, protocol_id: &ID): bool {
    self.protocol_registry.contains(protocol_id)
}

/// Contains the given dex in the liquidity layer or not.
public fun contains_dex(self: &LiquidityLayer, item: PoolPairItem): bool {
    self.dex_registry.contains(item)
}

/// Share the `LiquidityLayer`
public(package) fun share_object(self: LiquidityLayer) {
    transfer::share_object(self);
}

/// Add an asset type to the liquidity layer
fun add_vault_asset_type(self: &mut LiquidityLayer, pt: TypeName, vault_id: ID) {
    self.asset_types.insert(pt, vault_id);
}

/// Add a `Vault` to the liquidity layer
public(package) fun add_vault<T>(self: &mut LiquidityLayer, vault_id: ID, vault: Vault<T>) {
    self.vault_registry.add(vault_id, vault);
    self.add_vault_asset_type(type_name::get<T>(), vault_id);
}

/// Remove a `Vault` from the liquidity layer
public(package) fun remove_vault<T>(self: &mut LiquidityLayer, vault_id: ID): Vault<T> {
    self.asset_types.remove(&type_name::get<T>());
    self.vault_registry.remove(vault_id)
}

/// Add a protocol to the liquidity layer
public(package) fun add_protocol(self: &mut LiquidityLayer, protocol_id: ID, protocol_config: ProtocolConfig) {
    self.protocol_registry.insert(protocol_id, protocol_config);
}

/// Add a new coin type tuple (`A`, `B`) to the registry. Types must be sorted alphabetically (ASCII ordered)
/// such that `A` < `B`. They also cannot be equal.
/// Aborts when coin types are the same.
/// Aborts when coin types are not in order (type `A` must come before `B` alphabetically).
/// Aborts when coin type tuple is already in the registry.
public(package) fun registry_dex<A, B>(self: &mut LiquidityLayer) {
    let a = type_name::get<A>();
    let b = type_name::get<B>();

    assert!(common::cmp_type_names(&a, &b) == 0, EInvalidPair);

    self.check_asset_type_exists(a);
    self.check_asset_type_exists(b);

    let item = common::new_pool_pair_item(a, b);

    assert!(!self.contains_dex(item), EPoolAlreadyExists);

    self.add_dex(item)
}

/// Add a dex to the liquidity layer
fun add_dex(self: &mut LiquidityLayer, item: PoolPairItem) {
    self.dex_registry.add(item, true);
}

/// Remove a protocol from the liquidity layer
public(package) fun remove_protocol(self: &mut LiquidityLayer, protocol_id: ID) {
    self.protocol_registry.remove(&protocol_id);
}

/// Remove dex from the liquidity layer
public(package) fun remove_dex<A, B>(self: &mut LiquidityLayer) {
    self.dex_registry.remove(common::new_pool_pair_item(type_name::get<A>(), type_name::get<B>()));
}

/// Increment the protocol amount
public(package) fun increment_protocol_amount(self: &mut LiquidityLayer, protocol_id: ID, amount: u64) {
    let protocol_config = self.get_protocol_mut(&protocol_id);
    let current_amount = protocol_config.amount();
    protocol_config.set_amount(current_amount + amount);
}

/// Decrement the protocol amount
public(package) fun decrement_protocol_amount(self: &mut LiquidityLayer, protocol_id: ID, amount: u64) {
    // Vault-level stats like cumulative_out or total_deposits might not be needed here or may belong in LiquidityVault module itself.
    // let vault = self.borrow_vault_mut<T, YT>(); // Generic types T, YT are not available here
    // vault.cumulative_out = vault.cumulative_out + amount;
    // vault.total_deposits = vault.total_deposits - amount;
    
    // Core logic: Update the amount tracked for the protocol in the layer
    let protocol_config = self.get_protocol_mut(&protocol_id);
    // Prevent underflow - though checks should happen before calling this
    if (protocol_config.amount() >= amount) {
        let current_amount = protocol_config.amount();
        protocol_config.set_amount(current_amount - amount);
    } else {
        protocol_config.set_amount(0); // Or handle error appropriately
    }
}

/// Add asset to vault balance
public(package) fun add_asset_to_vault_balance<T>(self: &mut LiquidityLayer, payload: Balance<T>, clock: &Clock): Balance<YieldToken<T>> {
    let pt = type_name::get<T>();
    let vault_id = self.asset_types.get(&pt);
    let vault = self.vault_registry.borrow_mut<ID, Vault<T>>(*vault_id);
    
    vault.deposit(payload, clock)
}

/// Withdraw from LiquidityVault
public(package) fun withdraw_from_vault<T>(self: &mut LiquidityLayer, shares: Balance<YieldToken<T>>, clock: &Clock): Balance<T> {
    let vault_id = self.asset_types.get(&type_name::get<T>());
    let vault = self.vault_registry.borrow_mut<ID, Vault<T>>(*vault_id);

    let tick = vault.withdraw(shares, clock);

    // TODO: Rate limiting for 1 epoch(1 day)
    // let vault_config = &mut liquidity_vault.config;
    // if (vault_config.latest_epoch != current_epoch) {
    //     vault_config.latest_epoch = current_epoch;
    //     vault_config.latest_epoch_amount = amount;
    // } else {
    //     vault_config.latest_epoch_amount = vault_config.latest_epoch_amount + amount;
    // };

    // check_vault_rate_limiting(vault_config);

    vault.redeem_withdraw_ticket(tick)
}

/* ================= Setters ================= */

public(package) fun set_status(self: &mut LiquidityLayer, status: Status) {
    self.status = status;
}

/* ================= Checks ================= */
/// Checks if the liquidity layer is active.
/// Aborts with `EInvalidLiquidityStatus` if the liquidity layer is not active.
public fun check_liquidity_layer_is_active(self: &LiquidityLayer) {
    assert!(self.status == new_active_status(), EInvalidLiquidityStatus);
}

/// Checks if an asset type is already registered in the liquidity layer.
/// Aborts with `EAssetTypeNotFound` if the asset type is found in the `asset_types` set.
public fun check_asset_type_exists(self: &LiquidityLayer, pt: TypeName) {
    assert!(self.contains_asset_type(pt), EAssetTypeNotFound);
}

/// Checks if an asset type is not registered in the liquidity layer.
/// Aborts with `EAssetTypeNotFound` if the asset type is not found in the `asset_types` set.
public fun check_asset_type_not_exists(self: &LiquidityLayer, pt: TypeName) {
    assert!(!self.contains_asset_type(pt), EAssetTypeAlreadyExisted);
}

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

/// Checks if the protocol asset type match the asset type.
/// Aborts with `EProtocolAssetTypeMismatch` if the protocol asset type does not match the asset type.
public fun check_protocol_asset_type_match(self: &LiquidityLayer, protocol_id: &ID) {
    let protocol_config = self.protocol_registry.try_get(protocol_id);
    assert!(protocol_config.is_some(), EProtocolNotFound);
    // assert!(protocol_config.token_a() == pt, EProtocolAssetTypeMismatch);
}

// ------- Initialize function ------- //
/// Initialize the LiquidityLayer
/// Create a `LiquidityLayer` and share it,
/// Create a `AdminCap` and transfer it to the sender(publisher)
fun init(ctx: &mut TxContext) {
    let layer = new_liquidity_layer(ctx);
    let layer_id = layer.layer_id();

    layer.share_object();

    admin::create_admin_cap_and_transfer(ctx);

    // Emit liquidity layer created event
    layer_event::emit_liquidity_layer_created_event(layer_id, ctx.epoch_timestamp_ms(), ctx.epoch());
}

/* ================= Logic functions ================= */
/// The Protocol deposits the assets to the LiquidityLayer.
/// And update the protocol amount with protocol_id.
public fun deposit<T>(self: &mut LiquidityLayer, protocol_id: ID, payload: Balance<T>, clock: &Clock, ctx: &mut TxContext): Balance<YieldToken<T>> {
    if (payload.value() == 0) {
        payload.destroy_zero();
        balance::zero()
    } else {
        let pt = type_name::get<T>();

        self.check_protocol_exists(&protocol_id);
        self.check_asset_type_exists(pt);
        // self.check_protocol_asset_type_match(&protocol_id, &pt);

        let deposit_value = payload.value();
        self.increment_protocol_amount(protocol_id, deposit_value);

        let shares = self.add_asset_to_vault_balance<T>(payload, clock);

        // Emit protocol deposited event
        layer_event::emit_protocol_deposited_event(self.layer_id(), protocol_id, deposit_value, clock.timestamp_ms(), ctx.epoch());

        shares
    }  
}

/// Deposit assets directly to the vault without minting YieldToken
public(package) fun deposit_direct<T>(
    self: &mut LiquidityLayer,
    protocol_id: ID,
    payment: Balance<T>,
) {
    let vault = self.borrow_vault_mut<T>();
    vault.deposit_direct(protocol_id, payment);
}

/// The Protocol withdraws the assets from the LiquidityLayer.
/// And update the protocol amount with protocol_id.
/// Ignore the amount if the protocol amount is less than the amount.
public fun withdraw<T>(self: &mut LiquidityLayer, protocol_id: ID, shares: Balance<YieldToken<T>>, clock: &Clock, ctx: &mut TxContext): Balance<T> {
    if (shares.value() == 0) {
        shares.destroy_zero();
        return balance::zero<T>()
    };

    let pt = type_name::get<T>();

    self.check_protocol_exists(&protocol_id);
    self.check_asset_type_exists(pt);
    
    let current_epoch = ctx.epoch();
    // let shares_value_for_event = shares.value(); // Keep for event

    // Withdraw from vault using shares
    let withdrawn_balance_t = self.withdraw_from_vault<T>(shares, clock);
    let withdrawn_value = withdrawn_balance_t.value(); // Get the actual withdrawn asset value

    // Decrement the protocol amount using the ACTUAL withdrawn asset value
    self.decrement_protocol_amount(protocol_id, withdrawn_value);

    // Emit protocol withdrawn event (using shares value as amount? Or withdrawn_value?)
    // Using withdrawn_value seems more consistent with the state update.
    layer_event::emit_protocol_withdrawn_event(self.layer_id(), protocol_id, withdrawn_value, clock.timestamp_ms(), current_epoch);

    withdrawn_balance_t
}

/// Withdraw assets directly from the vault without burning YieldToken
public(package) fun withdraw_direct<T>(
    self: &mut LiquidityLayer,
    protocol_id: ID,
    amount: u64,
): Balance<T> {
    let vault = self.borrow_vault_mut<T>();
    vault.withdraw_direct(protocol_id, amount)
}

/* ================= Governance functions ================= */

/// Register a new asset vault to the LiquidityLayer.
/// 
/// # Arguments
/// * `liquidity_layer`: The LiquidityLayer to register the asset vault to.
/// * `payload`: The payload to register the asset vault to.
/// * `ctx`: The transaction context.
/// 
/// # Ignores
/// * If the asset type is already registered.
public(package) fun register_asset_vault<T>(
    self: &mut LiquidityLayer, 
    ctx: &mut TxContext
): VaultCap<T> {
    let pt = type_name::get<T>();

    check_liquidity_layer_is_active(self);
    check_asset_type_not_exists(self, pt);

    let (vault, vault_cap) = vault::create<T>(ctx);
            
    let vault_id = vault.id();

    self.add_vault(vault_id, vault);  

    // Emit vault registered event
    layer_event::emit_vault_registered_event(self.layer_id(), vault_id, pt.into_string(), ctx.epoch_timestamp_ms(), ctx.epoch());

    vault_cap
}

/// Register a new asset vault to the LiquidityLayer by AdminCap
public fun register_vault_by_admin_cap<T>(
    self: &mut LiquidityLayer, 
    _admin_cap: &AdminCap, 
    ctx: &mut TxContext
): VaultCap<T> {
    register_asset_vault<T>(self, ctx)
}

/// Unregister an asset vault from the LiquidityLayer
/// TODO:
#[allow(unused_type_parameter)]
public fun unregister_vault<T>(
    _self: &mut LiquidityLayer, 
    _admin_cap: &AdminCap, 
    _vault_id: ID, 
    _ctx: &mut TxContext
) {
    // let pt = type_name::get<T>();
    // let yt = type_name::get<YT>();

    // self.check_liquidity_layer_is_active();
    // self.check_asset_type_exists(pt, yt);

    // // TODO: Check if the vault doesn't have any balances
    // self.remove_vault(vault_id);

    abort 0
}

/// Register a new protocol to the LiquidityLayer
/// Pause the liquidity layer
public(package) fun register_protocol(self: &mut LiquidityLayer, protocol_id: ID, protocol_type: ProtocolType, ctx: &TxContext) {
    // let pt = type_name::get<T>();

    self.check_liquidity_layer_is_active();
    // self.check_asset_type_exists(pt);
    self.check_protocol_not_exists(&protocol_id);
    
    self.add_protocol(
        protocol_id, 
        protocol::new_protocol_config(protocol_id,  0, protocol_type)
    );


    // Emit protocol registered event
    layer_event::emit_protocol_registered_event(
        self.layer_id(), 
        protocol_id, 
        ctx.epoch_timestamp_ms(), 
        ctx.epoch()
    );
}

/// Register a new protocol to the LiquidityLayer
/// Pause the liquidity layer
public fun register_protocol_by_admin_cap(self: &mut LiquidityLayer, _admin_cap: &AdminCap, protocol_id: ID, protocol_type: ProtocolType, ctx: &mut TxContext) {
    register_protocol(self, protocol_id, protocol_type, ctx)
}


/// Remove a protocol from the LiquidityLayer
public fun unregister_protocol(self: &mut LiquidityLayer, _admin_cap: &AdminCap, protocol_id: ID, ctx: &mut TxContext) {
    self.check_liquidity_layer_is_active();
    self.check_protocol_exists(&protocol_id);

    // TODO: Check if the protocol doesn't have any debts
    self.remove_protocol(protocol_id);

    // Emit protocol unregistered event
    layer_event::emit_protocol_unregistered_event(self.layer_id(), protocol_id,ctx.epoch_timestamp_ms(), ctx.epoch());
}

/* ================= Testing ================= */

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
fun destroy_liquidity_layer_for_testing(layer: LiquidityLayer) {
    let LiquidityLayer {
        id,
        vault_registry,
        asset_types: _,
        protocol_registry: _,
        dex_registry,
        status: _,
    } = layer;

    id.delete();
    vault_registry.destroy_empty();
    dex_registry.destroy_empty();
}

// ------- Unit tests ------- //
#[test]
fun test_create_liquidity_layer_should_work() {
    let mut ctx = tx_context::dummy();

    let layer = new_liquidity_layer(&mut ctx);

    assert!(layer.status == Status::Active, EInvalidLiquidityStatus);
    assert!(layer.asset_types.size() == 0, 0);

    destroy_liquidity_layer_for_testing(layer);
}

// Test Set Liquidity Layer Status
#[test]
fun test_set_liquidity_layer_status_should_work() {
    let mut ctx = tx_context::dummy();

    let mut layer = new_liquidity_layer(&mut ctx);

    set_status(&mut layer, Status::Paused);

    assert!(layer.status == Status::Paused, EInvalidLiquidityStatus);

    destroy_liquidity_layer_for_testing(layer);
}