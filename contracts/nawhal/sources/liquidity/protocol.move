
module narval::protocol;

// use std::type_name::TypeName;

use sui::balance::{Balance};
use sui::vec_map::{VecMap};

use narval::access::{VaultAccess};
use narval::common::{YieldToken};

/* ================= Errors ================= */


/* ================= Structs ================= */

public struct ProtocolConfig has copy, drop, store {
    protocol_id: ID,
    // token_a: TypeName,
    // token_b: TypeName,
    amount: u64,
    protocol_type: ProtocolType,
}

public enum ProtocolType has copy, drop, store {
    Lending,
    Vault,
    DEX,
}

/// Translate ProtocolType from u8 to ProtocolType
public fun protocol_type_from_u8(protocol_type: u8): ProtocolType {
    match (protocol_type) {
        1 => new_vault_protocol_type(),
        2 => new_dex_protocol_type(),
        _ => new_lending_protocol_type(),
    }

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

/// New a new ProtocolConfig
public fun new_protocol_config(protocol_id: ID, amount: u64, protocol_type: ProtocolType): ProtocolConfig {
    ProtocolConfig {
        protocol_id,
        // token_a,
        // token_b,
        amount,
        protocol_type,
    }
}

// /// Get asset type from protocol config
// public fun token_a(self: &ProtocolConfig): &TypeName {
//     &self.token_a
// }

// /// Get asset type from protocol config
// public fun token_b(self: &ProtocolConfig): &TypeName {
//     &self.token_b
// }

/// Get amount of protocol config
public fun amount(self: &ProtocolConfig): u64 {
    self.amount
}

/// Set amount of protocol config
public(package) fun set_amount(self: &mut ProtocolConfig, amount: u64) {
    self.amount = amount;
}

/* ================= StrategyRemovalTicket ================= */

public struct StrategyRemovalTicket<phantom T> {
    access: VaultAccess,
    returned_balance: Balance<T>,
}

public(package) fun new_strategy_removal_ticket<T>(
    access: VaultAccess,
    returned_balance: Balance<T>,
): StrategyRemovalTicket<T> {
    StrategyRemovalTicket {
        access,
        returned_balance,
    }
}

public fun extract<T>(ticket: StrategyRemovalTicket<T>): (VaultAccess, Balance<T>) {
    let StrategyRemovalTicket { access, returned_balance } = ticket;
    (access, returned_balance)
}

/* ================= WithdrawTicket ================= */

public struct StrategyWithdrawInfo<phantom T> has store {
    to_withdraw: u64,
    withdrawn_balance: Balance<T>,
    has_withdrawn: bool,
}

public struct WithdrawTicket<phantom T> {
    to_withdraw_from_available_balance: u64,
    strategy_infos: VecMap<ID, StrategyWithdrawInfo<T>>,
    lp_to_burn: Balance<YieldToken<T>>,
}

// public(package) fun withdraw_ticket_to_withdraw<T, YT>(
//     ticket: &WithdrawTicket<T, YT>,
//     access: &VaultAccess,
// ): u64 {
//     let id = access.vault_access_id();
//     let info = ticket.strategy_infos.get(&id);
//     info.to_withdraw
// }

/// New StrategyWithdrawInfo
public(package) fun new_strategy_withdraw_info<T>(
    to_withdraw: u64,
    withdrawn_balance: Balance<T>,
    has_withdrawn: bool,
): StrategyWithdrawInfo<T> {
    StrategyWithdrawInfo {
        to_withdraw,
        withdrawn_balance,
        has_withdrawn,
    }
}

/// Extract `StrategyWithdrawInfo` to its inner values
public(package) fun extract_strategy_withdraw_info<T>(self: StrategyWithdrawInfo<T>): (u64, Balance<T>, bool) {
    let StrategyWithdrawInfo { to_withdraw, withdrawn_balance, has_withdrawn } = self;
    (to_withdraw, withdrawn_balance, has_withdrawn)
}

/// Join `balance` to `lp_to_burn`
public(package) fun join_lp_to_burn<T>(self: &mut WithdrawTicket<T>, balance: Balance<YieldToken<T>>) {
    self.lp_to_burn.join(balance);
}

/// New WithdrawTicket
public(package) fun new_withdraw_ticket<T>(
    to_withdraw_from_available_balance: u64,
    strategy_infos: VecMap<ID, StrategyWithdrawInfo<T>>,
    lp_to_burn: Balance<YieldToken<T>>,
): WithdrawTicket<T> {
    WithdrawTicket {
        to_withdraw_from_available_balance,
        strategy_infos,
        lp_to_burn,
    }
}

/// Extract `WithdrawTicket` to its inner values
public(package) fun extract_withdraw_ticket<T>(self: WithdrawTicket<T>): (u64, VecMap<ID, StrategyWithdrawInfo<T>>, Balance<YieldToken<T>>) {
    let WithdrawTicket { to_withdraw_from_available_balance, strategy_infos, lp_to_burn } = self;
    (to_withdraw_from_available_balance, strategy_infos, lp_to_burn)
}

/// Get `lp_to_burn` value
public fun lp_to_burn_value<T>(self: &WithdrawTicket<T>): u64 {
    self.lp_to_burn.value()
}

/// Get `to_withdraw`
public fun to_withdraw<T>(self: &StrategyWithdrawInfo<T>): u64 {
    self.to_withdraw
}

/// Get `has_withdrawn`
public fun has_withdrawn<T>(self: &StrategyWithdrawInfo<T>): bool {
    self.has_withdrawn
}

/// Get `to_withdraw_from_available_balance`
public fun to_withdraw_from_available_balance_value<T>(self: &WithdrawTicket<T>): u64 {
    self.to_withdraw_from_available_balance
}

/// Get `strategy_infos` size
public fun strategy_infos_size<T>(self: &WithdrawTicket<T>): u64 {
    self.strategy_infos.size()
}

/// Get `strategy_infos` entry by index
public fun get_strategy_info_by_idx<T>(self: &WithdrawTicket<T>, idx: u64): (&ID, &StrategyWithdrawInfo<T>) {
    self.strategy_infos.get_entry_by_idx(idx)
}

/// Get mut `strategy_infos`
public fun get_mut_strategy_info<T>(self: &mut WithdrawTicket<T>, strategy_id: &ID): &mut StrategyWithdrawInfo<T> {
    self.strategy_infos.get_mut(strategy_id)
}

/// Get `strategy_infos`
public fun get_strategy_info<T>(self: &WithdrawTicket<T>, strategy_id: &ID): &StrategyWithdrawInfo<T> {
    self.strategy_infos.get(strategy_id)
}

/// Set `to_withdraw`
public(package) fun set_to_withdraw<T>(self: &mut StrategyWithdrawInfo<T>, to_withdraw: u64) {
    self.to_withdraw = to_withdraw;
}

/// Set `has_withdrawn`
public(package) fun set_has_withdrawn<T>(self: &mut StrategyWithdrawInfo<T>, has_withdrawn: bool) {
    self.has_withdrawn = has_withdrawn;
}

/// Set `to_withdraw_from_available_balance`
public(package) fun set_to_withdraw_from_available_balance<T>(self: &mut WithdrawTicket<T>, to_withdraw: u64) {
    self.to_withdraw_from_available_balance = to_withdraw;
}

/// Join `withdrawn_balance`
public fun join_withdrawn_balance<T>(self: &mut StrategyWithdrawInfo<T>, balance: Balance<T>) {
    self.withdrawn_balance.join(balance);
}

/* ================= RebalanceInfo ================= */

public struct RebalanceInfo has store, copy, drop {
    /// The target amount the strategy should repay. The strategy shouldn't
    /// repay more than this amount.
    to_repay: u64,
    /// The target amount the strategy should borrow. There's no guarantee
    /// though that this amount is available in vault's free balance. The
    /// strategy shouldn't borrow more than this amount.
    can_borrow: u64,
}

public struct RebalanceAmounts has copy, drop {
    inner: VecMap<ID, RebalanceInfo>,
}

public(package) fun rebalance_amounts_get(
    amounts: &RebalanceAmounts,
    access: &VaultAccess,
): (u64, u64) {
    let strategy_id = access.vault_access_id();
    let amts = amounts.inner.get(&strategy_id);
    (amts.can_borrow, amts.to_repay)
}

/// New RebalanceInfo
public(package) fun new_rebalance_info(
    can_borrow: u64,
    to_repay: u64,
): RebalanceInfo {
    RebalanceInfo { can_borrow, to_repay }
}

/// New RebalanceAmounts
public(package) fun new_rebalance_amounts(
    inner: VecMap<ID, RebalanceInfo>,
): RebalanceAmounts {
    RebalanceAmounts { inner }
}
/// Set `to_repay`
public(package) fun set_to_repay(self: &mut RebalanceInfo, to_repay: u64) {
    self.to_repay = to_repay;
}

/// Set `can_borrow`
public(package) fun set_can_borrow(self: &mut RebalanceInfo, can_borrow: u64) {
    self.can_borrow = can_borrow;
}

/* ================= StrategyState ================= */

public struct StrategyState has store {
    borrowed: u64,
    target_alloc_weight_bps: u64,
    max_borrow: Option<u64>,
}

/// Create a new `StrategyState`
public fun new_strategy_state(
    borrowed: u64,
    target_alloc_weight_bps: u64,
    max_borrow: Option<u64>,
): StrategyState {
    StrategyState {
        borrowed,
        target_alloc_weight_bps,
        max_borrow,
    }
}

/// Get the `borrowed` amount of a strategy
public fun borrowed(self: &StrategyState): u64 {
    self.borrowed
}

/// Get the `target_alloc_weight_bps` of a strategy
public fun target_alloc_weight_bps(self: &StrategyState): u64 {
    self.target_alloc_weight_bps
}

/// exists `max_borrow`
public fun exists_max_borrow(self: &StrategyState): bool {
    option::is_some(&self.max_borrow)
}

/// Get the `max_borrow` amount of a strategy
/// Aborts if `max_borrow` is `None`
public fun max_borrow(self: &StrategyState): u64 {
    *option::borrow(&self.max_borrow)
}

// /// Subtract `amount` from `borrowed`
// public(package) fun subtract_from_borrowed(self: &mut StrategyState, amount: u64) {
//     self.borrowed = self.borrowed - amount;
// }

/// Set the `borrowed` amount of a strategy
public(package) fun set_borrowed(self: &mut StrategyState, borrowed: u64) {
    self.borrowed = borrowed;
}

/// Set the `max_borrow` amount of a strategy
public(package) fun set_max_borrow(self: &mut StrategyState, max_borrow: Option<u64>) {
    self.max_borrow = max_borrow;
}

/// Set the `target_alloc_weight_bps` of a strategy
public(package) fun set_target_alloc_weight_bps(self: &mut StrategyState, target_alloc_weight_bps: u64) {
    self.target_alloc_weight_bps = target_alloc_weight_bps;
}

/// Extract the `StrategyState` to its inner values
public(package) fun extract_strategy_state(self: StrategyState): (u64, u64, Option<u64>) {
    let StrategyState { borrowed, target_alloc_weight_bps, max_borrow } = self;
    (borrowed, target_alloc_weight_bps, max_borrow)
}

