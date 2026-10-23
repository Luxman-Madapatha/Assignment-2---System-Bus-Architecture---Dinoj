# Testbench Directory

This directory contains the verification suite for the bus architecture. The testbench files are responsible for exercising the RTL under controlled conditions and checking whether the hardware implementation behaves correctly for the expected bus transactions.

## Purpose

The testbenches validate the design at different levels of abstraction:

- low-level arbitration checks
- address decoding and boundary validation
- end-to-end bus protocol checks
- board-to-board interconnect simulation

These files are the main proving ground for the repository. In a typical HDL project, they verify correctness before synthesis or deployment.

## Testbench files

The project includes these four major testbenches:

- `tb_arbiter.v`
- `tb_addr_decoder.v`
- `tb_top.v`
- `tb_two_boards.v`

## File descriptions

### `tb_arbiter.v`

This testbench verifies the corrected priority-based arbitration behavior in `rtl/arbiter.v`.

It checks that:

- the bus is idle at reset
- `M0` receives grant first when both masters request the bus
- `M1` is served only when `M0` is not requesting
- the active grant persists until the current request is released
- no preemption occurs mid-transaction
- the `busy` flag reflects bus ownership correctly

Use cases:

- confirm priority ordering
- validate hold-time behavior
- ensure that grant transitions are deterministic and safe

### `tb_addr_decoder.v`

This testbench targets the logic in `rtl/addr_decoder.v`.

It verifies that:

- address ranges are decoded to the expected slave
- `S0`, `S1`, and `S2` are selected correctly
- boundary addresses such as `0x0FFF`, `0x1000`, `0x1FFF`, `0x2000`, and `0x2800` are treated properly
- unmapped addresses produce no valid slave selection
- `hit` correctly indicates whether an address is valid

This testbench is essential for confirming the memory map used by the bus system.

### `tb_top.v`

This is the most important simulation testbench for the design.

It exercises the full shared-bus controller implemented in `rtl/bus_top.v` and verifies:

- arbitration with two masters
- decode of the target slave
- bus beat sequencing
- read transaction completion
- write transaction completion
- unmapped accesses returning a safe response
- decode-error handling
- contention and bus release behavior

This testbench is the closest match to the full system behavior and is used to validate the actual bus protocol implementation.

### `tb_two_boards.v`

This testbench validates the board-to-board communication model used by the FPGA implementation.

It simulates the case where:

- one board acts as the bus controller / shared resource
- the other board contains masters and slave memory
- GPIO-style signals pass between the two logical boards
- timing and interconnect assumptions are tested in a realistic system-level setup

This test is important for validating the system’s distributed hardware concept and confirming that the design remains coherent when the bus is physically split across two DE0 boards.

## Typical simulation pattern

Each testbench follows a standard pattern:

1. define module under test
2. create clock and reset stimulus
3. drive requests and addresses
4. observe outputs such as grants, select lines, read data, and ready pulses
5. assert expected behavior with self-checking conditions

The assertions are designed to fail if the bus does not meet the expected protocol.

## Typical verification goals

Across the suite, the following behaviors are checked repeatedly:

- reset defaults are correct
- bus is inactive when no request is present
- grant is awarded to the correct master
- master cannot be preempted during its active transaction
- address range decoding is correct
- valid read returns data
- invalid address returns safe default data
- bus recovers cleanly after a request completes

## Command-line execution

The project includes direct Icarus Verilog commands for running all tests quickly:

```bash
iverilog -g2005 -o arb  rtl/*.v tb/tb_arbiter.v      && vvp arb
iverilog -g2005 -o dec  rtl/*.v tb/tb_addr_decoder.v && vvp dec
iverilog -g2005 -o top  rtl/*.v tb/tb_top.v          && vvp top
iverilog -g2005 -P tb_top.NODE_CLK_INV=1 -o topi rtl/*.v tb/tb_top.v && vvp topi
iverilog -g2005 -o two  rtl/*.v fpga/*.v tb/tb_two_boards.v && vvp two
```

These commands provide an easy path for CI-style simulation or quick verification from the shell.

## Relationship to the simulation scripts

The `sim/` directory contains the `.do` files that run the testbench flows in ModelSim/Questa, while the `tb/` directory contains the actual queued test stimuli and checking logic.

In practical terms:

- `tb/*.v` = scenarios and assertions
- `sim/*.do` = script wrapper and waveform viewer setup

## Recommended validation order

A sensible validation flow is:

1. run `tb_arbiter.v`
2. run `tb_addr_decoder.v`
3. run `tb_top.v`
4. run `tb_two_boards.v`

This order builds confidence from the simplest subsystem to the fully integrated bus design.

## Summary

The `tb/` folder is the behavioral verification layer of the project. It provides the test scenarios needed to confirm that the bus protocol, arbitration logic, decode map, and board-level interconnect all behave as intended.

If you want to understand whether the design is correct, start here.
