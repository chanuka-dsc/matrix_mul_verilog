# Lab 3 – `tb_top.sv` (Person B: Chanuka)

Object-oriented testbench for the matrix multiplier (`src/hdl/mat_mul.v`), using Dipu's
`stimulus.sv` (Person A). See `lab_3/TEAM_PLAN.md` for the split and the contract.

## What it does
`module tb_top` = 20 ns clock, active-low reset, the DUT (`dut`), and `class tb`:

| Lab 3 step | `class tb` member | What it does |
|---|---|---|
| 1. Matrix initialization | `init()` | `stim.randomize()` (immediate assertion `$fatal` if it fails) |
| 2. Reference result | `compute()` | `stim.compute_ref()`, then `stim.display()` prints A, B, R |
| 3. Feed the DUT | `send_word()`, `send()` | AXI-Stream master on `s00_axis_*`: matrix A (`sel=0`), then B (`sel=1`), `tlast` on the last word. Race-free: inputs change only with `<=` after `@(posedge clk)`; a word is taken on the edge where `s00_axis_tready` was 1 |
| 4. Start, collect, compare | `run_and_check()` | 1-cycle `start` pulse; receives on `m00_axis_*` with **random `m00_axis_tready` (~70 %, back-pressure)**; immediate assertion that `SIZE` words arrived; `stim.check(R_hw)`; prints `Test Pass/Fail` |

The script runs the 4 steps **3 times back-to-back without reset** (`randc` → EDGE, FULL, SMALL once each).
Matrix size: `localparam int DIM_LOG` at the top (2 = 4x4 for debugging, 6 = 64x64 for the final run).

## Still to do
- STEP 5 – concurrent assertions on the output AXI-Stream (Chanuka).
- STEP 6 – FSM transition covergroup on `dut.agu_inst.current_state` + `xcrg` report (Dipu).
  The skeleton comments for STEP 6 are already in `tb_top.sv`.

## Vivado project setup (important)
1. Add `src/hdl/mat_mul.v`, `lab3/stimulus.sv` and `lab3/tb_top.sv`; set `tb_top` as simulation top.
2. **Compile order:** `stimulus.sv` must come **before** `tb_top.sv`
   (Sources → Compile Order → Simulation → right-click → Hierarchy Update →
   "No Update, Manual Compile Order", then drag `stimulus.sv` up). Otherwise:
   `'randomize' is not declared under prefix 'stim'`.
3. **Vivado 2025.2 compiler hang:** with the default `--debug typical`, `xelab` hangs forever on the
   `c_small` constraint in `stimulus.sv`. Use `--debug wave` instead (waveforms still work).
   In the Tcl console, once per project:
   ```tcl
   set_property -name {xsim.elaborate.debug_level} -value {off} -objects [get_filesets sim_1]
   set_property -name {xsim.elaborate.xelab.more_options} -value {-debug wave} -objects [get_filesets sim_1]
   ```
4. Run Behavioral Simulation, then `run all` (the default first run stops at 1000 ns).

Expected output (4x4): three blocks `stimulus: mode=...` with A, B, R, each followed by
`CHECK PASS: ... all 16 elements match` and `Test Pass`, then `tb_top: all runs finished` at 7690 ns.
