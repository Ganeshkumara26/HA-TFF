ok so i finished the `edp-core` C middleware in july. got the latency down to 12us. my manager was happy. i thought i was done. i was ready to just drink coffee, pretend to look busy, and wait for my internship at meghdut to end so i could go back to college.

then the 5G tests started.

turns out 5G base stations like to randomly vomit network control packets (ARP, ICMP, multicast garbage) onto the network. our companion computer's linux kernel freaks out, triggers a softirq storm, and drops whatever its doing to process them. 

result: our drone control loop gets 10ms jitter spikes. 

in a drone, 10ms of jitter means the PID controller destabilizes. the drone literally wobbles in the air. 

i was staring at the telemetry graphs at 2am. software is the problem. linux is the problem. no matter how much i optimize my C code, the OS scheduler is going to ruin it. you cant do hard real-time on standard linux.

i need to filter these garbage packets before they ever touch the CPU. i need to do it in hardware.

i literally just spent the entire spring semester doing the rvfpga labs, suffering through pipeline diagrams and hazards. i know what a risc-v cpu looks like. why dont i just build a custom hardware firewall? plug the ethernet directly into the fpga fabric, drop bad packets at wire speed, and only send the good telemetry to the cpu.

im calling it the Hardware-Accelerated Telemetry Filter/Forwarder. HA-TFF. 

famous last words part 2.

---

## july 15 2026 - python hardware? lol

writing production verilog from scratch is terrifying. my only experience is the rvfpga labs where the code was mostly given to us. 

so i googled "write verilog in python" and found this library called Migen (now Amaranth). 

"oh thank god," i thought. "i know python. i can just write python and it will magically become hardware."

created `old_attempts/migen_filter.py`. started writing a basic state machine. 

it... did not feel like python. 

---

## july 20 2026 - fighting migen

i’ve spent five days trying to get migen to parse a basic ethernet header and i feel like i'm losing my mind. 

you have to write these massive chains of `If(self.state == IDLE).NextState(HDR)` objects. it feels so clunky. its like trying to speak french using a spanish dictionary. 

hardware is fundamentally concurrent. everything happens at once. python is fundamentally sequential. trying to force a sequential language to describe concurrent logic just leads to brain damage. i spend more time fighting the python syntax than actually designing the hardware.

but i kept pushing because i was too scared of raw systemverilog.

---

## july 25 2026 - giving up on migen

the breaking point finally happened. i tried to hook up my migen code to the Wishbone bus, which required generating the actual verilog output. 

i clicked "generate verilog", expecting some clean, readable code.

it spat out 500 lines of absolute gibberish. variables were named things like `migen_fsm_2_val_3_next`. all my readable, semantic names were stripped out and replaced with a completely flattened netlist.

when my simulation locked up and i tried to look at the waveform in vivado, i literally started crying laughing. i was staring at `signal_847` trying to figure out if that was my valid bit. you literally cannot debug the generated code.

i needed a mental escape. i had downloaded the RVfpga-SoC course materials months ago but never touched them. i opened rvfpga-soc Lab 1 and just started dragging and dropping IP blocks on Vivado's Block Design canvas. it was so therapeutic. no python, no gibberish, just connecting boxes like a coloring book. 

abstractions are a lie. if you have to debug the generated code (and in hardware, you ALWAYS have to debug the waveform), you need to understand the generated code. 

i deleted the python stuff. moved it all to `old_attempts/`. raw systemverilog it is. i just have to face my fears.

---

## aug 2 2026 - the 0.2ns nightmare

started writing the parser (`old_attempts/parser_v1_mealy.sv`) in raw SV. i needed a state machine that could consume bytes from an AXI-Stream interface.

i remembered from my digital logic class that there are two types of FSMs: Mealy and Moore.
in a Mealy machine, the outputs are a combinational function of the current state AND the current inputs. i thought this was brilliant. it meant the output (`tvalid`) would update in the EXACT SAME clock cycle that the input byte arrived. zero latency! im saving nanoseconds!

my testbench worked on the first try. i felt like a hardware god.

then i ran a slightly more realistic testbench where the input data arrived slightly off-center from the clock edge, which is how real PHYs work in the real world.

i opened the waveform, and something looked wrong. i zoomed in. i zoomed in more.

my `tvalid` output was glitching high for exactly 0.2 nanoseconds. 

WHAT. 

in python, 0.2ns doesnt exist. in hardware, a 0.2ns glitch on a valid signal means the downstream fifo latches pure garbage. 

---

## aug 5 2026 - the realization

i was staring at the vivado waveform pulling my hair out. why is it glitching? the logic is perfectly mathematically correct!

closed vivado in disgust. opened rvfpga-soc Lab 2 and just made an LED blink on the Nexys A7 using verilator and C. i needed a win. at least *something* i touched today actually worked.

and then it hit me. 

i had a sudden flashback to the base rvfpga lab 11. the prof was standing at the whiteboard explaining why the VeeR pipeline registers all of its control signals instead of leaving them combinational. 

because combinational logic evaluates instantly. if the inputs to an AND gate arrive at slightly different times due to routing delays, the output glitches and bounces around while it settles! 

OOPS.

my mealy machine was evaluating the NEW inputs against the OLD state for a fraction of a nanosecond before the clock edge hit. 

i had to scrap the mealy machine completely.

---

## aug 6 2026 - moore machines

rewrote the entire parser as a Moore machine (`rtl/eth_parser.sv`). outputs come directly from a flip-flop. they only depend on the state, not the inputs.

it adds 1 clock cycle of latency (10ns at 100MHz), but it guarantees perfectly clean, glitch-free signals. and honestly? 10ns of delay is absolutely nothing compared to linux's 10,000,000ns jitter anyway.

the waveforms are beautiful now. solid blocks of green. no red lines.

---

## aug 8 2026 - outsmarting the compiler

i decided i was going to be a genius and optimize my state machine before i even finished writing it. 

i read a Xilinx whitepaper that said "always use one-hot encoding for fpga state machines" because it maps better to LUTs.

so i went into my code, manually hardcoded my states to `8'b00000010`, and confidently added a vivado `(* fsm_encoding = "one_hot" *)` attribute above my state variable. i felt so smart. 

vivado threw a weird synthesis warning about "conflicting directives." i ignored it, obviously, because i read a whitepaper and vivado is just a dumb tool.

---

## aug 10 2026 - priority encoder disaster

i ran the simulation, expecting my highly optimized state machine to fly. 

instead, my state machine jumped from the IDLE state directly to the FORWARD state, completely bypassing all the IP and UDP security checks. it just opened the floodgates to every packet.

i posted my code on a hardware discord, completely defeated. 

a guy replied: "lol vivado got confused by your conflicting attributes and inferred a priority encoder instead of a state machine. just use an enum and let the tool do its job."

i quietly deleted my manual bit assignments, changed it to a simple `enum logic [3:0]`, removed the attribute, and ran it again. it worked perfectly. 

(saved the broken one in `old_attempts/fsm_onehot_broken.sv` to remind myself im not smarter than the compiler).

---

## aug 12 2026 - the wishbone disaster

okay, the filter works, but it's useless if the CPU can't actually talk to it to read the telemetry. i need to connect it to the VeeR RISC-V core using the Wishbone B4 bus architecture.

i vaguely remembered Wishbone from rvfpga-soc Lab 3. address goes in, data goes out, assert ACK. easy.

i wrote `old_attempts/wb_bridge_naive.sv`. i tested it with the cpu doing a single 32-bit read. it worked perfectly. 

then i tested a burst read, simulating the cpu reading the fifo in a tight loop. it dropped the second byte entirely. it just vanished.

WHY.

spent 3 agonizing days on this, reading the official 100-page wishbone spec PDF.

---

## aug 14 2026 - pipelined wishbone

my eyes were bleeding from the spec pdf. i procrastinated by opening rvfpga-soc Lab 3. 

lab 3 introduces FuseSoC. a package manager for hardware. you literally just type `fusesoc library add swervolf` and it builds the entire SoC. i felt like a caveman banging rocks together trying to manually write an ACK signal.

but looking at how the SweRVolf SoC mapped its GPIO to `0x80001010` in Lab 3 made me go back to my rvfpga lab 10 notes on serial buses and timing. 

and there it was. the VeeR Load/Store unit uses *pipelined* wishbone. 

it doesn't wait for the first ACK to send the second request. it just pipelines them back-to-back!

my stupid naive slave was registering the ACK (delaying it by 1 full clock cycle). by the time my ACK went high, the cpu had already requested the second byte, and my slave just ignored the second request because it was busy ACKing the first one.

YES! i actually understand bus timing now. i changed the ACK to be combinational. burst reads fixed.

---

## aug 18 2026 - the multi-pop ghost

i thought i was done with the bus, but i immediately hit a worse bug. 

the cpu would issue ONE read instruction (`lw`), but my fifo would pop 4 times. 3 bytes would literally vanish into the void.

i stared at the waveform for hours. the cpu was holding the read signal high for 4 full clock cycles. why? the `lw` instruction only takes 1 cycle in the execute stage!

wait. 
pipeline stalls. 
rvfpga lab 14. structural hazards. 

the cpu was stalled waiting for an instruction fetch from main memory! the pipeline just froze, and the load/store unit held the bus signals open while it waited! 

OOPS. 

my fifo read-enable was tied directly to the bus read signal. bus held high for 4 cycles = 4 pops.

i am so incredibly dumb. 

---

## aug 20 2026 - edge detection

i went back into `rtl/wb_slave.sv` and added a proper edge-detector. 

i registered the previous read state and added `assign fifo_pop = (read_now && !read_prev);`. 

now it only pops on the actual rising edge of the read signal, regardless of how long the cpu holds it open while stalled. 

this took me over a week to figure out. implementing a bus slave is way harder than just writing C code to read from one.

---

## aug 25 2026 - hardware crc

okay, time for the hardware CRC. doing this in hardware is sick because instead of a massive lookup table like i used in C, i can just build a massive XOR tree that computes the whole thing in 1 cycle. 

i wrote the combinational logic in `rtl/ha_tff_pkg.sv`. 

i ran a test packet through. 
it failed the CRC check. 

---

## aug 28 2026 - mavlink is annoying

i started tracing the CRC values. MAVLink has this annoying feature called `CRC_EXTRA`. it's a secret seed byte that isn't transmitted in the packet, but you have to mathematically add it to the CRC at the very end before checking it.

my FSM was doing this in its final state:
1. add CRC_EXTRA to the running total (`crc_calc <= crc_calc ^ crc_extra;`)
2. compare the total to the received CRC (`if (crc_calc == received)`)

failing. every single time. 

i stared at those two lines of verilog for an entire afternoon.

---

## aug 30 2026 - data hazards in real life

and then, like a lightning bolt, i remembered rvfpga lab 15. 

Data Hazards. Read-After-Write (RAW).

in verilog, non-blocking assignments (`<=`) don't update until the NEXT clock edge. i was adding the extra byte and comparing the register on the EXACT SAME CLOCK EDGE. 

my comparison logic was reading the OLD value of the register! the new value literally hadn't been written yet!

OOPS OOPS OOPS.

i literally just recreated a CPU data hazard inside my own state machine. i was the architect of my own RAW hazard.

YES! i added an extra `MF_PASS` state to delay the comparison by one cycle, letting the register actually update first. it worked instantly. i feel like an actual hardware engineer.

---

## sept 5 2026 - the rollback fifo (my actual masterpiece)

so i had a fundamental architectural problem. i don't know if a packet's CRC is actually valid until the very last byte arrives.
but i can't buffer a massive 1500-byte ethernet frame just to check it. that takes too much ram and adds huge latency.

i needed the speed of cut-through routing, but without the risk of forwarding bad packets to the cpu.

i spent a whole weekend staring at a whiteboard, designing `rtl/telem_fifo.sv`. 
it has TWO pointers. a speculative `wr_ptr` and a `wr_committed` pointer.
i write bytes directly into the fifo as they arrive, advancing `wr_ptr`. 
if the CRC passes at the end, `wr_committed` jumps forward to catch up. 
if the CRC fails... i just snap `wr_ptr` backwards to equal `wr_committed`. 

the bad packet is instantly, magically erased before the CPU even knows it exists.

this is the smartest thing i have ever coded. i am so proud of this.

---

## sept 8 2026 - doing the math

how big does this fifo actually need to be?

a mavlink heartbeat is 19 bytes. at 100Mbps, bytes arrive every 80ns.
if the cpu gets an interrupt and takes 100 cycles to wake up from sleep mode (at 100MHz = 1us), the MAC writes 12 bytes while the cpu is waking up.
so a 64-byte fifo is plenty.

i love math when it actually solves a real-world engineering problem instead of just being a textbook exercise.

---

## sept 25 2026 - verilator saves me

vivado's simulator is driving me insane. launching the GUI takes 3 minutes. running a million cycles takes forever. i can't fuzz my design with random garbage packets.

i finally bit the bullet and switched to Verilator. it compiles verilog into native C++. it runs instantly.

while verilator was compiling my 10,000 fuzzed packets, i procrastinated by doing rvfpga-soc Lab 4. booted Zephyr RTOS on the Nexys A7. watching an entire OS run on a soft-core made me realize i can actually use Zephyr for the drone instead of standard linux. the deterministic scheduling is exactly what we need.

wrote a C++ fuzzer (`tb/tb_utils.h`) and started throwing corrupt, malformed packets at my hardware to see if it would break.

---

## sept 29 2026 - edge cases

it broke. a lot.

i found out my state machine completely, permanently hangs if a packet ends early (a "runt" packet) because it was waiting for payload bytes that would never arrive. 
i had to go back and add `tlast` abort checks to every single state in the parser. 

if i had just used the vivado simulator i'd have never found this until the drone was literally falling out of the sky. 

also found out IPv4 options break my parser because i assumed a 20-byte fixed header. added a check for the `IHL` field. if its > 5, i just drop the packet entirely.

---

## oct 2 2026 - constraints

wrote the XDC constraints file for the Nexys A7. mapping the AXI-stream ports to the physical SMSC ethernet PHY pins on the board.

i spent four hours reading the Nexys A7 reference manual pdf trying to figure out which pin is `eth_txd[0]`. this part is so incredibly boring but you literally can't synthesize without it.

---

## oct 4 2026 - synthesis

the moment of truth. i clicked "Run Synthesis" for the Nexys A7 and watched the spinner.

it takes 15 minutes, so i did rvfpga-soc Lab 5 while waiting. compiled TensorFlow Lite and ran a neural net on the SweRVolf core. AI on an FPGA. 
by the time it finished printing the results, my synthesis dinged. 

when the utilization report popped up, my jaw dropped.

348 LUTs. 
less than 1% of the FPGA.
100MHz timing met easily (3.42ns positive slack).

i looked at the massive TensorFlow/Zephyr/SweRVolf stack running on my board from Lab 5, and then i looked at my tiny, brutally efficient, 348-LUT custom hardware firewall. 

doing this in software took an entire linux OS, thousands of lines of kernel code, context switches, and it still gave me 10ms of jitter.
my hardware version gives me exactly 10ns of latency per byte, every single time. it takes up basically zero physical space and uses almost zero power.

hardware is cheap. abstraction is expensive.

---

## oct 10 2026 - done.

everything is wired up in `rtl/ha_tff_top.sv`. 

a year ago i was looking at the VeeR pipeline diagrams in rvfpga lab 11 and crying because i didn't know what a structural hazard was. 

now i just built a custom hardware firewall that interfaces directly with its memory bus. and i literally debugged it by recognizing pipeline stalls and RAW data hazards in my own logic.

this internship has been wild. 
im ready to integrate this into the SoC next semester. but right now, i need to sleep for 3 days.
