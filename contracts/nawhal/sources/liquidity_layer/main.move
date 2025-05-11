
module narval::liquidity_layer_main;

use sui::clock::Clock;
use sui::vec_set::{Self};

use narval::vault::Vault;
use narval::access::{Self, AdminCap, VaultAccess};
use narval::protocol::{Self, StrategyRemovalTicket};

/* ================= constants ================= */

const BPS_IN_100_PCT: u64 = 10000;

/* ================= errors ================= */
const EInvalidWeights: u64 = 0;

/* ================= Admin ================= */
entry fun set_strategy_max_borrow<T, YT>(
    _cap: &AdminCap<YT>,
    vault: &mut Vault<T, YT>,
    strategy_id: ID,
    max_borrow: Option<u64>,
) {
    vault.assert_version();

    let state = vault.get_mut_strategy_state(&strategy_id);
    state.set_max_borrow(max_borrow);
}


entry fun set_strategy_target_alloc_weights_bps<T, YT>(
    _cap: &AdminCap<YT>,
    vault: &mut Vault<T, YT>,
    ids: vector<ID>,
    weights_bps: vector<u64>,
) {
    vault.assert_version();

    let mut ids_seen = vec_set::empty<ID>();
    let mut total_bps = 0;

    let mut i = 0;
    let n = vault.strategies_size();

    assert!(n == ids.length(), EInvalidWeights);
    assert!(n == weights_bps.length(), EInvalidWeights);

    while (i < n) {
        let id = ids[i];
        let weight = weights_bps[i];
        ids_seen.insert(id); // checks for duplicate ids
        total_bps = total_bps + weight;

        let state = vault.get_mut_strategy_state(&id);
        state.set_target_alloc_weight_bps(weight);

        i = i + 1;
    };

    assert!(total_bps == BPS_IN_100_PCT, EInvalidWeights);
}

public fun remove_strategy<T, YT>(
    cap: &AdminCap<YT>,
    vault: &mut Vault<T, YT>,
    ticket: StrategyRemovalTicket<T, YT>,
    ids_for_weights: vector<ID>,
    weights_bps: vector<u64>,
    clock: &Clock,
) {
    vault.assert_version();

    // extract the ticket and destroy the access
    let (access, mut returned_balance) = ticket.extract();
    let id = access.vault_access_id();

    access.destroy_vault_access();

    // remove from strategies and return balance
    let (_, state) = vault.remove_strategy(&id);

    let (borrowed, _, _) = state.extract_strategy_state();

    let returned_value = returned_balance.value();
    if (returned_value > borrowed) {
        let profit = returned_balance.split(
            returned_value - borrowed,
        );

        vault.top_up_time_locked_profit(profit, clock);
    };

    vault.join_free_balance(returned_balance);

    // remove from withdraw priority order
    // let (has, idx) = vault.strategy_withdraw_priority_order_index_of(&id);

    // assert!(has, EInvariantViolation);

    vault.remove_strategy_from_withdraw_priority_order(&id);

    // set new weights
    set_strategy_target_alloc_weights_bps(cap, vault, ids_for_weights, weights_bps);
}

public(package) fun add_strategy<T, YT>(
    _cap: &AdminCap<YT>,
    vault: &mut Vault<T, YT>,
    ctx: &mut TxContext,
): VaultAccess {
    vault.assert_version();

    let access = access::new_vault_access(ctx);
    let strategy_id = access.vault_access_id();

    let target_alloc_weight_bps = if (vault.strategies_size() == 0) {
        BPS_IN_100_PCT
    } else {
        0
    };

    vault.insert_strategy(
        strategy_id,
        protocol::new_strategy_state(0, target_alloc_weight_bps, option::none()),
    );

    vault.add_strategy_to_withdraw_priority_order(strategy_id);

    access
}

