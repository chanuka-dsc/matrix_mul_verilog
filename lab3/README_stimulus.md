# Lab 3 – Person A (Dipon): `stimulus.sv` explained

This is **my half** of the Lab 3 testbench ("what we test"): the random input matrices,
the expected result, and the result check. It is written so that **your `class tb` only has to
call a few functions** – this class never touches a DUT signal or the clock.

Everything here was compiled and run in **Vivado 2025.2** (xvlog / xelab / xsim / xcrg).

---

## 1. Files in this folder

| File | What it is |
|---|---|
| `stimulus.sv` | **The class you use.** Random matrices + constraints, reference model, checker, coverage |
| `stim_test.sv` | Stand-alone self-test of the class (no DUT). Proves every function works |
| `run_stim.tcl` | One command to compile + run `stim_test` and build the coverage HTML report |
| `xcrg_report/` | The functional-coverage report from the last run (open `functionalCoverageReport/dashboard.html`) |
| `README_stimulus.md` | This file |

**Run the self-test yourself** – in the Vivado Tcl console:
```
source {<path to this lab3 folder>/run_stim.tcl}
```
It ends with `ALL STEPS DONE`. The only `Error:` lines are the **two that are expected** in STEP 4b
(we feed a wrong result on purpose to prove the checker catches it).

---

## 2. How you use it from `class tb` (the contract)

```systemverilog
stimulus     stim;
logic [31:0] R_hw[];        // MUST be logic, not bit (see 4.5)
int          errors;

stim = new(2**DIM_LOG);                                         // dim = matrix side, e.g. 4 for 4x4
assert (stim.randomize()) else $fatal(1, "randomize failed");   // picks a mode + fills A and B
stim.compute_ref();                                             // R_expected = A x B
send(stim.A, stim.B);           // YOUR task: stream A (sel=0) then B (sel=1)
receive(R_hw);                  // YOUR task: R_hw = new[stim.size]; fill it word by word
errors = stim.check(R_hw);      // MY function: immediate assertions, returns #wrong elements
```

Call these in a loop (`repeat (N)`) with **one** `stim` object – a new mode is picked every time.

What the class gives you:

| Member | Type | Meaning |
|---|---|---|
| `dim`, `size` | `int unsigned` | matrix side and `dim*dim` |
| `mode` | `randc gen_mode_t` | `SMALL`, `EDGE` or `FULL` (enum) |
| `A[]`, `B[]` | `rand bit [31:0]` dynamic arrays | inputs, **row-major**: element (row,col) = `A[row*dim + col]` – same order the DUT expects on the stream |
| `R_expected[]` | `bit [31:0]` dynamic array | expected result, row-major (same order the DUT sends R) |
| `compute_ref()` | function | fills `R_expected` |
| `check(R_hw)` | function returning `int` | 0 = all correct |
| `display()` | function | prints mode, A, B, R (for debugging) |

### Changes compared with `TEAM_PLAN.md`
1. **`check()` takes `logic [31:0] R_hw[]`, not `bit`.** A `bit` array silently turns X into 0,
   so we could never catch X from the hardware. Please declare your receive array as `logic`.
2. The modes are exactly the plan's `SMALL`, `EDGE`, `FULL` (no `SPARSE`).
3. Coverage is sampled **automatically** inside the class (`post_randomize`) – you don't call anything.

### Adding it to your Vivado project
- Add `stimulus.sv` as a **Simulation Source**, file type **SystemVerilog**.
- `stimulus.sv` must be compiled **before** `tb_top.sv` (the class and the enum `gen_mode_t`
  live in the compilation-unit scope). Check *Sources → Compile Order* and move it above `tb_top.sv`
  if needed.

---

## 3. What each part does (in the order it was built)

### Step 1 – class skeleton
- Fields exactly as in the plan's contract.
- `new(dim)` sets `size = dim*dim` and allocates every array with `new[size]`.
- **Constraint `c_size`**: `A.size() == size; B.size() == size;` – `randomize()` is allowed to change
  the *length* of a `rand` dynamic array, so we pin it; otherwise the solver could return an empty matrix.

### Step 2 – constraint groups (Lab 3 task 3: "motivate the rules to the TA")

| Mode | Rule | Why |
|---|---|---|
| `SMALL` | every element `< 16` | results stay small → easy to check by hand in the waveform when debugging |
| `EDGE` | every element is one of `0, 1, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF` | 0/1 = zero and identity cases; `7FFF_FFFF`/`8000_0000` = around the sign bit; `FFFF_FFFF` = max. Products/sums overflow 32 bits → tests that HW keeps exactly the low 32 bits like the reference |
| `FULL` | no rule | "as random as possible" (what the handout asks for): any 32-bit value |

Each rule is an **implication**: `(mode == SMALL) -> (A[i] < 16)` – if the mode is not SMALL the rule is ignored.

**`rand` vs `randc`** (lecture Verification II, slides 7–8):
- `rand` = new random value every `randomize()`, repeats allowed → used for the matrix data.
- `randc` = *random-cyclic*: goes through **all** values once (random order) before repeating →
  used for `mode`, so every 3 jobs we get SMALL, EDGE and FULL exactly once.
- `randc` variables are solved **before** `rand` ones: the solver first picks the mode, then fills A/B
  under that mode's rule.

### Two Vivado 2025.2 problems we hit (the TA may ask why the code differs from the lecture)
1. **The lecture style crashes the elaborator.**
   `mode == SMALL -> { foreach (A[i]) A[i] < 16; }` → `xelab` crashes with
   `EXCEPTION_ACCESS_VIOLATION`, and `inside {...}` on array elements gives "Unsupported construct".
   We tested 6 variants; the working form is `foreach` **outside**, implication per element:
   ```systemverilog
   foreach (A[i]) (mode == SMALL) -> (A[i] < 16);
   ```
   Same meaning. **If you write constraints yourself, use this form.**
2. **EDGE was biased – found by the coverage report.** First version:
   `(mode == EDGE) -> (A[i] == 0 || A[i] == 1 || ...)`. Legal, but the coverage report showed
   0 hits for `0x7FFF_FFFF` and `0x8000_0000`: the solver always picked `0xFFFF_FFFF`.
   **Fix:** each element gets a random *index* `edge_idx_A[i]` (constrained `< 5`) and
   `post_randomize()` copies `EDGE_VALS[index]` into `A[i]`. Now all 5 corner values appear
   (≈ 45–80 hits each). Good demo point: *coverage showed the stimulus wasn't doing what we intended,
   even though the constraint was obeyed.*

### Step 2b – functional coverage (Lab 3 task 5, my part)
```systemverilog
covergroup cov_grp;
    cp_mode : coverpoint mode;      // 3 auto bins: SMALL, EDGE, FULL
    cp_val  : coverpoint cov_val {  // 8 value-range bins
        v_zero, v_one, v_small(2..15), v_mid(0x10..0x7FFF_FFFE), v_max_pos(0x7FFF_FFFF),
        v_sign_bit(0x8000_0000), v_high(0x8000_0001..0xFFFF_FFFE), v_all_ones(0xFFFF_FFFF) }
endgroup
```
- Created in `new()` (`cov_grp = new();`) – required for a covergroup inside a class (like the lecture's
  `random_memory_loader`).
- `post_randomize()` is called **automatically** after every successful `randomize()`; it samples every
  element of A and B. Your code does nothing extra.
- Bin names start with `v_` because `small` is a reserved Verilog keyword.
- Result: **100 %** (all 3 modes, all 8 value ranges). Small observation: in FULL mode ~75 % of values land
  in `v_high` (expected ~50 %) – Vivado's solver favours values with the top bit set; the full range is
  still covered.

**The HTML report (`xcrg`)** – same command you need for the FSM coverage:
```
xcrg -report_format html -dir <sim folder>/xsim.covdb -report_dir <where you want the report>
```
xsim writes the coverage counts into `xsim.covdb` next to the simulation; `xcrg` turns them into
`dashboard.html`, `groups.html`, `grp0.html` (details per covergroup). Without `-report_dir` it lands in
Vivado's working folder (`AppData\Roaming\Xilinx\Vivado\xcrg_report`), like in the lecture.
In the project flow the database is under
`<project>.sim/sim_1/behav/xsim/xsim.covdb`.

### Step 3 – `compute_ref()` (reference model)
The triple loop from the Lab 2 testbench: `R[row][col] = Σ_k A[row][k] · B[k][col]`.
The accumulator is `bit [31:0]`, so every product and sum keeps only its **low 32 bits** –
exactly like the 32-bit MAC in hardware. That's why overflowing EDGE values give the same answer in SW and HW.

### Step 4 – `check(R_hw)` (immediate assertions, Lab 3 "assertions")
For every element, two **immediate assertions** (lecture Verification II, slides 11–12):
```systemverilog
assert (!$isunknown(R_hw[i]))          else $error("R[r][c] is unknown ...");   // no X / Z
assert (R_hw[i] == R_expected[i])      else $error("R[r][c] mismatch: expected=.. got=..");
```
- Also asserts that `R_hw.size() == size` (right number of words received).
- Prints `CHECK PASS: ...` or `CHECK FAIL: ... N of M elements wrong`, returns N.
- Note: Vivado reports the file of these errors as `stim_test.sv` with a wrong line number; the
  `Scope: ...stimulus::check` part is the correct location.

### Step 5 – `display()`
Prints mode, A, B and R_expected (decimal for SMALL, hex otherwise). Handy when a check fails.

---

## 4. Self-test results (`stim_test.sv`, Vivado 2025.2, 2x2)

```
STEP 2: mode sequence (randc): EDGE FULL SMALL EDGE FULL SMALL FULL SMALL EDGE ...
        SMALL picked 10 times / EDGE 10 / FULL 10
        stimulus coverage: 100.0 %
STEP 3a: [1 2;3 4] x [5 6;7 8] = [19 22; 43 50]          (hand-calculated)
STEP 3b: wrap-around -> [00000001 80000000; 00000002 00000001]
         (FFFFFFFF*FFFFFFFF = 1 and 80000000*2 = 0 mod 2^32)
STEP 4a: correct R_hw  -> CHECK PASS, check() returned 0
STEP 4b: wrong value + X on purpose -> both assertions fire, check() returned 2 (expected 2)
STEP 5:  display() of a SMALL and an EDGE job
ALL STEPS DONE
```

After every `randomize()` the test also uses immediate assertions to confirm the values obey the
chosen mode's rule (SMALL < 16, EDGE in the 5-value set) – none fired in 30 jobs.

---

## 5. Questions the TA may ask about this half (short answers)

- **Why these three modes?** SMALL = debuggable, EDGE = corner/overflow cases, FULL = as random as possible.
- **rand vs randc?** randc cycles through all values before repeating → every mode is guaranteed to be used.
- **Why an index table for EDGE?** The OR-list was legal but biased (only `FFFF_FFFF`); coverage showed it.
- **Why is `R_hw` logic?** 2-state `bit` hides X; we want to catch X from the hardware.
- **Why does the reference match the hardware with overflow?** Both keep only the low 32 bits.
- **Immediate vs concurrent assertion?** Immediate = checks a condition *now* (like an `if` that reports
  an error) – used in `check()`. Concurrent (`assert property`) = checks behaviour *over clock cycles* –
  your AXI timing checks.
- **What does functional coverage tell us?** Which modes and value ranges were really generated; it
  cannot find features that were never implemented (lecture slide 30).
