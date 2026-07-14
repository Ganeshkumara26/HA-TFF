# Debug Record: BUG-001

## Date: 2026-01-06
## Symptom (CATEGORY A)
During `sim001`, the testbench `tb_ha_tff_parser_v001` timed out waiting for `tuple_valid`.
Simulation output:
`[1585000] ERROR: Tuple NOT Valid! (Timeout)`

## Root Cause Hypothesis (CATEGORY D)
The RTL `ha_tff_parser_v001.v` transitions from `STATE_IDLE` to `STATE_PARSE` when `s_axis_tvalid` is high, but does not capture the 0th byte of data in that clock cycle. As `s_axis_tdata` streams continuously, the FSM uses `case(byte_cnt)` to capture bytes. 
Because `s_axis_tdata` is synchronous to `clk`, the byte indices might be misaligned by one clock cycle, or the conditional `if (ethertype == 16'h0800)` evaluates `ethertype` too early before it has settled. Wait, in Verilog, non-blocking assignments (`<=`) mean `ethertype` is updated at the *end* of the cycle. At cycle 37, `ethertype` has been stable since cycle 13, so that's not the issue.

Let's check the testbench `send_byte` task:
```verilog
    task send_byte(input [7:0] data, input is_last);
        begin
            @(posedge clk);
            s_axis_tvalid <= 1;
            s_axis_tdata <= data;
            s_axis_tlast <= is_last;
        end
    endtask
```
This task changes signals on the `posedge clk`. This means the `uut` will see the new values on the *next* `posedge clk`.
So:
- T0 (posedge): `s_axis_tvalid` <= 1, `data` <= B0.
- T1 (posedge): `uut` sees `s_axis_tvalid == 1`, `data == B0`. `uut` is in IDLE. It sets `state <= PARSE`, `byte_cnt <= 1`.
- T1 (posedge inside task): `s_axis_tvalid` <= 1, `data` <= B1.
- T2 (posedge): `uut` sees `s_axis_tvalid == 1`, `data == B1`, `state == PARSE`. It evaluates `case(byte_cnt)` which is `case(1)`. It latches `data` (B1) correctly!

So the indexing is correct.
Why did it fail? Let's check `protocol`!
At byte 23, `send_byte(8'h11, 0)` is sent.
Wait! In the testbench:
```verilog
        // Byte 14: Version/IHL
        send_byte(8'h45, 0);
        // Byte 15: TOS
        send_byte(8'h00, 0);
        // Byte 16-17: Total Length
        send_byte(8'h00, 0); send_byte(8'h28, 0);
        // Byte 18-19: Identification
        send_byte(8'hAB, 0); send_byte(8'hCD, 0);
        // Byte 20-21: Flags/Offset
        send_byte(8'h40, 0); send_byte(8'h00, 0);
        // Byte 22: TTL
        send_byte(8'h40, 0);
        // Byte 23: Protocol (UDP = 0x11)
        send_byte(8'h11, 0);
```
Wait, count the bytes carefully:
Byte 14: 1 byte
Byte 15: 1 byte
Byte 16-17: 2 bytes
Byte 18-19: 2 bytes
Byte 20-21: 2 bytes
Byte 22: 1 byte
Byte 23: 1 byte.
Total = 1+1+2+2+2+1+1 = 10 bytes. 14 + 10 = 24.
Ah! 14 + 0 = 14.
14 + 1 = 15.
14 + 2 = 16, 17.
14 + 4 = 18, 19.
14 + 6 = 20, 21.
14 + 8 = 22.
14 + 9 = 23.
Yes, IP Protocol is byte 23.
IP Header Checksum is 24, 25.
Src IP is 26, 27, 28, 29.
Dst IP is 30, 31, 32, 33.
Src Port is 34, 35.
Dst Port is 36, 37.
Length & Checksum is 38, 39, 40, 41.

Wait, if `case(37)` asserts `tuple_valid <= 1`, when does it show up?
It shows up on T38.
In the testbench:
```verilog
        // wait for tuple_valid or timeout
        for (i = 0; i < 100; i = i + 1) begin
            if (tuple_valid) begin ...
```
This loop runs *after* the packet has finished sending!
```verilog
        send_byte(8'hEF, 1); // tlast = 1
        @(posedge clk);
        s_axis_tvalid <= 0;
        s_axis_tlast <= 0;
        // ... then wait loop starts ...
```
At the time `send_byte(8'hEF, 1)` finishes, we are at byte 45 or so. `byte_cnt == 37` happened 8 clock cycles *earlier*!
When `byte_cnt == 37`, `tuple_valid` goes high for 1 clock cycle.
By the time the testbench finishes sending the packet and starts checking `tuple_valid`, it's already back to 0!

## Fix
The testbench must check `tuple_valid` *concurrently* while sending the packet, not afterwards. Verilog-2001 doesn't have `fork/join_any`, but we can put the `tuple_valid` check in an `always` block or a separate `initial` block.

## Action
Rewrite `tb_ha_tff_parser_v001.v` to check `tuple_valid` using an `always @(posedge clk)` block.
