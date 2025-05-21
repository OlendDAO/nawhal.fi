//! Event module for liquidity layer

module narval::layer_event;

use std::ascii::String;

use sui::event::emit;

// ------ Events ------ //
/// LiquidityLayerCreatedEvent is emitted when a new liquidity layer is created.
public struct LiquidityLayerCreatedEvent has copy, drop, store {
    layer_id: ID,
    created_at_ms: u64,
    created_at_epoch: u64,
}

/// ProtocolDepositedEvent is emitted when a protocol deposits assets to the liquidity layer.
public struct ProtocolDepositedEvent has copy, drop, store {
    layer_id: ID,
    protocol_id: ID,
    amount: u64,
    deposited_at_ms: u64,
    deposited_at_epoch: u64,
}

/// ProtocolWithdrawnEvent is emitted when a protocol withdraws assets from the liquidity layer.
public struct ProtocolWithdrawnEvent has copy, drop, store {
    layer_id: ID,
    protocol_id: ID,
    amount: u64,
    withdrawn_at_ms: u64,
    withdrawn_at_epoch: u64,
}

/// VaultRegisteredEvent is emitted when a new vault is registered.
public struct VaultRegisteredEvent has copy, drop, store {
    layer_id: ID,
    vault_id: ID,
    asset_type: String,
    registered_at_ms: u64,
    registered_at_epoch: u64,
}

/// ProtocolRegisteredEvent is emitted when a new protocol is registered.
public struct ProtocolRegisteredEvent has copy, drop, store {
    layer_id: ID,
    protocol_id: ID,
    registered_at_ms: u64,
    registered_at_epoch: u64,
}  

/// ProtocolUnregisteredEvent is emitted when a protocol is unregistered.
public struct ProtocolUnregisteredEvent has copy, drop, store {
    layer_id: ID,
    protocol_id: ID,
    unregistered_at_ms: u64,
    unregistered_at_epoch: u64,
}

/// LiquidityLayerPausedEvent is emitted when a liquidity layer is paused.
public struct LiquidityLayerPausedEvent has copy, drop, store {
    layer_id: ID,
    old_status: String,
    new_status: String,
    paused_at_ms: u64,
    paused_at_epoch: u64,
}

/// LiquidityLayerResumedEvent is emitted when a liquidity layer is resumed.
public struct LiquidityLayerResumedEvent has copy, drop, store {
    layer_id: ID,
    old_status: String,
    new_status: String,
    resumed_at_ms: u64,
    resumed_at_epoch: u64,
}
// ------ Event emitters ------ //
/// LiquidityLayerCreatedEvent is emitted when a new liquidity layer is created.
/// Emit LiquidityLayerCreatedEvent
public fun emit_liquidity_layer_created_event(layer_id: ID, created_at_ms: u64, created_at_epoch: u64) {
    let event = LiquidityLayerCreatedEvent {
        layer_id,
        created_at_ms,
        created_at_epoch,
    };

    emit(event);
}

/// Emit ProtocolDepositedEvent
public fun emit_protocol_deposited_event(layer_id: ID, protocol_id: ID, amount: u64, deposited_at_ms: u64, deposited_at_epoch: u64) {
    let event = ProtocolDepositedEvent {
        layer_id,
        protocol_id,
        amount,
        deposited_at_ms,
        deposited_at_epoch,
    };

    emit(event);
}

/// Emit ProtocolWithdrawnEvent
public fun emit_protocol_withdrawn_event(layer_id: ID, protocol_id: ID, amount: u64, withdrawn_at_ms: u64, withdrawn_at_epoch: u64) {
    let event = ProtocolWithdrawnEvent {
        layer_id,
        protocol_id,
        amount,
        withdrawn_at_ms,
        withdrawn_at_epoch,
    };

    emit(event);
}

/// Emit LiquidityLayerPausedEvent
public fun emit_liquidity_layer_paused_event(layer_id: ID, old_status: String, new_status: String, paused_at_ms: u64, paused_at_epoch: u64) {
    let event = LiquidityLayerPausedEvent {
        layer_id,
        old_status,
        new_status,
        paused_at_ms,
        paused_at_epoch,
    };

    emit(event);
}

/// Emit LiquidityLayerResumedEvent
public fun emit_liquidity_layer_resumed_event(layer_id: ID, old_status: String, new_status: String, resumed_at_ms: u64, resumed_at_epoch: u64) {
    let event = LiquidityLayerResumedEvent {
        layer_id,
        old_status,
        new_status,
        resumed_at_ms,
        resumed_at_epoch,
    };

    emit(event);
}

/// Emit VaultRegisteredEvent
public fun emit_vault_registered_event(layer_id: ID, vault_id: ID, asset_type: String, registered_at_ms: u64, registered_at_epoch: u64) {
    let event = VaultRegisteredEvent {
        layer_id,
        vault_id,
        asset_type,
        registered_at_ms,
        registered_at_epoch,
    };

    emit(event);
}

/// Emit ProtocolRegisteredEvent
public fun emit_protocol_registered_event(layer_id: ID, protocol_id: ID, registered_at_ms: u64, registered_at_epoch: u64) {
    let event = ProtocolRegisteredEvent {
        layer_id,
        protocol_id,
        registered_at_ms,
        registered_at_epoch,
    };

    emit(event);
}

/// Emit ProtocolUnregisteredEvent
public fun emit_protocol_unregistered_event(layer_id: ID, protocol_id: ID, unregistered_at_ms: u64, unregistered_at_epoch: u64) {
    let event = ProtocolUnregisteredEvent {
        layer_id,
        protocol_id,
        unregistered_at_ms,
        unregistered_at_epoch,
    };

    emit(event);
}
