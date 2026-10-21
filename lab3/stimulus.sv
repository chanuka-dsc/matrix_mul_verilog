`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// stimulus.sv  -  Lab 3, Person A (Dipon): stimulus & checking
//
// One stimulus object = one test job for the matrix multiplier:
//   - random input matrices A and B          (rand / randc + constraint groups)
//   - the expected result R_expected = A x B (software reference model)
//   - check(): compares the hardware result with immediate assertions
// This class never touches a DUT signal; class tb (Person B) creates it and
// calls its functions.
// Matrices are stored row-major: element (row, col) is X[row*dim + col].
//////////////////////////////////////////////////////////////////////////////////

// Test scenarios. Each mode has its own constraint group (added in step 2).
typedef enum {SMALL, EDGE, FULL} gen_mode_t;

class stimulus;

    int unsigned dim;          // matrix side, e.g. 4 for a 4x4 matrix
    int unsigned size;         // number of elements = dim*dim

    randc gen_mode_t mode;     // randc: goes through every mode once before repeating
    rand  bit [31:0] A[];      // input matrix A (row-major)
    rand  bit [31:0] B[];      // input matrix B (row-major)
    bit   [31:0] R_expected[]; // reference result, filled by compute_ref()

    // ---------------------------------------------------------------------
    // STEP 1: size constraint
    // Why: A and B are dynamic arrays. randomize() is allowed to change the
    // size of a rand dynamic array, so we pin it to dim*dim. Otherwise the
    // solver could return an empty or wrong-sized matrix.
    // ---------------------------------------------------------------------
    constraint c_size {
        A.size() == size;
        B.size() == size;
    }

    // Constructor: remember the size and allocate the three arrays
    function new(int unsigned dim);
        this.dim   = dim;
        this.size  = dim * dim;
        A          = new[size];
        B          = new[size];
        R_expected = new[size];
        edge_idx_A = new[size];
        edge_idx_B = new[size];
        cov_grp    = new();      // a covergroup inside a class must be created in new()
    endfunction

    // ---------------------------------------------------------------------
    // STEP 2: constraint groups, one per mode
    // Each rule is an implication: "(mode == X) -> rule". If the mode is not X
    // the implication is true and the rule is ignored.
    // randc variables (mode) are solved BEFORE rand variables, so the solver
    // first picks the mode, then fills A and B under that mode's rule.
    //
    // NOTE (Vivado 2025.2 simulator): the lecture style
    //     mode == SMALL -> { foreach (A[i]) A[i] < 16; }
    // crashes xelab (EXCEPTION_ACCESS_VIOLATION), and "inside {...}" on array
    // elements is reported as "Unsupported construct". The equivalent form
    // below (foreach outside, implication per element, || instead of inside)
    // means exactly the same and works.
    // ---------------------------------------------------------------------

    // SMALL: every element < 16.
    // Why: results stay small (at most 15*15*dim), so a wrong element is easy
    // to spot by hand in the waveform or the printout while debugging.
    constraint c_small {
        foreach (A[i]) (mode == SMALL) -> (A[i] < 16);
        foreach (B[i]) (mode == SMALL) -> (B[i] < 16);
    }

    // EDGE: every element is one of the corner values 0, 1, 0x7FFF_FFFF,
    // 0x8000_0000, 0xFFFF_FFFF.
    // Why: 0 and 1 test the zero / identity cases; 0x7FFF_FFFF and 0x8000_0000
    // sit on the sign-bit border; 0xFFFF_FFFF is the largest value. Products and
    // sums of these overflow 32 bits, so this checks that the hardware keeps
    // exactly the low 32 bits (wrap-around) like the reference model.
    // How: each element gets a random INDEX 0..4 into the table EDGE_VALS;
    // post_randomize() copies the chosen corner value into A / B.
    // (Writing "A[i] == 0 || A[i] == 1 || ..." directly is legal, but the
    // Vivado solver then always picked 0xFFFF_FFFF - the coverage report
    // showed it. A small index range is spread evenly over all 5 values.)
    localparam int N_EDGE = 5;
    const bit [31:0] EDGE_VALS [N_EDGE] = '{32'h0, 32'h1, 32'h7FFF_FFFF, 32'h8000_0000, 32'hFFFF_FFFF};
    rand bit [2:0] edge_idx_A[];
    rand bit [2:0] edge_idx_B[];

    constraint c_edge {
        edge_idx_A.size() == size;
        edge_idx_B.size() == size;
        foreach (edge_idx_A[i]) edge_idx_A[i] < N_EDGE;
        foreach (edge_idx_B[i]) edge_idx_B[i] < N_EDGE;
    }

    // FULL: no value constraint at all.
    // Why: the handout asks to test "as random as possible"; every 32-bit
    // value is allowed (uniform), which finds bugs we did not think of.
    // (No constraint block needed: only c_size applies in FULL mode.)

    // ---------------------------------------------------------------------
    // STEP 2b: functional coverage of the generated stimulus (Lab 3 task 5)
    // Shows that the constraints really produce every mode and every value
    // range. Sampled once per matrix element after each randomize().
    // Report: xcrg -> dashboard.html
    // ---------------------------------------------------------------------
    bit [31:0] cov_val;        // the element currently being sampled

    covergroup cov_grp;
        cp_mode : coverpoint mode;                      // one bin per mode
        cp_val  : coverpoint cov_val {
            bins v_zero     = {32'h0};
            bins v_one      = {32'h1};
            bins v_small    = {[32'h2 : 32'hF]};
            bins v_mid      = {[32'h10 : 32'h7FFF_FFFE]};
            bins v_max_pos  = {32'h7FFF_FFFF};            // largest positive (signed)
            bins v_sign_bit = {32'h8000_0000};            // smallest negative (signed)
            bins v_high     = {[32'h8000_0001 : 32'hFFFF_FFFE]};
            bins v_all_ones = {32'hFFFF_FFFF};
        }
    endgroup

    // post_randomize() is called automatically right after a successful randomize():
    // it finishes the EDGE values and samples the coverage of the new matrices
    function void post_randomize();
        if (mode == EDGE) begin                        // EDGE: index -> corner value
            foreach (A[i]) A[i] = EDGE_VALS[edge_idx_A[i]];
            foreach (B[i]) B[i] = EDGE_VALS[edge_idx_B[i]];
        end
        foreach (A[i]) begin cov_val = A[i]; cov_grp.sample(); end
        foreach (B[i]) begin cov_val = B[i]; cov_grp.sample(); end
    endfunction

    // ---------------------------------------------------------------------
    // STEP 3: reference model  R_expected = A x B
    // Same triple loop as the Lab 2 testbench. acc is bit [31:0], so every
    // product and sum keeps only its low 32 bits - exactly what the hardware
    // MAC does (its registers are 32 bits wide). This is why EDGE values that
    // overflow still give the same answer in software and hardware.
    // ---------------------------------------------------------------------
    function void compute_ref();
        bit [31:0] acc;
        for (int row = 0; row < dim; row++)
            for (int col = 0; col < dim; col++) begin
                acc = 0;
                for (int k = 0; k < dim; k++)
                    acc += A[row*dim + k] * B[k*dim + col];
                R_expected[row*dim + col] = acc;
            end
    endfunction

    // ---------------------------------------------------------------------
    // STEP 4: compare the hardware result with IMMEDIATE assertions
    // R_hw is logic (4-state), not bit: a bit array would silently turn an
    // X or Z coming from the hardware into 0, and the X check could never fire.
    // Returns the number of wrong elements (0 = pass).
    // ---------------------------------------------------------------------
    function int check(logic [31:0] R_hw[]);
        int errors = 0;
        assert (R_hw.size() == size)
            else begin
                $error("check: got %0d result words, expected %0d", R_hw.size(), size);
                return size;
            end
        foreach (R_expected[i]) begin
            // 1) no X / Z in the hardware result
            assert (!$isunknown(R_hw[i]))
                else begin
                    errors++;
                    $error("R[%0d][%0d] is unknown: hw=%h", i/dim, i%dim, R_hw[i]);
                end
            // 2) value must equal the reference
            if (!$isunknown(R_hw[i]))
                assert (R_hw[i] == R_expected[i])
                    else begin
                        errors++;
                        $error("R[%0d][%0d] mismatch: expected=%h got=%h", i/dim, i%dim, R_expected[i], R_hw[i]);
                    end
        end
        if (errors == 0)
            $display("CHECK PASS: mode=%s %0dx%0d, all %0d elements match", mode.name(), dim, dim, size);
        else
            $display("CHECK FAIL: mode=%s %0dx%0d, %0d of %0d elements wrong", mode.name(), dim, dim, errors, size);
        return errors;
    endfunction

    // ---------------------------------------------------------------------
    // STEP 5: print the job (debug). SMALL in decimal, other modes in hex.
    // ---------------------------------------------------------------------
    function void print_matrix(string name, bit [31:0] m[]);
        string line;
        for (int row = 0; row < dim; row++) begin
            line = (row == 0) ? $sformatf("  %s =", name) : "     ";
            for (int col = 0; col < dim; col++)
                line = {line, (mode == SMALL) ? $sformatf(" %5d", m[row*dim + col])
                                              : $sformatf(" %h", m[row*dim + col])};
            $display("%s", line);
        end
    endfunction

    function void display();
        $display("stimulus: mode=%s, %0dx%0d", mode.name(), dim, dim);
        print_matrix("A", A);
        print_matrix("B", B);
        print_matrix("R", R_expected);
    endfunction

endclass : stimulus
