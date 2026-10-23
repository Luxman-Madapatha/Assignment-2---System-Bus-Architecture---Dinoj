# RTL Design Description

This directory contains the register-transfer level (RTL) implementation of the shared system bus architecture developed for a two-board FPGA platform. The RTL modules describe the functional behavior of the bus controller, arbitration policy, slave selection logic, and the memory-mapped transaction protocol used across the system.

The design is organized around a centralized bus controller that interfaces with two masters and three slave devices. The architecture emphasizes deterministic arbitration, low-complexity decode logic, and fixed-latency response behavior appropriate for FPGA-based bus-level verification and demonstration.

## 1. Design Objectives

The RTL implements a compact 8-bit multiplexed parallel bus intended for a dual-DE0 hardware platform. The system must satisfy the following functional requirements:

- support two bus masters, M0 and M1
- support three memory-mapped slave devices, S0, S1, and S2
- enforce a deterministic fixed-priority arbitration policy
- decode the destination slave from the transaction address
- support read and write transactions over a shared 8-bit bus
- handle invalid or unmapped addresses safely without bus deadlock
- provide a simulation-friendly protocol suitable for FPGA validation

## 2. System-Level Architecture

The design consists of the following building blocks:

- `arbiter.v`: shared medium access control
- `addr_decoder.v`: address-to-slave decode logic
- `bus_top.v`: top-level bus controller and transaction sequencer
- `master_model.v`: behavioral master model
- `slave_model.v`: behavioral memory slave model

The bus acts as a single shared communication medium among multiple bus initiators and memory endpoints. All masters compete for access through a central arbiter, and only one master is granted access at a time.

## 3. Bus Protocol

The implemented bus is a multiplexed 8-bit parallel interface. The same eight physical signal lines are reused across multiple transfer phases:

- Beat 0: HEADER = {RW, 0, A[13:8]}
- Beat 1: ADDR_LO = A[7:0]
- Beat 2: WDATA = write data (write transactions only)
- Completion phase: `m_ready` and `m_rdata` are asserted as part of the response

The protocol is intentionally simple and hardware-friendly, enabling compact implementation while preserving enough structure for realistic transaction modeling.

The address space is 14-bit, giving a total of 16 KB of addressable space. The implemented decode map allocates:

- S0: 4 KB memory region at 0x0000–0x0FFF
- S1: 4 KB memory region at 0x1000–0x1FFF
- S2: 2 KB memory region at 0x2000–0x27FF
- Unmapped region: 0x2800–0x3FFF

## 4. Address Decoding

The address decoder is implemented in `rtl/addr_decoder.v`. Its purpose is to convert the upper address bits into a valid selection signal for one of the slave devices.

The decoder performs the following functions:

- receives the upper address bits `A[13:8]`
- identifies the current memory segment
- generates a one-hot slave select vector
- generates a 2-bit select code for slave identification
- sets the `hit` flag when the address maps to a valid device
- ensures unmapped addresses are rejected cleanly

The decode logic is designed to follow the memory map defined in the specification:

- `A[13:12] = 00` selects S0
- `A[13:12] = 01` selects S1
- `A[13:12] = 10` and `A[11] = 0` selects S2
- otherwise, the region is unmapped

This scheme yields a deterministic and efficient decode structure suitable for FPGA synthesis.

## 5. Arbitration

The bus arbiter is implemented in `rtl/arbiter.v`. It creates a fixed-priority, non-preemptive arbitration scheme between two masters.

### Arbitration behavior

- `M0` has higher priority than `M1`
- `M1` can only access the bus when `M0` is not requesting
- the current grant remains active until the requesting master releases the bus
- once the current grant is released, the arbiter reevaluates the state immediately
- no interrupt or mid-transaction preemption is permitted

The arbiter uses a compact state machine with `IDLE`, `M0`, and `M1` states. The active grant is represented directly in the state register, which minimizes extra combinational logic and preserves a glitch-free grant signal path.

## 6. Top-Level Bus Controller

The module `rtl/bus_top.v` is the primary bus controller. It integrates:

- master selection
- bus beat tracking
- address decoding
- write-data propagation
- slave read-data multiplexing
- response generation
- error handling for unmapped transactions

The controller monitors the active grant signal and routes the selected master's valid data and address information onto the shared bus. It also records transaction state and generates `m_ready` when the bus has completed the required response cycle.

The logic includes the following behavioral features:

- `s_sel` is driven to the selected slave
- `s_valid` indicates the active transaction beat
- `m_rdata` is propagated to the granted master
- `m_ready` is generated at the end of the transaction
- invalid accesses return `UNMAPPED_RDATA` (default value `0xEE`)
- `dec_err` is asserted when the requested address is not valid

This implementation is specifically designed to avoid bus lock-up in the event of illegal or unmapped transactions.

## 7. Master and Slave Behavioral Models

### 7.1 Master Model

`rtl/master_model.v` provides a behavioral representation of a bus master. It is used for transaction generation, protocol compliance checking, and testbench stimulus.

The master model is responsible for:

- initiating bus requests
- issuing valid read or write transactions
- driving address and data values onto the bus
- watching the response signals from the bus
- validating the returned data

### 7.2 Slave Model

`rtl/slave_model.v` models a memory device with address-aware behavior. Each slave responds to memory accesses according to the transaction sequence and the decode result.

The slave functionality includes:

- memory storage for the assigned address region
- address-based data selection
- write transaction handling
- read transaction handling
- fixed-latency read response behavior consistent with the bus timing model

## 8. Timing and Reset Semantics

The RTL modules follow a consistent hardware timing convention:

- asynchronous active-low reset (`rst_n`)
- rising-edge clocking (`posedge clk`)
- combinational decode logic for bus selection
- registered propagation of transaction state
- fixed-latency response generation

This arrangement is suitable for both simulation and synthesis and reflects standard FPGA design practice.

## 9. Design Integration

The RTL layer forms the foundation for the remainder of the repository. It is used by:

- simulation scripts in the `sim/` directory
- verification testbenches in the `tb/` directory
- FPGA wrappers in the `fpga/` directory

The hardware hierarchy is therefore structured in a top-down engineering flow:

1. RTL defines the bus architecture
2. Simulation verifies the behavior
3. Testbenches confirm correct functional operation
4. FPGA wrappers translate the design to board-level hardware

## 10. Summary

The `rtl/` directory contains the core hardware implementation of the bus architecture. It defines the arbitration logic, decode policy, master/slave communication protocol, and transaction sequencing required for shared bus operation. From an engineering standpoint, the directory represents the functional implementation layer of the design and is the primary reference for understanding the bus behavior at the HDL level.

The most important modules to inspect for system understanding are:

- `rtl/arbiter.v`
- `rtl/addr_decoder.v`
- `rtl/bus_top.v`

These files define the principal logic responsible for bus access control and transaction execution.
