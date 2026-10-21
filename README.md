# maxtrix_mul_verilog – FINAL VERSION (Lab 2 + Lab 3)

| Folder / file | What |
|---|---|
| `src/hdl/mat_mul.v` | **Lab 2 design**: matrix multiplier with the **5-state AGU** of the lab manual (S_IDLE, S_LOAD_A, S_LOAD_B, S_CALCULATE, S_OUTPUT) |
| `src/hdl/mat_mul_tb.v` | **Lab 2 testbench** (course file) with the 3 race fixes: lines 115, 125, 126 use `<=` |
| `lab3/stimulus.sv` | **Lab 3** Person A (Dipon): random matrices (rand/randc + constraints), reference model, `check()`, stimulus coverage |
| `lab3/tb_top.sv` | **Lab 3** top: `class tb` + AXI send/receive (Chanuka), concurrent assertions (Chanuka), FSM coverage (Dipon) |
| `lab3/stim_test.sv` | stand-alone self-test of `stimulus.sv` |
| `lab3/README_*.md` | explanations: `README_stimulus.md`, `README_tb_top.md`, `README_fsm.md` |

**How to run** (Vivado 2025.2 Tcl console, no project needed):
```
source {<repo>/lab3/run_lab2_tb.tcl}   ;# Lab 2: course testbench, 64x64 -> "HW/SW result match!"
source {<repo>/lab3/run_tb.tcl}        ;# Lab 3: tb_top (3 jobs) + coverage report lab3/xcrg_tb_report/
source {<repo>/lab3/run_stim.tcl}      ;# Lab 3: stimulus.sv self-test + report lab3/xcrg_report/
```

---

# maxtrix_mul_verilog
