# Lab 3 – STEP 6: FSM coverage (Dipon)

Lab 3 task 5: *"report the FSM or functional coverage of your matrix multiplier. Are there any
unreachable FSM state(s) or state(s) that goes wrong with the FSM state transition graph? Are there
any state(s) that is holding with not enough cycles?"*

Everything is in `tb_top.sv`, section **STEP 6**. Verified in **Vivado 2025.2** (4x4).

## How to run
Vivado Tcl console (no project needed):
```
source {<path to this lab3 folder>/run_tb.tcl}
```
`run_tb.tcl` compiles `../src/hdl/mat_mul.v`, then `stimulus.sv` **before** `tb_top.sv`, elaborates
**without** `--debug typical` (that option makes `xelab` hang on the `c_small` constraint – see
`README_tb_top.md`), runs, and writes the coverage report to
`xcrg_tb_report/functionalCoverageReport/dashboard.html` (all three covergroups: stimulus + FSM).

## The AGU state diagram (design on `main`, 6 one-hot states)
```
IDLE --tvalid,sel=0--> LOAD_A --tlast accepted--> IDLE
IDLE --tvalid,sel=1--> LOAD_B --tlast accepted--> IDLE
IDLE --start--> CALC --(DIM^3 cycles)--> WAIT --(3 cycles)--> OUT --last word accepted--> IDLE
```

## What we cover

### 1. `covergroup cov_fsm @(posedge clk)` on `dut.agu_inst.current_state` (lecture slide 37 style)
| Coverpoint | Bins | Answers |
|---|---|---|
| `cp_state` | one bin per state: idle, load_a, load_b, calc, wait_s, out | *unreachable states?* |
| `cp_trans` | the 8 legal transitions (IDLE→LOAD_A, LOAD_A→IDLE, IDLE→LOAD_B, LOAD_B→IDLE, IDLE→CALC, CALC→WAIT, WAIT→OUT, OUT→IDLE) | *does the FSM follow its diagram?* |
| `cp_never` | 7 transitions that must **never** happen (LOAD_A→CALC, LOAD_A→LOAD_B, CALC→IDLE, CALC→OUT, WAIT→IDLE, OUT→CALC, IDLE→OUT). `option.weight = 0` so they don't count in the score | *wrong transitions?* – the report shows 0 hits each |

(`wait` is a SystemVerilog keyword, hence the bin name `wait_s`.)

### 2. `covergroup cov_hold` + immediate assertions: how many cycles each state is held
An `always @(posedge clk)` block counts the cycles spent in the current state. When the state
changes it (a) samples `cov_hold` with the length, (b) checks it with an **immediate assertion**,
(c) prints `FSM: <state> held N cycles`.

| State | Expected length | Why | Bin / assertion |
|---|---|---|---|
| LOAD_A / LOAD_B | `SIZE` (16 at 4x4) | one word per cycle, our sender has no gaps | bin `exactly_SIZE`; assert `>= SIZE` |
| CALC | `DIM^3` (64 at 4x4) | one cycle per (row, col, temp) address | bin `exactly_DIM3`; assert `== DIM^3` |
| WAIT | 3 | 2-cycle pipeline (BRAM read + MAC input register) drain, then R[0] pre-fetch | bin `exactly_3`; assert `== 3` |
| OUT | `> SIZE` | random `m00_axis_tready` (back-pressure) adds cycles | bin `stalled`; assert `>= SIZE` |

**Why not the lecture's repetition bins** like `(S_CALC[*64] => S_WAIT)`? We tried: in Vivado 2025.2
any `[*N]` inside a transition bin either kills the simulator kernel (`FATAL_ERROR` when the covergroup
is created) or gives `Error: Encountered wrong state type while Populating tbin`. Plain transition bins
work. We bisected this with 8 variants of the covergroup (states / transitions / each repetition bin /
never-bins with and without weight) – only the `[*N]` bins fail. Counting in the testbench gives the
same information and also lets us *assert* the exact length.

## Results (Vivado 2025.2, 4x4, 3 jobs back-to-back: SMALL, EDGE, FULL)
```
FSM: LOAD_A held 16 cycles      FSM: CALC held 64 cycles
FSM: LOAD_B held 16 cycles      FSM: WAIT held 3 cycles
FSM:    OUT held 26 cycles / 20 cycles   (back-pressure)
CHECK PASS (x3), Test Pass (x3)
FSM coverage (cov_fsm, states + transitions): 100.0 %
FSM coverage (cov_hold, cycles per state)   : 100.0 %
```
Report hit counts: idle 22, load_a 48, load_b 48, calc 192 (= 3 x 64), wait_s 9 (= 3 x 3), out 68;
each legal transition 3 (out_to_idle 2: the simulation ends during the 3rd OUT); **all 7 never-bins: 0**.

## Answers to the handout's questions
- **Unreachable states?** No – all 6 states are reached. Only the unused one-hot codes of the 6-bit
  state register (58 of 64 values) can never occur; the `default` branch of the FSM is unreachable.
- **Wrong transitions?** No – only the 8 legal transitions occur; the 7 illegal ones have 0 hits.
- **States held with not enough cycles?** No – CALC lasts exactly DIM^3, WAIT exactly 3 (enough for the
  2-cycle pipeline before OUT reads R[0]), LOAD exactly SIZE, OUT at least SIZE. All assertions passed.
  (In the original Lab 2 AGU the pipeline wait was one cycle off – that's the bug fixed in Lab 2.)
