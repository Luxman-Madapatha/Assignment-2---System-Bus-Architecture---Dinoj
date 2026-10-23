# System Bus Architecture for Two DE0 Boards

This repository implements a compact, 8-bit multiplexed parallel bus for a two-board FPGA system. The design is organized around a shared bus controller on one DE0 board and master/slave logic on the second board.

The project includes:
- 2 masters
- 3 slaves
- fixed-priority arbitration
- address decoding for memory-mapped access
- testbenches for simulation and FPGA demonstration

## Repository structure

```text
.
├── README.md
├── rtl/
│   ├── addr_decoder.v
│   ├── arbiter.v
│   ├── bus_top.v
│   ├── master_model.v
│   └── slave_model.v
├── tb/
│   ├── tb_addr_decoder.v
│   ├── tb_arbiter.v
│   ├── tb_top.v
│   └── tb_two_boards.v
├── sim/
│   ├── sim_arbiter.do
│   ├── sim_decoder.do
│   ├── sim_top.do
│   └── sim_top_inv.do
├── fpga/
│   ├── de0_bus_board.v
│   ├── de0_node_board.v
│   ├── reset_sync.v
│   └── seg7.v
└── .gitignore
```

## Bus architecture

The bus is an 8-bit multiplexed parallel bus. Address and data share the same 8 wires and are transferred in consecutive beats:

- Beat 0: HEADER = `{RW, 0, A[13:8]}`
- Beat 1: ADDR_LO = `A[7:0]`
- Beat 2: WDATA = write data (write transactions only)
- Read response: bus returns `m_ready` with `m_rdata`

The design uses a 14-bit address space (16 KB total), with 10 KB memory actually populated across the 3 slaves.

## Address map

| Slave | Size | Address range | Decode condition |
|---|---:|---|---|
| S0 | 4 KB | `0x0000`–`0x0FFF` | `A[13:12] = 00` |
| S1 | 4 KB | `0x1000`–`0x1FFF` | `A[13:12] = 01` |
| S2 | 2 KB | `0x2000`–`0x27FF` | `A[13:12] = 10` and `A[11] = 0` |
| Unmapped | — | `0x2800`–`0x3FFF` | no valid slave selected |

Unmapped transactions complete safely and return `0xEE` while setting the decode error flag.

## RTL modules

### `rtl/arbiter.v`
Implements a fixed-priority, non-preemptive arbiter.
- `M0` has higher priority than `M1`
- once a master is granted, it keeps the bus until it releases its request
- the arbiter uses the current state as the grant vector

### `rtl/addr_decoder.v`
Decodes the upper address bits from the header beat and generates:
- one-hot slave select
- 2-bit slave select code
- `hit` indicator for valid mapped addresses

### `rtl/bus_top.v`
Top-level bus controller. It combines:
- arbiter logic
- master-to-bus multiplexing
- address decoding
- transaction tracking
- response generation and error handling

### `rtl/master_model.v`
Behavioral master model used for simulation and verification. It drives requests, validates bus transactions, and captures returned data.

### `rtl/slave_model.v`
Behavioral memory slave model with address-range awareness and read/write behavior that matches the bus protocol.

## FPGA / board mapping

The repository includes two DE0 board wrappers:

- `fpga/de0_bus_board.v` — Board A, implements the shared bus logic and board-level I/O wiring
- `fpga/de0_node_board.v` — Board B, contains both masters and the three slaves

Additional support modules:
- `fpga/reset_sync.v` — reset synchronizer
- `fpga/seg7.v` — seven-segment display logic

The bus is wired across the DE0 GPIO headers using ribbon cables, with GPIO0 and GPIO1 carrying the cross-board signals.

## Simulation

The `sim/` directory contains ModelSim/Questa scripts for the bus verification flow:

```bash
cd sim
# ModelSim / Questa
#do sim_arbiter.do
#do sim_decoder.do
#do sim_top.do
# or
#do sim_top_inv.do
```

Icarus Verilog commands used in this project:

```bash
iverilog -g2005 -o arb  rtl/*.v tb/tb_arbiter.v      && vvp arb
iverilog -g2005 -o dec  rtl/*.v tb/tb_addr_decoder.v && vvp dec
iverilog -g2005 -o top  rtl/*.v tb/tb_top.v          && vvp top
iverilog -g2005 -P tb_top.NODE_CLK_INV=1 -o topi rtl/*.v tb/tb_top.v && vvp topi
iverilog -g2005 -o two  rtl/*.v fpga/*.v tb/tb_two_boards.v && vvp two
```

## Testbenches

| Testbench | Purpose |
|---|---|
| `tb/tb_arbiter.v` | verifies arbitration, fixed priority, no preemption, reset behavior |
| `tb/tb_addr_decoder.v` | checks address decode boundaries and mapping correctness |
| `tb/tb_top.v` | end-to-end bus verification for idle, read/write, unmapped accesses, and two-master contention |
| `tb/tb_two_boards.v` | verifies the two-board GPIO-backed interconnect |

## Quartus build notes

The project targets the Cyclone III EP3C16F484C6 used on the DE0 boards.

Two Quartus projects are expected:
- Project A: `rtl/*.v`, `fpga/de0_bus_board.v`, `fpga/reset_sync.v`, `fpga/seg7.v`, top-level = `de0_bus_board`
- Project B: same files with `fpga/de0_node_board.v`, top-level = `de0_node_board`

## Notes

- Reset is asynchronous active-low and clocking is rising-edge based.
- The bus is intentionally designed to never hang on unmapped memory access.
- Fixed latency is used for slave reads; the bus generates `m_ready` after the required response delay.

This repository is a complete FPGA-friendly bus design example for a system with shared bus arbitration, memory-address decoding, and board-to-board communication.
