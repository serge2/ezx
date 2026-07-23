%% @doc ZX Spectrum TAP file format parser.
%%
%% TAP format stores data as a sequence of blocks.
%% Each block has the following binary layout:
%%
%%   Len  (2 bytes, little-endian) — block length including flag and checksum
%%   Flag (1 byte) — 0x00 for header, 0xFF for data
%%   Payload (Len-2 bytes) — block content
%%   Checksum (1 byte) — XOR of flag and all payload bytes
%%
%% A TAP file is simply the concatenation of all blocks with no file header.
%% Header blocks (flag=0x00) are always 19 bytes:
%%   Type (1), Filename (10), DataLength (2), Param1 (2), Param2 (2), checksum (1)
%% Data blocks (flag=0xFF) contain the actual program or data.
%%
%% @end
-module(ezx_tap).

-include("tap.hrl").

-export([parse_blocks/1, block_flag/1, block_payload/1]).

%% @doc Parse a TAP binary into a list of blocks.
%%
%% Returns an empty list for empty or malformed input.
%% Blocks with insufficient data for the declared length are skipped.
-spec parse_blocks(binary()) -> tap_blocks().
parse_blocks(<<>>) -> [];
parse_blocks(<<Len:16/little, Flag:8, PayloadAndChecksum/binary>> = _Data)
  when byte_size(PayloadAndChecksum) >= Len - 1 ->
    PayloadLen = Len - 2,
    <<Payload:PayloadLen/binary, _Checksum:8, Remaining/binary>> = PayloadAndChecksum,
    [#tap_block{flag = Flag, payload = Payload} | parse_blocks(Remaining)];
parse_blocks(_) -> [].

%% @doc Get the flag byte from a parsed block.
%% 0x00 = header block, 0xFF = data block.
-spec block_flag(tap_block()) -> byte().
block_flag(#tap_block{flag = Flag}) -> Flag.

%% @doc Get the payload binary from a parsed block.
-spec block_payload(tap_block()) -> binary().
block_payload(#tap_block{payload = Payload}) -> Payload.
