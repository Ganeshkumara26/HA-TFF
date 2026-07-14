# BUG-006: Sticky Parse Error

## Description
The `parse_error` signal in `ha_tff_parser_v002.v` was implemented as a "sticky" flag that remained asserted once triggered, instead of being a 1-cycle pulse or resetting at the end of the packet. Furthermore, packets that were too short (ending before the 5-tuple was fully extracted) did not correctly trigger a parsing error.

## Root Cause
- The `else` blocks in the parser state machine did not explicitly clear `parse_error <= 0`.
- The parser did not handle premature `s_axis_tlast` events, leaving the state machine stuck or erroneously asserting `tuple_valid` on incomplete data.

## Fix
- Added `parse_error <= 0` in the default assignments at the top of the clock block.
- Implemented short-packet detection: if `s_axis_tlast` is asserted before `word_cnt` reaches 4, `parse_error` is immediately driven high, and the state machine resets.
