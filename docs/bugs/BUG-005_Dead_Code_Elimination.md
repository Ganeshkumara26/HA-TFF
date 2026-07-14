# Bug Report: BUG-005 (Total Logic Optimization via Dead Code Elimination)

## Symptoms
In Iteration 009, the full system `ha_tff_system_top_v001.v` synthesized successfully, but the Vivado utilization report showed `0 LUTs, 0 CARRY4, 0 BRAMs, 74 IBUFs, 75 OBUFs`. 
The entire HA-TFF Datapath, Parser, Cuckoo Hash, and SNN Coprocessor were optimized out of existence.

## Root Cause Hypothesis
During System Integration, the final override logic was written as:
```verilog
wire final_forward = (dp_match_valid && dp_action_forward && !anomaly_detected);
    
assign m_axis_tdata  = s_axis_tdata;
assign m_axis_tkeep  = s_axis_tkeep;
assign m_axis_tlast  = s_axis_tlast;
assign m_axis_tvalid = s_axis_tvalid; // BUG: Did not use final_forward
```
Because `final_forward` was never assigned to an output port, Vivado traced the logic backward from the OBUFs. It saw that `m_axis_tvalid` was just a wire connected to `s_axis_tvalid`. Therefore, the thousands of LUTs and BRAMs calculating `final_forward` had absolutely no effect on any output pin. 
Vivado correctly deleted the entire firewall to save area, turning it into a simple pass-through wire.

## Fix Strategy
1. **Fix the RTL**: Assign the override logic directly to the output valid signal.
```verilog
assign m_axis_tvalid = final_forward;
```

## Resolution
This will be corrected in `v002` of the System Top (`rtl_v010`). This highlights the importance of always checking the Utilization Report after Synthesis, as a "0 error" log does not mean the design actually exists on silicon.
