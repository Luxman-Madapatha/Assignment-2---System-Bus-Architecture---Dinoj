# Testbench Documentation

This directory contains the verification suite used to evaluate the correctness of the shared bus architecture. The testbench files are HDL-based behavioral checks written to validate the RTL implementation under a range of operating conditions. These modules provide the functional evidence required to confirm that the design satisfies the specified bus protocol and address-mapping requirements.

## 1. Scope of Verification

The testbench suite is designed to verify the following system aspects:

- arbitration policy
- reset and idle-state operation
- address decode correctness
- memory-mapped slave selection
- read and write transaction behavior
- unmapped-address handling
- end-to-end bus protocol operation
- board-to-board signal propagation

The tests are intentionally structured to isolate subsystem behavior before progressing to more complex system-level validation.

## 2. Testbench Set

The repository contains four primary testbench files:

- `tb_arbiter.v`
- `tb_addr_decoder.v`
- `tb_top.v`
- `tb_two_boards.v`

### 2.1 `tb_arbiter.v`

This testbench validates the `arbiter.v` module. It is intended to confirm that:

- `M0` has higher priority than `M1`
- the grant remains active until the request is released
- no mid-transaction preemption occurs
- the `busy` signal is asserted under active bus ownership
- the reset state returns the bus to the idle condition

This is the most direct verification of the arbitration behavior specified by the hardware design.

### 2.2 `tb_addr_decoder.v`

This testbench confirms the response of the address decoder to the memory map. It checks the proper selection of:

- S0 for the lower address region
- S1 for the upper address region
- S2 for the 2 KB restricted region
- no valid selection for unmapped addresses

In addition, the file verifies boundary conditions at the address transitions used by the design. These checks are essential for confirming that the implemented memory map matches the specification.

### 2.3 `tb_top.v`

This testbench is the main behavioral validation of the full bus controller. It exercises the entire shared bus implementation and confirms:

- arbitration between two masters
- correct operation of the decode logic
- sequencing across transaction beats
- completion of read and write cycles
- response generation and valid `m_rdata`
- safe behavior when addresses are unmapped
- correct dec_err signaling

This is the central verification target of the repository and is the most comprehensive functional check of the design.

### 2.4 `tb_two_boards.v`

This testbench models the board-to-board interconnect used in the FPGA hardware implementation. It verifies the functional assumptions associated with the distributed bus design:

- one board acts as the shared bus resource
- the second board contains the master and slave logic
- bus signals interconnect across FPGA boundaries
- transaction semantics remain valid under board-to-board communication assumptions

This test is essential for validating the physical architecture of the project beyond the isolated RTL simulation environment.

## 3. Verification Methodology

The testbenches generally follow a standard verification approach:

1. stimulus generation
2. clock and reset application
3. functional excitation
4. signal observation
5. expected-result assertion
6. failure detection and debugging

This pattern provides reproducible validation and allows errors to be localized to specific modules.

## 4. Execution Strategy

The repository provides a direct command-line compilation flow for running the testbenches:

```bash
iverilog -g2005 -o arb  rtl/*.v tb/tb_arbiter.v      && vvp arb
iverilog -g2005 -o dec  rtl/*.v tb/tb_addr_decoder.v && vvp dec
iverilog -g2005 -o top  rtl/*.v tb/tb_top.v          && vvp top
iverilog -g2005 -P tb_top.NODE_CLK_INV=1 -o topi rtl/*.v tb/tb_top.v && vvp topi
iverilog -g2005 -o two  rtl/*.v fpga/*.v tb/tb_two_boards.v && vvp two
