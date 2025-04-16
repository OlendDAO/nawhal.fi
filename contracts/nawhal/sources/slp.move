module nawhal::slp;

use nawhal::admin;
use sui::coin::{Self, TreasuryCap};
use sui::url;
use sui::transfer;
use sui::tx_context::TxContext;

// use perps::rate;

const DECIMALS: u8 = 9;
const SYMBOL: vector<u8> = b"SLP";
const NAME: vector<u8> = b"SuiPerps LP Token";
const DESCRIPTION: vector<u8> = b"SuiPerps LP Token for Perps World";
const ICON_URL: vector<u8> = b"https://olend.finance/slp-icon.png";

#[allow(unused_field)]
public struct SLP has drop {
    dummy_field: bool,
}

/// Create the `AdminCap` and `SLP` token, 
/// Share the `CoinMetadata` and transfer `TreasuryCap` to the `Market` object
fun init(otw: SLP, ctx: &mut TxContext) {
    initalize(otw, ctx)
}

// ... existing code ...