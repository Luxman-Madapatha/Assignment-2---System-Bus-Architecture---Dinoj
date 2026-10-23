# System Specification: 8-bit Parallel Bus (2 Masters, 3 Slaves)

This document describes the board-to-board FPGA bus implemented in this repository for a two-DE0 system. The design provides a shared 8-bit multiplexed parallel bus connecting two masters to three memory-mapped slave devices.

## 1. Scope

The system is intended to support:

- Two bus masters (`M0`, `M1`)
- Three slave devices (`S0`, `S1`, `S2`)
- A shared 8-bit parallel data/address bus
- Fixed-priority bus arbitration
- Address decoding and unmapped-address handling
- Read and write transactions across a board-to-board FPGA interconnect

The design is implemented in a compact, FPGA-friendly form for hardware verification and demonstration on DE0-class boards.

## 2. System Overview

The architecture uses a centralized bus controller and a single shared data path. Each master requests ownership of the bus, and the arbiter grants access according to a static priority scheme.

- `M0` has higher priority than `M1`
- Once a master is granted the bus, it retains control until it releases the request
- The arbiter is non-preemptive
- Slave devices are selected by decoded address bits

The bus is physically distributed between two DE0 boards using GPIO header connections, with the bus controller and shared arbitration logic on one board and the master/slave endpoints on the complement board.

## 3. Bus Topology

The system behaves as a single shared bus with the following topology:

- 1 shared 8-bit multiplexed parallel bus
- 2 masters
- 3 slaves
- 1 central arbiter
- 1 address decoder
- 1 response/error path for all slaves

### Masters

`M0` and `M1` are the initiators. Each master can:

- request bus ownership
- issue a read or write transaction
- observe response completion and data validity

### Slaves

The three slaves provide memory-mapped storage regions:

- `S0`: 4 KB region
- `S1`: 4 KB region
- `S2`: 2 KB region

An unmapped region is also defined for illegal or out-of-range address access.

## 4. Signal and Protocol Model

The bus is multiplexed: the same 8 physical wires carry address and data at different phases of a transaction.

### 4.1 Transaction Beat Structure

The protocol is defined in consecutive bus phases.

1. HEADER
   - `RW` bit indicates read/write direction
   - bit 0 is reserved or zero-extended as required by the design
   - upper address bits: `A[13:8]`

2. ADDR_LO
   - lower address byte: `A[7:0]`

3. WRITE DATA
   - used only for write transactions
   - transferred over the shared bus

4. RESPONSE / READY
   - bus returns completion status via `m_ready`
   - read transactions return valid data via `m_rdata`

The repository README describes the cycle as:

- Beat 0: `HEADER = {RW, 0, A[13:8]}`
- Beat 1: `ADDR_LO = A[7:0]`
- Beat 2: `WDATA` (write operations only)
- Read response: `m_ready` with `m_rdata`

### 4.2 Control Signals

Although exact RTL port names may differ slightly across modules, the conceptual bus interface includes the following semantics:

- `clk`: system clock
- `rst_n`: asynchronous or synchronous reset as defined by the design
- `req[1:0]`: request lines from masters
- `grant[1:0]`: arbitration result to masters
- `rw`: transaction direction
- `addr`: current transaction address
- `data`: multiplexed bus data
- `m_ready`: transaction completion flag
- `m_rdata`: read response data
- `hit`: valid slave selected

## 5. Address Map

The bus uses a 14-bit address space, giving a total 16 KB address range.

| Slave | Size | Address Range | Decode Condition |
|---|---:|---|---|
| `S0` | 4 KB | `0x0000` to `0x0FFF` | `A[13:12] = 00` |
| `S1` | 4 KB | `0x1000` to `0x1FFF` | `A[13:12] = 01` |
| `S2` | 2 KB | `0x2000` to `0x27FF` | `A[13:12] = 10` and `A[11] = 0` |
| Unmapped | — | `0x2800` to `0x3FFF` | no valid slave selected |

### Address Decoding Behavior

- `S0` occupies the lower 4 KB
- `S1` occupies the next 4 KB block
- `S2` occupies a 2 KB block with restricted decode conditions
- any unmapped region is rejected safely

Unmapped access is not allowed to hang the bus. The design returns `0xEE` and asserts the decode-error indication.

## 6. Arbitration

The bus uses a fixed-priority arbiter with non-preemptive service. The behavioral intent is:

- `M0` has higher priority than `M1`
- the current grant remains active until the current transaction is completed
- a lower-priority master cannot interrupt an ongoing transfer
- the arbiter selects only one master at a time

This matches the project README and is consistent with the `rtl/arbiter.v` module behavior.

## 7. Read and Write Behavior

### Write Transactions

A write transaction follows:

1. Master requests bus ownership
2. Arbiter grants the bus
3. Master drives HEADER and ADDRESS
4. Master drives write data on the shared bus
5. Selected slave writes data to its memory region
6. Bus returns a completion flag

### Read Transactions

A read transaction follows:

1. Master requests bus ownership
2. Arbiter grants the bus
3. Master drives HEADER and ADDRESS
4. Selected slave decodes the address and presents the data
5. Bus drives `m_ready` and `m_rdata`
6. Master captures the read data

The design supports fixed-latency response timing, with read completion and data value returned after the required delay.

## 8. Slave Selection and Error Handling

Address decoding is implemented in `rtl/addr_decoder.v` and produces:

- a one-hot slave-select vector
- a 2-bit slave-select code
- a `hit` flag indicating whether the address maps to a valid slave

If the address falls outside the valid region:

- the decoder returns no valid slave select
- the transaction is treated as unmapped
- the bus completes safely with a default value
- the decode error flag is set

## 9. Timing and Reset Assumptions

The repository specification indicates the following implementation assumptions:

- reset is active-low
- clocking is rising-edge sensitive
- bus transfers are serialized over multiple beats
- read completion is controlled by the response logic and `m_ready`

These assumptions are consistent with the hardware design and simulation testbenches.

## 10. FPGA Implementation Mapping

The repository includes two board-level wrappers:

- `fpga/de0_bus_board.v` — shared bus controller / board A
- `fpga/de0_node_board.v` — master/slave node / board B

The bus is connected across the DE0 board GPIO headers with ribbon cable interconnects, allowing a shared operating bus between the two boards.

## 11. Simulation and Verification

The `sim/` directory contains ModelSim/Questa command scripts, and the design is validated through dedicated testbenches:

- `tb/tb_arbiter.v`: arbitration behavior and fixed-priority logic
- `tb/tb_addr_decoder.v`: decode correctness and address boundaries
- `tb/tb_top.v`: end-to-end bus validation
- `tb/tb_two_boards.v`: board-to-board interconnect validation

This confirms the bus protocol, decode logic, and arbitration behavior under read, write, idle, and error conditions.

## 12. Summary

The implemented bus is a compact and practical FPGA-oriented shared bus architecture intended for a two-board system. It provides:

- 2 masters and 3 slaves
- 8-bit multiplexed parallel bus transfers
- fixed-priority arbitration
- memory-mapped decode logic
- safe handling of invalid addresses
- support for both read and write transactions

This design fits the repository’s RTL, testbench, and FPGA goals and serves as a complete hardware demonstration of a shared-system bus architecture.

## 13. Related Repository Files

- `README.md`
- `rtl/arbiter.v`
- `rtl/addr_decoder.v`
- `rtl/bus_top.v`
- `rtl/master_model.v`
- `rtl/slave_model.v`
- `tb/tb_arbiter.v`
- `tb/tb_addr_decoder.v`
- `tb/tb_top.v`
- `tb/tb_two_boards.v`
- `fpga/de0_bus_board.v`
- `fpga/de0_node_board.v`

This specification is intended as a concise engineering reference for the repository implementation and matches the design language used throughout the project.
