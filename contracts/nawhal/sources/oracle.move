
module narval::oracle;

public struct PriceObject has key, store {
    id: UID,
    price: u64,
    timestamp: u64,
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