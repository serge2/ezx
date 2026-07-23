-record(tap_block, {
    flag    :: byte(),
    payload :: binary()
}).

-export_type([tap_block/0, tap_blocks/0]).
-opaque tap_block() :: #tap_block{}.
-type tap_blocks() :: [tap_block()].
