-record(sna_header, {
    i        :: byte(),
    r        :: byte(),
    af       :: non_neg_integer(),
    bc       :: non_neg_integer(),
    de       :: non_neg_integer(),
    hl       :: non_neg_integer(),
    ix       :: non_neg_integer(),
    iy       :: non_neg_integer(),
    af_prime :: non_neg_integer(),
    bc_prime :: non_neg_integer(),
    de_prime :: non_neg_integer(),
    hl_prime :: non_neg_integer(),
    sp       :: non_neg_integer(),
    iff2     :: byte(),
    border   :: byte(),
    mem      :: binary()
}).

-export_type([sna_header/0]).
-opaque sna_header() :: #sna_header{}.
