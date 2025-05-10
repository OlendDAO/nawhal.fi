
module narval::oracle;

use std::type_name::{Self, TypeName};

use sui::vec_map::{Self, VecMap};

// ------- Structs ------- //
/// The registry of the oracle
public struct OracleRegistry has key {
    id: UID,
    price_objects: VecMap<TypeName, PriceObject>,
}

/// The price object of the oracle
public struct PriceObject has key, store {
    id: UID,
    asset_type: TypeName,

    price: u64,
    timestamp: u64,
}

// ------- Initializers ------- //
fun init(ctx: &mut TxContext) {
    let oracle_registry = new_oracle_registry(ctx);

    transfer::share_object(oracle_registry);
}

// ------- Governance ------- //
/// Registry the Pyth oracle for a given asset type
/// For Test
public fun register_oracle<T>(self: &mut OracleRegistry, price: u64, timestamp: u64, ctx: &mut TxContext) {
    self.add_price_object<T>(PriceObject {
        id: object::new(ctx),
        asset_type: type_name::get<T>(),
        price,
        timestamp,
    });
}

public entry fun register_oracle_api<T>(self: &mut OracleRegistry, price: u64, timestamp: u64, ctx: &mut TxContext) {
    register_oracle<T>(self, price, timestamp, ctx);
}

/// Get the price by the asset type
public fun get_price<T>(self: &OracleRegistry): u64 {
    let price_object = self.price_objects.get(&type_name::get<T>());
    price_object.price
}

// ------- Constructors ------- //
public fun new_price_object<T>(price: u64, timestamp: u64, ctx: &mut TxContext): PriceObject {
    PriceObject {
        id: object::new(ctx),
        asset_type: type_name::get<T>(),
        price,
        timestamp,
    }
}

public fun new_oracle_registry(ctx: &mut TxContext): OracleRegistry {
    OracleRegistry {
        id: object::new(ctx),
        price_objects: vec_map::empty(),
    }
}

// ------- Setters ------- //
public(package) fun add_price_object<T>(self: &mut OracleRegistry, price_object: PriceObject) {
    self.price_objects.insert(type_name::get<T>(), price_object);
}


// ------- Getters ------- //
public fun id(self: &PriceObject): ID {
    object::id(self)
}

public fun price(self: &PriceObject): u64 {
    self.price
}

public fun timestamp(self: &PriceObject): u64 {
    self.timestamp

}


