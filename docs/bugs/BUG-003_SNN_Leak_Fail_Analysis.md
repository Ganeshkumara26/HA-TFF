# Bug Report: BUG-003 (SNN Fails to Leak During Idle Cycles)

## Symptoms
In `sim006`, the SNN layer correctly fires under heavy traffic (Experiment 1 & 2). However, in Experiment 3, traffic is injected at a very low rate (1 spike every 5 clock cycles). The expected behavior is that the membrane potential should leak away between spikes, preventing the neuron from reaching the threshold (300).
Instead, the neuron still fires. The leak mechanism is not functioning over time.

## Root Cause Hypothesis
In `snn_tff_neuron.v`, the integration and leak logic is wrapped inside an `if (valid_in)` block. When `valid_in` is low, the pipeline holds state (`membrane_u` is untouched). In biological SNNs, leakage occurs continuously over time, regardless of whether a new spike arrives. By gating the update with `valid_in`, the network behaves like an event-driven system without a local timer.

## Experiments & Fix
To fix this, the leak equation must be applied every clock cycle. The synaptic current `I[t]` will just be 0 if `valid_in` is low.

**Attempt 1 (Fix):**
```verilog
    wire signed [DATA_WIDTH-1:0] syn_input = valid_in ? syn_current : 0;
    wire signed [DATA_WIDTH-1:0] u_temp  = u_decayed + syn_input;
    
    always @(posedge clk) begin
        // Unconditionally update membrane potential every cycle
        if (u_temp >= THRESHOLD) begin
            spike_out  <= 1'b1;
            membrane_u <= 0;
        end else begin
            spike_out  <= 1'b0;
            membrane_u <= u_temp;
        end
    end
```

## Verification
This will be applied in `rtl_v007`. The expectation is that Experiment 3 in the testbench will now remain entirely silent (0 firings), proving that the leaky integrate-and-fire dynamic is working correctly to filter out low-rate noise.

## Lessons Learned
In digital SNN design, the definition of "time" is critical. If time progresses with the clock, the leak must be applied continuously. If time progresses only with `valid_in` (event-driven), then we must subtract a leak proportional to the timestamp difference $\Delta t$. For high-speed FPGA design, cycle-accurate continuous leaking is simpler and maps directly to the line rate.
