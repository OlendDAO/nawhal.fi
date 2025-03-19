
/// This module is used to manage the position of the user
/// 
module nawhal::position;

// ------ Constants ------ //
const COLLATERAL_RATIO_PERCENTAGE: u64 = 100;

// ------ Structs ------ //
public struct Position<phantom T> has key {
    id: UID,
    account_id: ID,
    pool_id: ID,
    collateral: u64,
    debt: u64,
    pool_collateral_ratio: u64,
    status: PositionStatus,
}

public enum PositionStatus has copy, drop, store {
    Active,
    Closed,
}

// ------ Creators ------ //
public fun new<T>(
    account_id: ID,
    pool_id: ID,
    collateral: u64,
    debt: u64,
    pool_collateral_ratio: u64,
    ctx: &mut TxContext,
): Position<T> {
    Position<T> {
        id: object::new(ctx),
        account_id,
        pool_id,
        collateral,
        debt,
        pool_collateral_ratio,
        status: PositionStatus::Active,
    }
}

// ------ Getters ------ //
public fun collateral_value<T>(self: &Position<T>): u64 {
    self.collateral
}

public fun debt_value<T>(self: &Position<T>): u64 {
    self.debt
}

public fun pool_collateral_ratio<T>(self: &Position<T>): u64 {
    self.pool_collateral_ratio
}   

public fun status<T>(self: &Position<T>): PositionStatus {
    self.status
}

/// Calculate the collateral ratio of the position
public fun collateral_ratio<T>(self: &Position<T>): u64 {
    COLLATERAL_RATIO_PERCENTAGE * self.collateral_value() / self.debt_value() 
}


