

module narval::market;

use std::type_name::TypeName;

use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::event;
use sui::vec_map::{Self, VecMap};

use narval::access::{Self, ActionRequest};
use narval::account_ds::AccountRegistry;
use narval::debt::{Self, DebtRegistry, DebtShareBalance};
use narval::debt_bag::{Self, DebtBag};
use narval::liquidity::{LiquidityLayer};
use narval::piecewise::Piecewise;
use narval::util;


public use fun fds_facil_id as FacilDebtShare.facil_id;
public use fun fds_borrow_inner as FacilDebtShare.borrow_inner;
public use fun fds_value_x64 as FacilDebtShare.value_x64;
public use fun fds_split_x64 as FacilDebtShare.split_x64;
public use fun fds_split as FacilDebtShare.split;
public use fun fds_withdraw_all as FacilDebtShare.withdraw_all;
public use fun fds_join as FacilDebtShare.join;
public use fun fds_destroy_zero as FacilDebtShare.destroy_zero;

public use fun fdb_add as FacilDebtBag.add;
public use fun fdb_take_amt as FacilDebtBag.take_amt;
public use fun fdb_take_all as FacilDebtBag.take_all;
public use fun fdb_get_share_amount_by_asset_type as FacilDebtBag.get_share_amount_by_asset_type;
public use fun fdb_get_share_amount_by_share_type as FacilDebtBag.get_share_amount_by_share_type;
public use fun fdb_get_share_type_for_asset as FacilDebtBag.get_share_type_for_asset;
public use fun fdb_is_empty as FacilDebtBag.is_empty;
public use fun fdb_destroy_empty as FacilDebtBag.destroy_empty;

/* ================= constants ================= */

// Seconds in a year
const SECONDS_IN_YEAR: u128 = 365 * 24 * 60 * 60;

const MODULE_VERSION: u16 = 1;

/* ================= errors ================= */

/// The share treasury for the supply shares must be empty, without any outstanding shares.
const EShareTreasuryNotEmpty: u64 = 0;
/// The provided repay balance does not match the amount that needs to be repaid.
const EInvalidRepayAmount: u64 = 1;
/// The provided shares do not belong to the correct lending facility.
const EShareFacilMismatch: u64 = 2;
/// The maximum utilization has been reached or exceeded for the lending facility.
const EMaxUtilizationReached: u64 = 3;
/// The maximum amount of debt has been reached or exceeded for the lending facility.
const EMaxLiabilityOutstandingReached: u64 = 4;
/// The `SupplyPool` version does not match the module version.
const EInvalidSupplyPoolVersion: u64 = 5;
/// The migration is not allowed because the object version is higher or equal to the module
/// version.
const ENotUpgrade: u64 = 6;
/// The collateral amount is insufficient to repay the debt.
const EInsufficientCollateral: u64 = 7;

/* ================= access ================= */

public struct ACreatePool has drop {}
public struct AConfigLendFacil has drop {}
public struct AConfigFees has drop {}
public struct ATakeFees has drop {}
public struct ADeposit has drop {}
public struct AMigrate has drop {}

/* ================= structs ================= */

public struct MarketInfo has copy, drop {
    market_id: ID,
    deposited: u64,
    share_balance: u64,
}

public struct WithdrawInfo has copy, drop {
    market_id: ID,
    amount: u64,
    withdrawn: u64,
}

public struct LendFacilCap has key, store {
    id: UID,
}

public struct LendFacilInfo<phantom ST> has store {
    interest_model: Piecewise,
    // Shares of the debt (borrowed amount). Its total liability value is the total amount lent out,
    // and when added to the available balance it is equal to the underlying value of the
    // supply shares.
    debt_registry: DebtRegistry<ST>,
    /// The maximum amount of debt after which the borrowing will be capped.
    max_liability_outstanding: u64,
    /// The maximum utilization after which the borrowing will be capped.
    max_utilization_bps: u64,
}

public struct FacilDebtShare<phantom ST> has store {
    facil_id: ID,
    inner: DebtShareBalance<ST>,
}

public struct FacilDebtBag has key, store {
    id: UID,
    facil_id: ID,
    inner: DebtBag,
}

public struct Market<phantom Collateral, phantom ST> has key {
    id: UID,
    // The total collateral amount in the market.
    collateral_amount: u64,
    // The collateral amount of each user account in the market
    collateral_info: VecMap<ID, u64>,
    // The interest fee in basis points.
    interest_fee_bps: u16,
    // Debt information for each lending facility.
    debt_info: VecMap<ID, LendFacilInfo<ST>>,
    // Total amount lent out.
    total_liabilities_x64: u128,
    // Total borrowable amount for the market
    borrowable_cap: u64,
    // Last time the interest was accrued.
    last_update_ts_sec: u64,

    // Versioning to facilitate upgrades.   
    version: u16,
}

/* ================= upgrade ================= */

public(package) fun check_version<T, ST>(self: &Market<T, ST>) {
    assert!(self.version == MODULE_VERSION, EInvalidSupplyPoolVersion);
}

public fun migrate_market_version<T, ST>(
    self: &mut Market<T, ST>,
    ctx: &mut TxContext,
): ActionRequest {
    assert!(self.version < MODULE_VERSION, ENotUpgrade);
    self.version = MODULE_VERSION;
    access::new_request(AMigrate {}, ctx)
}

/* ================= Pool ================= */

public fun create_pool<T, ST: drop>(
    borrowable_cap: u64,
    ctx: &mut TxContext,
) {

    let market = Market<T, ST> {
        id: object::new(ctx),
        // available_balance: balance::zero(),
        collateral_amount: 0,
        collateral_info: vec_map::empty(),
        interest_fee_bps: 0,
        debt_info: vec_map::empty(),
        total_liabilities_x64: 0,
        borrowable_cap,
        last_update_ts_sec: 0,
        // supply_equity: equity_treasury,
        // collected_fees: equity::zero(),
        version: MODULE_VERSION,
    };

    transfer::share_object(market);
}

public fun create_lend_facil_cap(ctx: &mut TxContext): LendFacilCap {
    LendFacilCap { id: object::new(ctx) }
}

public fun add_lend_facil<T, ST: drop>(
    self: &mut Market<T, ST>,
    facil_id: ID,
    interest_model: Piecewise,
    ctx: &mut TxContext,
): ActionRequest {
    check_version(self);

    let debt_registry = debt::create_registry_with_cap();
    self
        .debt_info
        .insert(
            facil_id,
            LendFacilInfo {
                interest_model,
                debt_registry,
                max_liability_outstanding: 0,
                max_utilization_bps: 10_000,
            },
        );

    access::new_request(AConfigLendFacil {}, ctx)
}

public fun remove_lend_facil<T, ST>(
    self: &mut Market<T, ST>,
    facil_id: ID,
    ctx: &mut TxContext,
): ActionRequest {
    check_version(self);

    let (_, info) = self.debt_info.remove(&facil_id);
    let LendFacilInfo { interest_model: _, debt_registry, .. } = info;
    debt_registry.destroy_empty();

    access::new_request(AConfigLendFacil {}, ctx)
}

public fun set_lend_facil_interest_model<T, ST>(
    self: &mut Market<T, ST>,
    facil_id: ID,
    interest_model: Piecewise,
    ctx: &mut TxContext,
): ActionRequest {
    check_version(self);

    let info = &mut self.debt_info[&facil_id];
    info.interest_model = interest_model;

    access::new_request(AConfigLendFacil {}, ctx)
}

public fun set_lend_facil_max_liability_outstanding<T, ST>(
    self: &mut Market<T, ST>,
    facil_id: ID,
    max_liability_outstanding: u64,
    ctx: &mut TxContext,
): ActionRequest {
    check_version(self);

    let info = &mut self.debt_info[&facil_id];
    info.max_liability_outstanding = max_liability_outstanding;

    access::new_request(AConfigLendFacil {}, ctx)
}

public fun set_lend_facil_max_utilization_bps<T, ST>(
    self: &mut Market<T, ST>,
    facil_id: ID,
    max_utilization_bps: u64,
    ctx: &mut TxContext,
): ActionRequest {
    check_version(self);

    let info = &mut self.debt_info[&facil_id];
    info.max_utilization_bps = max_utilization_bps;

    access::new_request(AConfigLendFacil {}, ctx)
}

public fun set_interest_fee_bps<T, ST>(
    self: &mut Market<T, ST>,
    fee_bps: u16,
    ctx: &mut TxContext,
): ActionRequest {
    check_version(self);

    self.interest_fee_bps = fee_bps;
    access::new_request(AConfigFees {}, ctx)
}

/// The maximum amount of assets that can be borrowed from the market.
public fun borrowable_cap<T, ST>(self: &Market<T, ST>): u128 {
    self.borrowable_cap as u128
}

public fun utilization_bps<T, ST>(self: &Market<T, ST>): u64 {
    let total_value_x64 = borrowable_cap(self);
    if (total_value_x64 == 0) {
        return 0
    };

    util::muldiv_u128(
        self.total_liabilities_x64,
        10000,
        total_value_x64,
    ) as u64
}


public(package) fun borrow_debt_registry<T, ST>(
    self: &Market<T, ST>,
    id: &ID,
    _clock: &Clock,
): &DebtRegistry<ST> {
    check_version(self);

    let info = &self.debt_info[id];
    &info.debt_registry
}

/// Deposit collateral into the market.
public fun deposit_collateral<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    account_registry: &mut AccountRegistry,
    balance: Balance<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(self);

    let collateral_amount = balance.value();
    self.collateral_amount = self.collateral_amount + collateral_amount;

    let account_id = account_registry.borrow_or_create_profile(clock, ctx).account_id();

    if (self.collateral_info.try_get(&account_id).is_some()) {
        let current_amount = self.collateral_info[&account_id];
        *self.collateral_info.get_mut(&account_id) = current_amount + collateral_amount;
    } else {
        self.collateral_info.insert(account_id, collateral_amount);
    };
    
    liquidity_layer.deposit_direct(self.market_id(),balance);  
}

/// Withdraw collateral from the market after repaid the debt.
public fun withdraw_collateral<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    account_registry: &mut AccountRegistry,
    amount: u64,
    ctx: &mut TxContext,
): Balance<T> {
    check_version(self);

    let account_id = account_registry.account_id_of_sure(ctx.sender());
    let collateral_amount = self.collateral_info[&account_id];

    assert!(amount <= collateral_amount, EInsufficientCollateral);

    let market_id = self.market_id();

    event::emit(WithdrawInfo {
        market_id,
        amount,
        withdrawn: amount,
    });

    liquidity_layer.withdraw_direct(market_id, amount)
}

/// Borrow Assets from the market.
/// Borrowing amount can't exceed the collateral value * ratio.
/// TODO: pyth oracle price 
public fun borrow<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    _account_registry: &mut AccountRegistry,
    facil_cap: &LendFacilCap,
    amount: u64,
    _clock: &Clock,
    _ctx: &mut TxContext,
): (Balance<T>, FacilDebtShare<ST>) {
    check_version(self);

    let facil_id = object::id(facil_cap);

    let market_id = self.market_id();

    let info = &mut self.debt_info[&facil_id];
    let max_utilization_bps = info.max_utilization_bps;
    let max_liability_outstanding = info.max_liability_outstanding;

    let shares = info.debt_registry.increase_liability_and_issue(amount);

    // TODO: check withdrawable amount is less then collateral value * ratio
    // check_borrowable_amount(self, amount);

    let balance = liquidity_layer.withdraw_direct(market_id, amount);

    self.total_liabilities_x64 = self.total_liabilities_x64 + ((amount as u128) << 64);

    let liability_after_borrow = ((info.debt_registry.liability_value_x64() >> 64) as u64);
    let utilization_after_borrow = utilization_bps(self);
    assert!(liability_after_borrow < max_liability_outstanding, EMaxLiabilityOutstandingReached);
    assert!(utilization_after_borrow <= max_utilization_bps, EMaxUtilizationReached);

    let facil_shares = FacilDebtShare { facil_id, inner: shares };
    (balance, facil_shares)
}

/// Calculates the debt amount that needs to be repaid for the given amount of debt shares.
public fun calc_repay_by_shares<T, ST>(
    self: &mut Market<T, ST>,
    fac_id: ID,
    share_value_x64: u128,
    _clock: &Clock,
): u64 {
    check_version(self);
    let info = &self.debt_info[&fac_id];
    debt::calc_repay_lossy(&info.debt_registry, share_value_x64)
}

/// Calculates the debt share amount required to repay the given amount of debt.
public fun calc_repay_by_amount<T, ST>(
    self: &mut Market<T, ST>,
    fac_id: ID,
    amount: u64,
    _clock: &Clock,
): u128 {
    check_version(self);
    let info = &self.debt_info[&fac_id];
    debt::calc_repay_for_amount(&info.debt_registry, amount)
}

public(package) fun repay<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    shares: FacilDebtShare<ST>,
    balance: Balance<T>,
    _clock: &Clock,
) {
    check_version(self);
    let FacilDebtShare { facil_id, inner: shares } = shares;

    let info = &mut self.debt_info[&facil_id];
    let amount = info.debt_registry.repay_lossy(shares);
    assert!(balance.value() == amount, EInvalidRepayAmount);

    self.total_liabilities_x64 = self.total_liabilities_x64 - ((amount as u128) << 64);

    liquidity_layer.deposit_direct(self.market_id(), balance);
}

/// Repays the maximum possible amount of debt shares given the balance.
/// Returns the amount of debt shares and balance repaid.
public(package) fun repay_max_possible<T, ST>(
    self: &mut Market<T, ST>,
    liquidity_layer: &mut LiquidityLayer,
    shares: &mut FacilDebtShare<ST>,
    balance: &mut Balance<T>,
    clock: &Clock,
): (u128, u64) {
    check_version(self);

    let facil_id = shares.facil_id;
    let balance_by_shares = calc_repay_by_shares(self, facil_id, shares.value_x64(), clock);
    let shares_by_balance = calc_repay_by_amount(self, facil_id, balance.value(), clock);

    let (share_amt, balance_amt) = if (balance.value() >= balance_by_shares) {
        (shares.value_x64(), balance_by_shares)
    } else {
        // `shares_by_balance <= shares` here, this can be proven with an SMT solver
        (shares_by_balance, balance.value())
    };
    repay(
        self,
        liquidity_layer,
        shares.split_x64(share_amt),
        balance.split(balance_amt),
        clock,
    );

    (share_amt, balance_amt)
}

/* ================= FacilDebtShare ================= */

public(package) fun fds_facil_id<ST>(self: &FacilDebtShare<ST>): ID {
    self.facil_id
}

public(package) fun fds_borrow_inner<ST>(self: &FacilDebtShare<ST>): &DebtShareBalance<ST> {
    &self.inner
}

public(package) fun fds_value_x64<ST>(self: &FacilDebtShare<ST>): u128 {
    self.inner.value_x64()
}

public(package) fun fds_split_x64<ST>(
    self: &mut FacilDebtShare<ST>,
    amount: u128,
): FacilDebtShare<ST> {
    let inner = self.inner.split_x64(amount);
    FacilDebtShare { facil_id: self.facil_id, inner }
}

public(package) fun fds_split<ST>(self: &mut FacilDebtShare<ST>, amount: u64): FacilDebtShare<ST> {
    let inner = self.inner.split(amount);
    FacilDebtShare { facil_id: self.facil_id, inner }
}

public(package) fun fds_withdraw_all<ST>(self: &mut FacilDebtShare<ST>): FacilDebtShare<ST> {
    let inner = self.inner.withdraw_all();
    FacilDebtShare { facil_id: self.facil_id, inner }
}

public(package) fun fds_join<ST>(self: &mut FacilDebtShare<ST>, other: FacilDebtShare<ST>) {
    assert!(self.facil_id == other.facil_id, EShareFacilMismatch);

    let FacilDebtShare { facil_id: _, inner: other } = other;
    self.inner.join(other);
}

public(package) fun fds_destroy_zero<ST>(shares: FacilDebtShare<ST>) {
    let FacilDebtShare { facil_id: _, inner: shares } = shares;
    shares.destroy_zero();
}

/* ================= FacilDebtBag ================= */

public(package) fun empty_facil_debt_bag(facil_id: ID, ctx: &mut TxContext): FacilDebtBag {
    FacilDebtBag {
        id: object::new(ctx),
        facil_id,
        inner: debt_bag::empty(ctx),
    }
}

public(package) fun fdb_add<T, ST>(self: &mut FacilDebtBag, shares: FacilDebtShare<ST>) {
    assert!(self.facil_id == shares.facil_id, EShareFacilMismatch);

    let FacilDebtShare { facil_id: _, inner: shares } = shares;
    self.inner.add<T, ST>(shares);
}

public(package) fun fdb_take_amt<ST>(self: &mut FacilDebtBag, amount: u128): FacilDebtShare<ST> {
    let shares = self.inner.take_amt(amount);
    FacilDebtShare { facil_id: self.facil_id, inner: shares }
}

public(package) fun fdb_take_all<ST>(self: &mut FacilDebtBag): FacilDebtShare<ST> {
    let shares = self.inner.take_all();
    FacilDebtShare { facil_id: self.facil_id, inner: shares }
}

public(package) fun fdb_get_share_amount_by_asset_type<T>(self: &FacilDebtBag): u128 {
    self.inner.get_share_amount_by_asset_type<T>()
}

public(package) fun fdb_get_share_amount_by_share_type<ST>(self: &FacilDebtBag): u128 {
    self.inner.get_share_amount_by_share_type<ST>()
}

public(package) fun fdb_get_share_type_for_asset<T>(self: &FacilDebtBag): TypeName {
    self.inner.get_share_type_for_asset<T>()
}

public(package) fun fdb_is_empty(self: &FacilDebtBag): bool {
    self.inner.is_empty()
}

public(package) fun fdb_destroy_empty(self: FacilDebtBag) {
    let FacilDebtBag { id, facil_id: _, inner } = self;
    id.delete();
    inner.destroy_empty();
}

/* ================= Market ================= */

public(package) fun market_id<T, ST>(self: &Market<T, ST>): ID {
    object::id(self)
}

