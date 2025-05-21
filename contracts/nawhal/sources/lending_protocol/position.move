
module narval::position;

use std::type_name::{Self, TypeName};

use sui::balance::Balance;
use sui::vec_map::VecMap;

use narval::common::{YieldToken};

// ------- Structs ------- //
/// The staking info of a vault
public struct StakingInfo<phantom T> has store {
    lending_protocol_id: ID,
    account_id: ID,
    asset_type: TypeName,
    /// The shares after staked 
    shares: Balance<YieldToken<T>>,
    /// The total amount of the staking `T
    total_asset_amount: u64,
    latest_updated_ms: u64,
}

// Position config
public struct PositionConfig<phantom T, phantom DT> has store, copy, drop {
    // The Net APY earning from the vault (supply interest - borrow interest)
    net_apy_bps: u64, // net apy in basis points
    // Represents what percentage of the collateral can be borrowed against Sometimes called LTV (Loan to Value)
    collateral_factor_bps: u64,
    // The ratio at which the position would be considered undercollateralized and Could be liquidated.
    liquidation_threshold_bps: u64,
    // The threshold above which 100% of your position gets liquidated instantly.
    liquidation_max_limit_bps: u64, // Not allow >  100%
    // The collateral price at which the position would be considered undercollateralized and could be liquidated.
    // Generally represented as liquidation price/current price of collateral.
    liquidation_price: u64,
    // This is the penalty on your collateral asset for liquidating the position, 
    // that has crossed the liquidation threshold, just until the threshold
    liquidation_penalty_bps: u64,
    // This is the Debt to Collateral ratio. Dollar value of Debt / Dollar value of Collateral or D/C ratio
    ratio_bps: u64, 
    // Rate earned per year for supplying the collateral asset
    supply_apr_bps: u64,
    // Rate to be paid per year for borrowing the debt asset
    borrow_apr_bps: u64,
}

// Withdrawal config
public struct WithdrawalConfig has store, copy, drop {
    // The minimum limit for a Vault's withdrawal. The further expansion happens on this base
    base_limit: u64,
    // The limit until where you can withdraw. If it is $0 that means 100% of the users can withdraw
    current_limit: u64,
    // The rate at which Limits would increase or decrease over the given
    expand_percentage: u64,
    // The time for which the limits expand at the given rate
    expand_duration_ms: u64,
    // Amount available for instant withdrawal
    withdrawable_amount: u64,
    // Safety non-withdrawable amount to guarantee liquidations
    withdrawable_gap: u64,
}

// Borrow config
public struct BorrowConfig has store, copy, drop {
    // The minimum limit for a Vault's borrowing. The further expansion happens on this base
    base_limit: u64,
    // The limit until where you can borrow
    current_limit: u64,
    // Maximum limit for a vault above which it is not possible to borrow
    max_limit: u64,
    // The rate at which Limits would increase or decrease over the given duration
    expand_percentage: u64,
    // The time for which the limits expand at the given rate
    expand_duration_ms: u64,
    // Amount available for instant borrow
    withdrawable_gap: u64,
}

/// Position data, includes collateral and debt
public struct Position<phantom T, phantom DT> has key, store {
    id: UID,
    vault_protocol_id: ID,
    account_id: ID,
    collateral: Collateral<T>,
    debt: Debt<DT>,
    config: PositionConfig<T, DT>,
}

/// The staking info of a vault
public struct Collateral<phantom T> has store, copy, drop { 
    /// The total amount of the staking `T
    asset_amount: u64,
    latest_updated_ms: u64,
}

/// Debt info
public struct Debt<phantom DT> has store, copy, drop {
    /// The total amount of the debt
    debt_amount: u64,
    latest_updated_ms: u64,
}

/// The tick info of a vault
public struct Tick has store, copy, drop {
    /// The ratio of debt to collateral
    ratio_bps: u64,
    /// The lowest price of the tick
    low_price: u64,
    /// The highest price of the tick
    high_price: u64,
    /// Stores the (position id, account id)
    positions: VecMap<ID, ID>,
    timestamp: u64,
}

// ------- Constructors ------- //
/// New a new StakingInfo
public fun new_staking_info<T>(
    lending_protocol_id: ID,
    account_id: ID,
    total_asset_amount: u64,
    shares: Balance<YieldToken<T>>,
    latest_updated_ms: u64,
): StakingInfo<T> {
    StakingInfo {
        lending_protocol_id,
        account_id,
        asset_type: type_name::get<T>(),
        shares,
        total_asset_amount,
        latest_updated_ms,
    }
}

public fun new_position_config<T, DT>(
    net_apy_bps: u64,
    collateral_factor_bps: u64,
    liquidation_threshold_bps: u64,
    liquidation_max_limit_bps: u64,
    liquidation_price: u64,
    liquidation_penalty_bps: u64,
    ratio_bps: u64, 
    supply_apr_bps: u64,
    borrow_apr_bps: u64,
): PositionConfig<T, DT> {
    PositionConfig {
        net_apy_bps,
        collateral_factor_bps,
        liquidation_threshold_bps,
        liquidation_max_limit_bps,
        liquidation_price,
        liquidation_penalty_bps,
        ratio_bps,
        supply_apr_bps,
        borrow_apr_bps,
    }
}

public fun new_withdrawal_config(
    base_limit: u64,
    current_limit: u64,
    expand_percentage: u64,
    expand_duration_ms: u64,
    withdrawable_amount: u64,
    withdrawable_gap: u64,
): WithdrawalConfig {
    WithdrawalConfig {
        base_limit,
        current_limit,
        expand_percentage,
        expand_duration_ms,
        withdrawable_amount,
        withdrawable_gap,
    }
}

public fun new_borrow_config(
    base_limit: u64,
    current_limit: u64,
    max_limit: u64,
    expand_percentage: u64,
    expand_duration_ms: u64,
    withdrawable_gap: u64,
): BorrowConfig {
    BorrowConfig {
        base_limit,
        current_limit,
        max_limit,
        expand_percentage,
        expand_duration_ms,
        withdrawable_gap,
    }
}

public fun new_position<T, DT>(
    vault_protocol_id: ID,
    account_id: ID,
    collateral: Collateral<T>,
    debt: Debt<DT>,
    config: PositionConfig<T, DT>,
    ctx: &mut TxContext,
): Position<T, DT> {
    Position {
        id: object::new(ctx),
        vault_protocol_id,
        account_id,
        collateral,
        debt,
        config,
    }
}

public fun new_collateral<T>(
    asset_amount: u64,
    latest_updated_ms: u64,
): Collateral<T> {
    Collateral {
        asset_amount,
        latest_updated_ms,
    }
}

public fun new_debt<DT>(
    debt_amount: u64,
    latest_updated_ms: u64,
): Debt<DT> {
    Debt {
        debt_amount,
        latest_updated_ms,
    }
}

public fun new_tick(
    ratio_bps: u64,
    low_price: u64,
    high_price: u64,
    positions: VecMap<ID, ID>,
    timestamp: u64,
): Tick {   
    Tick {
        ratio_bps,
        low_price,
        high_price,
        positions,
        timestamp,
    }
}

// ------- Setters ------- //
/// Take shares from the staking info
public(package) fun take_shares<T>(self: &mut StakingInfo<T>, amount: u64, timestamp_ms: u64): Balance<YieldToken<T>> {
    self.sub_asset_amount(amount);
    self.update_latest_updated_ms(timestamp_ms);
    self.shares.split(amount)
}

/// Add shares to the staking info
public(package) fun add_shares<T>(self: &mut StakingInfo<T>, shares: Balance<YieldToken<T>>, timestamp_ms: u64) {
    self.add_asset_amount(shares.value());  
    self.update_latest_updated_ms(timestamp_ms);
    self.shares.join(shares);
}

/// Add asset amount to the staking info
fun add_asset_amount<T>(self: &mut StakingInfo<T>, amount: u64) {
    self.total_asset_amount = self.total_asset_amount + amount;
}

/// Subtract asset amount from the staking info
 fun sub_asset_amount<T>(self: &mut StakingInfo<T>, amount: u64) {
    self.total_asset_amount = self.total_asset_amount - amount;
}

/// Update the latest updated ms
public(package) fun update_latest_updated_ms<T>(self: &mut StakingInfo<T>, latest_updated_ms: u64) {
    self.latest_updated_ms = latest_updated_ms;
}

/// Add debt amount to the position
public(package) fun add_debt<T, DT>(self: &mut Position<T, DT>, debt_amount: u64) {
    self.debt.debt_amount = self.debt.debt_amount + debt_amount;
}



// ------- Getters ------- //
/// Get staking total amount
public fun total_asset_amount<T>(self: &StakingInfo<T>): u64 {
    self.total_asset_amount
}

/// Get shares value
public fun shares_value<T>(self: &StakingInfo<T>): u64 {
    self.shares.value()
}

/// Get staking type
public fun staking_asset_type<T>(self: &StakingInfo<T>): TypeName {
    self.asset_type
}

/// Get ratio bps
public fun ratio_bps<T, DT>(self: &PositionConfig<T, DT>): u64 {
    self.ratio_bps
}