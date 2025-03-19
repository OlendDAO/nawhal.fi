
module nawhal::staking;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::vec_map::{Self, VecMap};
use sui::vec_set::{Self, VecSet};

use nawhal::account_ds::{AccountProfileCap, AccountRegistry};
use nawhal::vault::{Self, Vault};

// ------ Errors ------ //
const ENotEnoughStakingValue: u64 = 0;

/// The global registry of the staking vaults
public struct StakingRegistry has key {
    id: UID,
    // Store the (account_id, [vault_id]) pair
    stake_infos: VecMap<ID, VecSet<ID>>,
}

fun init(ctx: &mut TxContext) {
    initialize(ctx);
}

public(package) fun initialize(ctx: &mut TxContext) {
    let registry = StakingRegistry {
        id: object::new(ctx),
        stake_infos: vec_map::empty(),
    };

    transfer::share_object(registry);
}

// ------ Staking ------ //

/// Deposit balance into the `Vault`, and update the account profile 
public fun deposit<T, LPT>(
    vault: &mut Vault<T, LPT>,
    account_cap: &mut AccountProfileCap,
    staking_registry: &mut StakingRegistry,
    account_registry: &mut AccountRegistry,
    collateral: Balance<T>,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    vault.assert_version();
    vault.assert_status();
    if (collateral.value() == 0) {
        collateral.destroy_zero();
    } else {
        let account_id = account_cap.account_of();
        let profile = account_registry.borrow_account_mut(account_id);
        profile.add_staking_value<T>(vault.vault_id(), collateral.value());
        profile.update_latest_updated_ms(clock.timestamp_ms());

        add_staking_info(staking_registry, account_id, vault.vault_id());

        vault::emit_deposited_event<T>(
            account_id,
            vault.vault_id(),
            collateral.value(),
            clock.timestamp_ms(),
        );

        vault.borrow_collateral_mut().join(collateral);   
        vault.assert_tvl_cap();
    };
}

/// Withdraw from the `Vault`, and update the account profile
public fun withdraw<T, LPT>(
    vault: &mut Vault<T, LPT>,
    account_cap: &mut AccountProfileCap,
    staking_registry: &mut StakingRegistry,
    account_registry: &mut AccountRegistry,
    amount: u64,
    clock: &Clock,
    _ctx: &mut TxContext,
): Balance<T> {
    vault.assert_version();
    vault.assert_status();
    
    if (amount == 0) {
        balance::zero()
    } else {
        let account_id = account_cap.account_of();
        let profile = account_registry.borrow_account_mut(account_id);

        let stake_info = profile.get_staking_info(&vault.vault_id()).extract();

        validate_withdraw_amount(stake_info.staking_value(), amount);

        // If the withdraw amount is equal to the staking value, remove the staking info,
        // remove the staking info from the account profile and staking registry
        if (stake_info.staking_value() == amount) {
            profile.remove_staking_info(vault.vault_id());
            staking_registry.remove_staking_info(account_id, vault.vault_id());
        } else {
            profile.sub_staking_value(vault.vault_id(), amount);
        };

        profile.update_latest_updated_ms(clock.timestamp_ms());

        vault::emit_withdrawn_event<T>(
            account_id,
            vault.vault_id(),
            amount,
            clock.timestamp_ms(),
        );

        vault.borrow_collateral_mut().split(amount)  
    }
}

// /// Delegate Collateral to a Pool    TODO:
// public fun delegate_collateral<T, YT>(
//     vault: &mut Vault<T, YT>,
//     payment: Balance<T>,
//     clock: &Clock,
// ) {
//     // TODO: implement
// }

/// Add the account id and vault id to the staking registry
public(package) fun add_staking_info(
    self: &mut StakingRegistry,
    account_id: ID,
    vault_id: ID,
) {
    if (self.stake_infos.contains(&account_id)) {
        let vaults = self.stake_infos.get_mut(&account_id);
        vaults.insert(vault_id);
    } else {
        let vaults = vec_set::singleton(vault_id);
        self.stake_infos.insert(account_id, vaults);
    }
}

/// Remove the staking info from the staking registry
public(package) fun remove_staking_info(
    self: &mut StakingRegistry,
    account_id: ID,
    vault_id: ID,
) {
    let vaults = self.stake_infos.get_mut(&account_id);
    vaults.remove(&vault_id);
}

/// Check if registry contains the account id and vault id
public(package) fun contains(
    self: &StakingRegistry,
    account_id: &ID,
    vault_id: &ID,
):bool {
    let vaults = self.stake_infos.get(account_id);
    vaults.contains(vault_id)
}

/// Validate the withdraw amount
public(package) fun validate_withdraw_amount(
    stake_value: u64,
    amount: u64,
) {
    assert!(stake_value >= amount, ENotEnoughStakingValue);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    initialize(ctx);
}
