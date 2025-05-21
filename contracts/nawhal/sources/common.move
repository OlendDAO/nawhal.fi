module narval::common;

use std::type_name::{Self, TypeName};
use std::u64;

/* ================= Structs ================= */

// YieldToken witness.
public struct YieldToken<phantom T> has drop {}

/// New a yield token
public fun new_yield_token<T>(): YieldToken<T> {
    YieldToken {}
}

/// An item in the `PoolRegistry` table. Represents a pool's currency pair.
public struct PoolPairItem has copy, drop, store {
    a: TypeName,
    b: TypeName,
}

///  New an pool pair item
public fun new_pool_pair_item(a: TypeName, b: TypeName): PoolPairItem {
    PoolPairItem { 
        a, 
        b 
    }
}

// returns:
//    0 if a < b,
//    1 if a == b,
//    2 if a > b
public fun cmp_type_names(a: &TypeName, b: &TypeName): u8 {
    let bytes_a = a.borrow_string().as_bytes();
    let bytes_b = b.borrow_string().as_bytes();

    let len_a = bytes_a.length();
    let len_b = bytes_b.length();

    let mut i = 0;
    let n = u64::min(len_a, len_b);
    while (i < n) {
        let a = bytes_a[i];
        let b = bytes_b[i];

        if (a < b) {
            return 0
        };
        if (a > b) {
            return 2
        };
        i = i + 1;
    };

    if (len_a == len_b) {
        return 1
    };

    return if (len_a < len_b) {
            0
        } else {
            2
        }
}

#[test_only]
public struct BAR has drop {}
#[test_only]
public struct FOO has drop {}
#[test_only]
public struct FOOD has drop {}
#[test_only]
public struct FOOd has drop {}

#[test]
fun test_cmp_type() {
    assert!(
        cmp_type_names(&type_name::get<BAR>(), &type_name::get<FOO>()) == 0,
        0,
    );
    assert!(
        cmp_type_names(&type_name::get<FOO>(), &type_name::get<FOO>()) == 1,
        0,
    );
    assert!(
        cmp_type_names(&type_name::get<FOO>(), &type_name::get<BAR>()) == 2,
        0,
    );

    assert!(
        cmp_type_names(&type_name::get<FOO>(), &type_name::get<FOOd>()) == 0,
        0,
    );
    assert!(
        cmp_type_names(&type_name::get<FOOd>(), &type_name::get<FOO>()) == 2,
        0,
    );

    assert!(
        cmp_type_names(&type_name::get<FOOD>(), &type_name::get<FOOd>()) == 0,
        0,
    );
    assert!(
        cmp_type_names(&type_name::get<FOOd>(), &type_name::get<FOOD>()) == 2,
        0,
    );
}