# Simulation and Waveform Verification

This directory contains the simulation environment and command scripts used to validate the bus design at the signal and waveform level. The simulation layer exists to confirm that the RTL behaves as intended before the design is transferred to hardware implementation or board-level integration.

The simulation workflow is structured around ModelSim/Questa `.do` scripts and Icarus Verilog command-line execution. These tools provide a practical means to validate timing, signal sequencing, arbitration decisions, and read/write protocol behavior under controlled test conditions.

## 1. Purpose of the Simulation Environment

The simulation environment supports several key verification objectives:

- validation of arbitration behavior
- verification of address decode correctness
- testing of end-to-end bus transactions
- inspection of waveform timing
- checking reset and bus-release conditions
- verification of board-to-board timing assumptions

The simulation scripts are designed to reduce manual compile and run effort while preserving signal visibility for debugging and validation.

## 2. Simulation Scripts

The project includes the following simulation scripts:

- `sim_arbiter.do`
- `sim_decoder.do`
- `sim_top.do`
- `sim_top_inv.do`

Each script focuses on a distinct aspect of the system and is intended to be run in a consistent, targeted verification flow.

### 2.1 `sim_arbiter.do`

This script executes the arbiter-focused simulation. It is intended to validate:

- master priority ordering
- non-preemptive bus ownership
- proper reset behavior
- generation of `busy` when a grant has been assigned
- state transitions between idle and active grant states

This script is most useful during low-level functional verification of the arbitration logic.

### 2.2 `sim_decoder.do`

This script verifies address decode operation. It is used to confirm:

- correct mapping between address and slave
- proper decode behavior at boundary conditions
- correct handling of the unmapped address region
- correct `hit` signal generation
- proper `sel_code` assignment

This script is particularly important for validating the memory map and ensuring that illegal addresses do not propagate to the wrong device.

### 2.3 `sim_top.do`

This script runs the comprehensive top-level bus simulation. It validates:

- bus arbitration
- bus beat sequencing
- data propagation
- read and write transaction behavior
- response generation and completion
- end-to-end bus-level state transitions

The script supports a full-system verification of the shared bus protocol and is the primary simulation workflow for the design.

### 2.4 `sim_top_inv.do`

This script models the inverted-clock timing condition applied to the second board in the FPGA implementation. It is used to assess whether the design remains functionally correct when timing is offset across the board-to-board interconnect.

The file is particularly relevant because the FPGA system physically spans two DE0 boards and relies on board-to-board signal propagation. The simulation scenario tests the design under shifted timing assumptions without requiring a hardware implementation.

## 3. Standard Simulation Workflow

A typical simulation flow is as follows:

1. Open the simulator environment, such as ModelSim or Questa.
2. Change to the `sim/` directory.
3. Load the desired `.do` script.
4. Inspect the signal waveforms.
5. Verify transaction ordering and response timing.
6. Correct any RTL issue identified during verification.

Example:

```tcl
#do sim_arbiter.do
#do sim_decoder.do
#do sim_top.do
#do sim_top_inv.do
