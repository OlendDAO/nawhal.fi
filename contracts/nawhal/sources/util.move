
module nawhal::util;

use sui::clock::Clock;

/// Calculate `Clock` timestamp in seconds from milliseconds.
public fun get_sec(clock: &Clock): u64 {
    clock.timestamp_ms() / 1000
}
