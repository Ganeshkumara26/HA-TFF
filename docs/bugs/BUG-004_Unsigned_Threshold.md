# Bug Report: BUG-004 (Signed/Unsigned Threshold Comparison)

## Symptoms
In `sim007`, while testing the BUG-003 fix (Leak Logic), the Safe Neuron began firing wildly even when injected with anomaly traffic. 
Calculations showed that the Safe Neuron was receiving a total synaptic current of `-140`. The expected behavior is that the membrane potential becomes highly negative (inhibited) and does not fire. Instead, it fired instantly.

## Root Cause Hypothesis
In Verilog, if a comparison involves one signed operand and one unsigned operand, the signed operand is implicitly cast to unsigned.
In `snn_tff_neuron_v002.v`:
```verilog
parameter THRESHOLD = 16'd300;
wire signed [15:0] u_temp;

if (u_temp >= THRESHOLD) // BUG!
```
`-140` in 16-bit two's complement is `16'hFF74`. 
When cast to unsigned, `16'hFF74` becomes `65396`.
The hardware evaluated `65396 >= 300`, which is true, causing a false positive spike.

Additionally, the single-cycle synaptic sum for the Anomaly neuron was `410`, which is greater than `300`. This caused the Anomaly neuron to fire instantly in one clock cycle, bypassing the temporal integration and leak dynamics completely.

## Fix Strategy
1. **Fix the RTL**: The parameter `THRESHOLD` must be explicitly signed or evaluated against a signed cast.
```verilog
parameter signed [15:0] THRESHOLD = 16'sd300;
// or
if (u_temp >= $signed(THRESHOLD))
```
2. **Fix the Testbench/Weights**: The threshold must be increased, or the weights decreased, so that it takes *multiple* cycles to fire. For example, if weights sum to 100, and threshold is 300, it takes 3 consecutive cycles to fire. This allows us to properly test temporal integration and leaking.

## Resolution
This will be corrected in `v003` of the RTL. This highlights the severe dangers of mixing signed DSP arithmetic with unsigned literal parameters in Verilog.
