

module narval::vault_protocol;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::table::{Self, Table};

use narval::account_ds::{AccountProfileCap, AccountRegistry};
use narval::liquidity_layer_model::{LiquidityLayer};
use narval::oracle::OracleRegistry;
use narval::position::{Self, Position, PositionConfig, Tick, WithdrawalConfig, BorrowConfig};


// ------- Errors ------- //
const EWithdrawAmountTooLarge: u64 = 30001;

// ----- Structs ----- //
/// Vault protocol is a protocol that allows users to borrow assets(Debt) from the protocol with collateral
public struct VaultProtocol<phantom T, phantom YT, phantom DT> has key, store {
    id: UID,
    supply: u64,
    supply_cap: u64,
    /// The shares after staked 
    shares: Balance<YT>,
    // Stores the (account id, posistion)
    positions: Table<ID, Position<T, DT>>,

    // Ticks for liquidation, the tick should be store the ratio (debt/collateral value) TODO:
    ticks: Table<ID, Tick>,

    // position config
    position_config: PositionConfig<T, DT>,
    withdrawal_config: WithdrawalConfig,
    borrow_config: BorrowConfig,

    status: Status,
    created_at_ms: u64,
    created_at_epoch: u64,
}

public enum Status has copy, drop, store {
    Active,
    Paused,
    WithdrawalAndPayBack,
    Closed,
}

// ------- Logic ------- //
// /// Deposit assets to the protocol
// /// TODO: Add Oracle support
// public fun deposit_collateral<T, YT, DT>(
//     self: &mut VaultProtocol<T, YT, DT>, 
//     liquidity_layer: &mut LiquidityLayer, 
//     registry: &mut AccountRegistry, 
//     payload: Coin<T>, 
//     price_object: &PriceObject,     // Replace with Pyth oracle
//     clock: &Clock, 
//     ctx: &mut TxContext
// ) {
//     let protocol_id = self.protocol_id();

//     let profile = registry.borrow_or_create_profile(clock, ctx);
//     let account_id = profile.account_id();

//     self.supply = self.supply + payload.value();

//     assert!(self.supply <= self.supply_cap, ESupplyCapReached);

//     let now = clock.timestamp_ms();
//     profile.add_lending_protocol(protocol_id);
//     profile.update_latest_updated_ms(now);
    
//     let asset_amount = payload.value();
//     let shares = liquidity_layer::deposit<T, YT>(liquidity_layer, protocol_id, payload.into_balance(), clock, ctx);

//     self.shares.join (shares);

//     // Update collateral info in position data TODO:
// }

// /// Borrow a specified amount of a given asset from the vault, with the collateral shares(T).
// /// TODO: Replace with Pyth oracle
// public fun borrow<T, YT, DT, DYT>(
//     self: &mut VaultProtocol<T, YT, DT>,
//     liquidity_layer: &mut LiquidityLayer,
//     _registry: &mut AccountRegistry,
//     oracle_registry: &mut OracleRegistry,
//     collateral_shares: Balance<YT>,
//     withdraw_amount: u64,
//     account_cap: &AccountProfileCap,
//     _clock: &Clock,
//     _ctx: &mut TxContext
// ): Balance<DT> {
//     // Get the collateral price for Pyth oracle
//     let price = oracle_registry.get_price<T>();

//     // Step 1: Check withdraw amount is less then collateral value % Ratio
//     let collateral_vault = liquidity_layer.borrow_vault<T, YT>();
//     let collateral_value = collateral_vault.calc_withdraw_by_shares(collateral_shares.value());

//     assert!(withdraw_amount <= collateral_value * price * self.position_config.ratio_bps() / 10000, EWithdrawAmountTooLarge);

//     // Step 2: Add debt to the position
//     let position = self.positions.borrow_mut(account_cap.account_of());
//     position.add_debt(withdraw_amount);

//     // Step 3: Join the collateral shares to the vault protocol
//     self.shares.join(collateral_shares);
    
//     // Step 4: Borrow the asset from liquidity layer
//     liquidity_layer.borrow<DT, DYT>(withdraw_amount)
// }

// ------- Helpers ------- //
/// Borrow or create a position
public fun borrow_or_create_position<T, YT, DT>(
    self: &mut VaultProtocol<T, YT, DT>,
    account_id: ID,
    collateral_amount: u64,
    debt_amount: u64,
    timestamp_ms: u64,
    ctx: &mut TxContext
): &mut Position<T, DT> {
    if (self.positions.contains(account_id)) {
        self.positions.borrow_mut(account_id)
    } else {
        let collateral = position::new_collateral(collateral_amount, timestamp_ms);
        let debt = position::new_debt(debt_amount, timestamp_ms);
        let position = position::new_position(self.protocol_id(), account_id, collateral, debt, self.position_config, ctx);

        self.positions.add(account_id, position);
        self.positions.borrow_mut(account_id)
    }
}

// ------- Constructors ------- //
public fun new_vault_protocol<T, YT, DT>(
    supply: u64,
    supply_cap: u64,
    position_config: PositionConfig<T, DT>,
    withdrawal_config: WithdrawalConfig,
    borrow_config: BorrowConfig,
    status: Status,
    created_at_ms: u64,
    created_at_epoch: u64,
    ctx: &mut TxContext
): VaultProtocol<T, YT, DT> {
    VaultProtocol {
        id: object::new(ctx),
        supply,
        supply_cap,
        shares: balance::zero(),
        positions: table::new(ctx),
        ticks: table::new(ctx),
        position_config,
        withdrawal_config,
        borrow_config,
        status,
        created_at_ms,
        created_at_epoch,
    }
}

// ------- Getters ------- //
public fun protocol_id<CT, YT, DT>(self: &VaultProtocol<CT, YT, DT>): ID {
    object::id(self)
}

