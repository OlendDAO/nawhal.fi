
module narval::position;

use std::type_name::{Self, TypeName};
use sui::balance::Balance;

// ------- Structs ------- //
/// The staking info of a vault
public struct StakingInfo<phantom T, phantom YT> has store {
    lending_protocol_id: ID,
    account_id: ID,
    asset_type: TypeName,
    /// The shares after staked 
    shares: Balance<YT>,
    /// The total amount of the staking `T
    total_asset_amount: u64,
    latest_updated_ms: u64,
}

// ------- Constructors ------- //
/// New a new StakingInfo
public fun new_staking_info<T, YT>(
    lending_protocol_id: ID,
    account_id: ID,
    total_asset_amount: u64,
    shares: Balance<YT>,
    latest_updated_ms: u64,
): StakingInfo<T, YT> {
    StakingInfo {
        lending_protocol_id,
        account_id,
        asset_type: type_name::get<T>(),
        shares,
        total_asset_amount,
        latest_updated_ms,
    }
}

// ------- Setters ------- //
/// Take shares from the staking info
public(package) fun take_shares<T, YT>(self: &mut StakingInfo<T, YT>, amount: u64, timestamp_ms: u64): Balance<YT> {
    self.sub_asset_amount(amount);
    self.update_latest_updated_ms(timestamp_ms);
    self.shares.split(amount)
}

/// Add shares to the staking info
public(package) fun add_shares<T, YT>(self: &mut StakingInfo<T, YT>, shares: Balance<YT>, timestamp_ms: u64) {
    self.add_asset_amount(shares.value());  
    self.update_latest_updated_ms(timestamp_ms);
    self.shares.join(shares);
}

/// Add asset amount to the staking info
public(package) fun add_asset_amount<T, YT>(self: &mut StakingInfo<T, YT>, amount: u64) {
    self.total_asset_amount = self.total_asset_amount + amount;
}

/// Subtract asset amount from the staking info
public(package) fun sub_asset_amount<T, YT>(self: &mut StakingInfo<T, YT>, amount: u64) {
    self.total_asset_amount = self.total_asset_amount - amount;
}

/// Update the latest updated ms
public(package) fun update_latest_updated_ms<T, YT>(self: &mut StakingInfo<T, YT>, latest_updated_ms: u64) {
    self.latest_updated_ms = latest_updated_ms;
}

// ------- Getters ------- //
/// Get staking total amount
public fun total_asset_amount<T, YT>(self: &StakingInfo<T, YT>): u64 {
    self.total_asset_amount
}

/// Get shares value
public fun shares_value<T, YT>(self: &StakingInfo<T, YT>): u64 {
    self.shares.value()
}

/// Get staking type
public fun staking_asset_type<T, YT>(self: &StakingInfo<T, YT>): TypeName {
    self.asset_type
}