# FPGA folder: DE0 board-level integration and hardware wiring

The `fpga/` directory contains the board-level wrappers for the actual hardware implementation. These files connect the abstract RTL logic to the physical hardware interfaces on the DE0 boards and define how the bus is mapped across the two boards.

## Purpose of the FPGA layer

The RTL describes the bus logic, but the FPGA layer is where the design becomes a real system on hardware. This folder defines:

- board A: the shared bus controller
- board B: the node with masters and slaves
- reset synchronization
- display output logic
- board-to-board wiring over GPIO headers

This is the layer that turns the functional bus design into a demonstrable FPGA system.

## Main files

### 1. `de0_bus_board.v`

This is the board A wrapper. It implements the shared bus side of the hardware.

Responsibilities:

- generate a bus clock from `CLOCK_50`
- synchronize reset using `reset_sync.v`
- provide the bus controller instance `bus_top`
- connect to board B over GPIO lines
- expose status through LEDs and 7-segment displays

The important idea is that board A is the shared resource controller. It owns the central bus logic and drives the board-to-board bus signals through the GPIO ports.

It also sends the inverted bus clock to board B, so board B sees timing offset by half a clock cycle. This helps with signal timing across the ribbon cable.

### 2. `de0_node_board.v`

This is the board B wrapper. It models the node board that contains both masters and all three slave memory blocks.

Responsibilities:

- receive the bus clock and reset from board A
- instantiate two `master_model` blocks
- instantiate three `slave_model` blocks
- accept user actions from switches and push buttons
- display the last read data on the 7-seg displays
- send request and response signals back to board A over the GPIO interface

This is the board where user interaction happens: buttons trigger transactions, and the LEDs show grant/busy states.

### 3. `reset_sync.v`

This module synchronizes an asynchronous reset into the local clock domain.

It does two things:

- if the incoming reset is asserted, it forces the internal synchronization register to zero
- on the next active clock edges, it releases the reset in a clean, synchronized way

This prevents metastability and ensures the bus starts in a deterministic state after power-up or reset.

### 4. `seg7.v`

This is a simple hexadecimal-to-7-segment decoder. It converts a nibble to the pattern needed by the DE0 display.

It is used to decode:

- the bus write data on board A
- the last read data values on board A and board B

This gives a simple hardware visualization of transaction values.

## How the FPGA files interact with the rest of the project

The file relationship is:

- `rtl/bus_top.v` provides the real bus protocol implementation
- `fpga/de0_bus_board.v` instantiates that logic on board A
- `fpga/de0_node_board.v` creates the master/slave endpoints on board B
- `reset_sync.v` makes reset safe and consistent in both boards
- `seg7.v` converts numerical values into board-readable display patterns

The connection across the boards is done through GPIO headers. The code explicitly maps signals such as:

- `s_wdata` and `s_valid` from board A to board B
- `m0_req`, `m1_req`, and grants between boards
- returned read data and completion signals back to the board that originated the transaction

This is a true distributed hardware system, not just a software model.

## How the whole application is assembled

The complete application is assembled in layers:

1. `rtl/` defines the bus logic and memory protocol.
2. `tb/` verifies that logic with simulation.
3. `sim/` gives the waveform-based debugging environment.
4. `fpga/` packages the logic for real DE0 hardware and connects the two boards with GPIO wiring.

The physical system works like this:

- board A provides arbitration and central bus control
- board B initiates transactions from its two masters and contains the slave memory regions
- the bus signals are transmitted over the ribbon-cable-connected GPIO ports
- the system behaves as a single shared bus even though it spans two FPGA boards

## Why the FPGA folder is essential

This is the folder that makes the project a complete application rather than just a simulation. It bridges the domain between HDL design and real hardware operation on DE0 boards.

The FPGA code shows the full practical implementation of the assignment: shared bus, board-to-board communication, user input, display feedback, and reset timing.
