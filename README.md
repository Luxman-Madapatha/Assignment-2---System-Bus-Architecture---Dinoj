# 8-bit Parallel Bus — 2 Masters, 3 Slaves (4K / 4K / 2K) on two DE0 boards

All RTL uses an **asynchronous active-low reset** and the **rising clock edge**.

```
rtl/   arbiter.v  addr_decoder.v  bus_top.v  master_model.v  slave_model.v
tb/    tb_arbiter.v  tb_addr_decoder.v  tb_top.v  tb_two_boards.v
fpga/  de0_bus_board.v (Board A)  de0_node_board.v (Board B)  reset_sync.v  seg7.v
```

## 1. Functional description

**Bus type.** An 8-bit multiplexed parallel bus. Address and data share the same
8 data lines and are sent as consecutive *beats*, which keeps the wire count low
enough to cross between two DE0 boards on two 40-pin ribbon cables.

| Beat | Content | Notes |
|---|---|---|
| 0 HEADER | `{RW, 0, A[13:8]}` | RW = 1 write, 0 read |
| 1 ADDR_LO | `A[7:0]` | |
| 2 WDATA | write data | write only |

A transaction ends when the bus returns a one-clock `m_ready` pulse (with
`m_rdata` for reads). Total memory is 10 KB, so a 14-bit address (16 KB space) is used.

**Address map**

| Slave | Size | Range | Decode | sel code |
|---|---|---|---|---|
| S0 | 4 KB | 0x0000–0x0FFF | A[13:12]=00 | 1 |
| S1 | 4 KB | 0x1000–0x1FFF | A[13:12]=01 | 2 |
| S2 | 2 KB | 0x2000–0x27FF | A[13:12]=10, A[11]=0 | 3 |
| — | — | 0x2800–0x3FFF | unmapped | 0 |

An unmapped access still completes (the bus never hangs): reads return 0xEE and `dec_err` is set.

**Arbiter.** Fixed priority, M0 > M1, non-preemptive: a master keeps the bus until it
drops `req`; on release the arbiter re-arbitrates in the same clock (direct M0→M1
hand-over). The state register is the grant vector, so grants come straight from
flip-flops. Note: M1 can be starved if M0 requests continuously; this is the
expected trade-off of fixed priority.

**Address decoder.** Combinational, looks only at A[13:8] in the header beat; the bus
latches the resulting select code for the rest of the transaction.

**Slaves.** Synchronous RAMs (inferred as M9K block RAM). Fixed latency: read data
is valid on `sN_rdata` one clock after the slave samples ADDR_LO and is held until
its next read. A slave `ready` wire was deliberately left out to fit the pin budget
(section 4); the bus generates `m_ready` two clocks after the last beat.

**Masters.** One read or write per `start` pulse:
IDLE → REQ (wait gnt) → HDR → ALO → [DAT] → WAIT (bus_ready) → REL (wait gnt low).

## 2. IO definitions

### bus_top (Board A)
| Signal | Dir | Width | Description |
|---|---|---|---|
| clk, rst_n | in | 1 | bus clock, async active-low reset |
| m0_req / m1_req | in | 1 | bus request |
| m0_valid / m1_valid | in | 1 | beat valid |
| m0_dout / m1_dout | in | 8 | master beat (header / addr / data) |
| m0_gnt / m1_gnt | out | 1 | grant |
| m_rdata | out | 8 | read data to masters (shared) |
| m_ready | out | 1 | transaction complete, 1-clock pulse (shared; qualified by own gnt) |
| s_wdata | out | 8 | beat forwarded to all slaves |
| s_valid | out | 1 | beat valid to slaves |
| s_sel | out | 2 | selected slave code (0 = none) |
| s0/s1/s2_rdata | in | 8 | slave read data |
| busy, dec_err | out | 1 | status |

### arbiter
`clk, rst_n, req0, req1` in; `gnt0, gnt1, busy` out.

### addr_decoder
`addr_hi[5:0]` (A[13:8]) in; `slave_sel[2:0]` (one-hot), `sel_code[1:0]`, `hit` out.

### master_model
Command side: `start, rw, addr[13:0], wdata[7:0]` in; `rdata[7:0], done, busy` out.
Bus side: `req, valid, dout[7:0]` out; `gnt, bus_rdata[7:0], bus_ready` in.

### slave_model #(SLAVE_ID, ADDR_W)
`s_sel[1:0], s_valid, s_wdata[7:0]` in; `s_rdata[7:0]` out.
ADDR_W = 12 for 4 KB, 11 for 2 KB.

## 3. Timing diagrams (paste into https://wavedrom.com/editor.html)

Cycle-accurate to the simulation (single-clock view).

**Read** (M0 reads S1)
```json
{"signal":[
 {"name":"clk","wave":"p.........."},
 {"name":"m0_req","wave":"01......0.."},
 {"name":"m0_gnt","wave":"0.1......0."},
 {"name":"m0_valid","wave":"0..1.0....."},
 {"name":"m0_dout","wave":"x..==x.....","data":["HDR","ALO"]},
 {"name":"s_sel","wave":"=...=..=...","data":["0","2 (S1)","0"]},
 {"name":"s_valid","wave":"0...1.0...."},
 {"name":"s_wdata","wave":"x...==x....","data":["HDR","ALO"]},
 {"name":"s1_rdata","wave":"x.....=....","data":["D"]},
 {"name":"m_ready","wave":"0......10.."},
 {"name":"m_rdata","wave":"x......=...","data":["D"]}
]}
```

**Write** (M0 writes S0)
```json
{"signal":[
 {"name":"clk","wave":"p..........."},
 {"name":"m0_req","wave":"01.......0.."},
 {"name":"m0_gnt","wave":"0.1.......0."},
 {"name":"m0_valid","wave":"0..1..0....."},
 {"name":"m0_dout","wave":"x..===x.....","data":["HDR","ALO","DATA"]},
 {"name":"s_sel","wave":"=...=...=...","data":["0","1 (S0)","0"]},
 {"name":"s_valid","wave":"0...1..0...."},
 {"name":"s_wdata","wave":"x...===x....","data":["HDR","ALO","DATA"]},
 {"name":"mem write","wave":"0.....10...."},
 {"name":"m_ready","wave":"0.......10.."}
]}
```

**Two simultaneous requests** (both masters read; M0 has priority)
```json
{"signal":[
 {"name":"clk","wave":"p..............."},
 {"name":"m0_req","wave":"01......0......."},
 {"name":"m1_req","wave":"01.............0"},
 {"name":"m0_gnt","wave":"0.1......0......"},
 {"name":"m1_gnt","wave":"0........1......"},
 {"name":"m_ready","wave":"0......10.....10"},
 {"name":"bus owner","wave":"=.=......=......","data":["idle","M0","M1"]}
]}
```

## 4. Two-board implementation

**Board A** (`de0_bus_board`): the bus. It divides CLOCK_50 to a 1 MHz bus clock
(SW[0]=1 gives 4 Hz, slow enough to watch each beat on the LEDs/HEX) and sends the
**inverted** clock plus reset to Board B. Clocking Board B on the opposite phase
gives half a period of setup and hold margin across the cable in both directions;
the RTL on both boards is still posedge. `tb_top` is run in both phasings and passes.

**Board B** (`de0_node_board`): both masters and the three slaves.

**Wiring:** GPIO0↔GPIO0 and GPIO1↔GPIO1 with straight 40-pin ribbon cables (this
also joins the grounds). The CLKIN pins are input-only on both ends, so they are
unused; that leaves 34 usable pins per header, 68 total, and the design uses all 68.

| Pins | Signal | Direction |
|---|---|---|
| GPIO0_D[7:0] | s_wdata | A→B |
| GPIO0_D[8] | s_valid | A→B |
| GPIO0_D[10:9] | s_sel | A→B |
| GPIO0_D[18:11] | m_rdata | A→B |
| GPIO0_D[19] | m_ready | A→B |
| GPIO0_D[20] / [21] | m0_gnt / m1_gnt | A→B |
| GPIO0_D[22] | node clock (~bus_clk) | A→B |
| GPIO0_D[23] | rst_n | A→B |
| GPIO0_D[31:24] | s0_rdata | B→A |
| GPIO0_CLKOUT[0] / [1] | m0_req / m1_req | B→A |
| GPIO1_D[7:0] | m0_dout | B→A |
| GPIO1_D[8] | m0_valid | B→A |
| GPIO1_D[16:9] | m1_dout | B→A |
| GPIO1_D[17] | m1_valid | B→A |
| GPIO1_D[25:18] | s1_rdata | B→A |
| GPIO1_D[31:26], GPIO1_CLKOUT[1:0] | s2_rdata[5:0], [7:6] | B→A |

Port names follow the DE0 System Builder, so its `.qsf` provides the pin locations.
Check them against your own `.qsf` before compiling.

**Quartus:** make two projects (Cyclone III EP3C16F484C6). Project A: `rtl/*.v`,
`fpga/de0_bus_board.v`, `fpga/reset_sync.v`, `fpga/seg7.v`, top = `de0_bus_board`.
Project B: the same files with `fpga/de0_node_board.v`, top = `de0_node_board`.

## 5. Demo procedure (Board B controls)

| Control | Function |
|---|---|
| SW[9] | 1 = write, 0 = read |
| SW[8:7] | 00 S0, 01 S1, 10 S2, 11 unmapped |
| SW[6:0] | address offset and write data (M0 writes {0,SW}, M1 writes {1,SW}) |
| BUTTON[0] / [1] / [2] | start M0 / start M1 / start both together |
| HEX1:0, HEX3:2 | M0 / M1 last read data |

1. **Reset:** press BUTTON[0] on Board A; all grant/req LEDs go off.
2. **Idle:** no button pressed, no LED activity (watch in 4 Hz mode).
3. **One master:** SW[9]=1, SW[8:7]=01, SW[6:0]=0x2A, press B0 (write). Set SW[9]=0, press B0 → HEX1:0 shows **2A**.
4. **Two masters:** SW[9]=1, press B2 (both write the same address). Set SW[9]=0, press B0 → shows **AA**, because M0 (priority) wrote first and M1 overwrote it. In 4 Hz mode, LEDG on Board A shows gnt0 then gnt1.
5. **Unmapped:** SW[8:7]=11, read → **EE** and Board A's dec_err LED lights.

## 6. Simulation

**ModelSim-Altera / Questa:** open ModelSim, `cd` to the `sim/` folder in the Transcript window, then run `do sim_arbiter.do`, `do sim_decoder.do` or `do sim_top.do`. Each script compiles, loads the testbench, adds grouped waveforms and runs to the PASSED/FAILED message.

**Icarus Verilog:**

```
iverilog -g2005 -o arb  rtl/*.v tb/tb_arbiter.v      && vvp arb
iverilog -g2005 -o dec  rtl/*.v tb/tb_addr_decoder.v && vvp dec
iverilog -g2005 -o top  rtl/*.v tb/tb_top.v          && vvp top
iverilog -g2005 -P tb_top.NODE_CLK_INV=1 -o topi rtl/*.v tb/tb_top.v && vvp topi
iverilog -g2005 -o two  rtl/*.v fpga/*.v tb/tb_two_boards.v && vvp two
```
All testbenches are self-checking (they print PASSED/FAILED) and dump VCD files for
GTKWave. They also run in ModelSim/Questa (`vlog` + `vsim`).

| Testbench | Covers |
|---|---|
| tb_arbiter | idle, single request (M0, M1), two simultaneous requests, no preemption, async reset; checks that both grants are never high together |
| tb_addr_decoder | boundary table and an exhaustive check of all 16384 addresses against a reference model |
| tb_top | (a) reset incl. async reset mid-transfer, (b) idle, (c) one master: every slave's first/last byte, no aliasing, unmapped read/write, (d) two masters: simultaneous, same-address ordering, no preemption |
| tb_two_boards | both DE0 wrappers wired back to back through the GPIO mapping |
