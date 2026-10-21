# Lab 3 – FSM coverage (Dipon)

Lab 3 task 5: *"report the FSM or functional coverage of your matrix multiplier. Are there any
unreachable FSM state(s) or state(s) that goes wrong with the FSM state transition graph? Are there
any state(s) that is holding with not enough cycles?"*

Everything is in `tb_top.sv`, section **FSM coverage**. Verified in **Vivado 2025.2**.

## How to run
Vivado Tcl console (no project needed):
```
source {<path to this lab3 folder>/run_tb.tcl}
```
`run_tb.tcl` compiles `../src/hdl/mat_mul.v`, then `stimulus.sv` **before** `tb_top.sv`, elaborates
**without** `--debug typical` (that option makes `xelab` hang on the `c_small` constraint – see
`README_tb_top.md`), runs, and writes the coverage report to
`xcrg_tb_report/functionalCoverageReport/dashboard.html` (all three covergroups: stimulus + FSM).

## The AGU state diagram (final design, the 5 states of the Lab 2 manual, one-hot)
```
S_IDLE --tvalid,sel=0--> S_LOAD_A --word with tlast accepted--> S_IDLE
S_IDLE --tvalid,sel=1--> S_LOAD_B --word with tlast accepted--> S_IDLE
S_IDLE --start--> S_CALCULATE --(DIM^3 + 3 cycles)--> S_OUTPUT --last word accepted--> S_IDLE
```
S_CALCULATE = DIM^3 address cycles (one per row, col, temp) + 3 drain cycles: the last sum needs
2 more cycles to come out of the pipeline (BRAM read + MAC input register) and be written to matR,
then R[0] is pre-fetched so it is already on `m00_axis_tdata` when S_OUTPUT starts.
(In the testbench the states are called S_IDLE, S_LOAD_A, S_LOAD_B, S_CALC, S_OUT.)

## What we cover

### 1. `covergroup cov_fsm @(posedge clk)` on `dut.agu_inst.current_state` (lecture slide 37 style)
| Coverpoint | Bins | Answers |
|---|---|---|
| `cp_state` | one bin per state: idle, load_a, load_b, calc, out | *unreachable states?* |
| `cp_trans` | the 7 legal transitions (IDLE→LOAD_A, LOAD_A→IDLE, IDLE→LOAD_B, LOAD_B→IDLE, IDLE→CALC, CALC→OUT, OUT→IDLE) | *does the FSM follow its diagram?* |
| `cp_never` | 6 transitions that must **never** happen (LOAD_A→CALC, LOAD_A→LOAD_B, CALC→IDLE, LOAD_B→CALC, OUT→CALC, IDLE→OUT). `option.weight = 0` so they don't count in the score | *wrong transitions?* – the report shows 0 hits each |

### 2. `covergroup cov_hold` + immediate assertions: how many cycles each state is held
An `always @(posedge clk)` block counts the cycles spent in the current state. When the state
changes it (a) samples `cov_hold` with the length, (b) checks it with an **immediate assertion**,
(c) prints `FSM: <state> held N cycles`.

| State | Expected length (4x4) | Why | Bin / assertion |
|---|---|---|---|
| LOAD_A / LOAD_B | `SIZE` = 16 | one word per cycle, our sender has no gaps | bin `exactly_SIZE`; assert `>= SIZE` |
| CALCULATE | `DIM^3 + 3` = 67 | DIM^3 addresses + 3-cycle pipeline drain / R[0] pre-fetch | bin `exactly_DIM3_plus_3`; assert `== DIM^3 + 3` |
| OUTPUT | `> SIZE` | random `m00_axis_tready` (back-pressure) adds cycles | bin `stalled`; assert `>= SIZE` |

**Why not the lecture's repetition bins** like `(S_CALC[*67] => S_OUT)`? We tried: in Vivado 2025.2
any `[*N]` inside a transition bin either kills the simulator kernel (`FATAL_ERROR` when the covergroup
is created) or gives `Error: Encountered wrong state type while Populating tbin`. Plain transition bins
work. We bisected this with 8 variants of the covergroup (states / transitions / each repetition bin /
never-bins with and without weight) – only the `[*N]` bins fail. Counting in the testbench gives the
same information and also lets us *assert* the exact length.

## Results (Vivado 2025.2, 4x4, 3 jobs back-to-back: SMALL, EDGE, FULL)
```
FSM: LOAD_A held 16 cycles      FSM: CALC held 67 cycles   (= 4^3 + 3)
FSM: LOAD_B held 16 cycles      FSM:  OUT held 26 / 20 cycles (back-pressure)
CHECK PASS (x3), Test Pass (x3), no concurrent-assertion failures
FSM coverage (cov_fsm, states + transitions): 100.0 %
FSM coverage (cov_hold, cycles per state)   : 100.0 %
```
Report hit counts (`xcrg_tb_report/`): idle 22, load_a 48, load_b 48, calc 201 (= 3 x 67), out 68;
each legal transition 3 (out_to_idle 2: the simulation ends during the 3rd OUTPUT); **all 6 never-bins: 0**.
The Lab 2 course testbench (`run_lab2_tb.tcl`, 64x64) prints `HW/SW result match!` on the same design.

## Answers to the handout's questions
- **Unreachable states?** No – all 5 states are reached. Only the unused one-hot codes of the 5-bit
  state register (27 of 32 values) can never occur; the `default` branch of the FSM is unreachable.
- **Wrong transitions?** No – only the 7 legal transitions occur; the illegal ones have 0 hits.
- **States held with not enough cycles?** No – S_CALCULATE lasts exactly DIM^3 + 3 (the 3 drain cycles
  are exactly what the 2-stage BRAM+MAC pipeline needs before S_OUTPUT reads R[0]), LOAD exactly SIZE,
  OUTPUT at least SIZE. All assertions pass. (In the original Lab 2 AGU this pipeline timing was one
  cycle off – that bug was fixed in Lab 2.)
