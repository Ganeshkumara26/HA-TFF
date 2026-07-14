# Mathematical Formulation: Hardware-Efficient LIF Neuron

## 1. Biological Model
The Leaky Integrate-and-Fire (LIF) neuron is defined by a differential equation modeling the membrane potential $V(t)$:
$$ \tau_m \frac{dV(t)}{dt} = - (V(t) - V_{rest}) + R \cdot I(t) $$
Where:
- $\tau_m$ is the membrane time constant.
- $V_{rest}$ is the resting potential.
- $I(t)$ is the input current (weighted sum of incoming spikes).

When $V(t) \ge V_{thresh}$, the neuron emits a spike and resets its potential to $V_{reset}$.

## 2. Discrete-Time Approximation for FPGA
To map this to a digital clock domain, we discretize time into steps $t \in \{1, 2, \dots, T\}$. 
Let $U[t]$ be the discrete membrane potential.
The equation simplifies to:
$$ U[t] = \alpha \cdot U[t-1] + \sum_i W_i \cdot S_i[t] $$
Where:
- $\alpha \in (0, 1)$ is the decay (leak) factor.
- $W_i$ is the synaptic weight from input neuron $i$.
- $S_i[t] \in \{0, 1\}$ is the binary spike from input neuron $i$.

If $U[t] \ge V_{thresh}$, then $S_{out}[t] = 1$ and $U[t]$ is reset.

## 3. Hardware Optimization (Bit-Shift Leak)
Floating-point multiplication for $\alpha \cdot U[t-1]$ is too expensive. We can approximate $\alpha$ using powers of 2.
For example, if we want $\alpha \approx 0.875$, we can compute:
$$ \alpha \cdot U \approx U - (U \gg 3) $$
This replaces a multiplier with a simple right-shift and a subtractor.

## 4. Hardware Implementation Equations
1. **Integration**: $I[t] = \sum_i W_i \cdot S_i[t]$
2. **Leakage**: $U_{decay}[t] = U[t-1] - (U[t-1] \gg \text{LEAK\_SHIFT})$
3. **Update**: $U_{temp}[t] = U_{decay}[t] + I[t]$
4. **Fire & Reset**:
   - If $U_{temp}[t] \ge V_{thresh}$: $S_{out}[t] = 1$, $U[t] = 0$ (Hard Reset)
   - Else: $S_{out}[t] = 0$, $U[t] = U_{temp}[t]$

## 5. Conclusion
By using integer weights, a right-shift leak, and a hard reset, a fully functional LIF neuron can be built entirely out of Adders, Subtractors, and Comparators. Zero DSP slices are required. This makes the architecture massively scalable on an Artix-7 FPGA, allowing us to build a robust SNN-TFF anomaly detection engine.
