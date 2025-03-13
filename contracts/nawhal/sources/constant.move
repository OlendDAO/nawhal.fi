
module nawhal::constant;

/// Consts
/// Define a trillion for precision
const TRILLION: u256 = 1_000_000_000_000_000_000;

public fun trillion() : u256 {
    TRILLION
}

public fun trillion_u128() : u128 {
    TRILLION as u128
}