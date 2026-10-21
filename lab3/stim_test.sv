`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// stim_test.sv  -  stand-alone test of class stimulus (no DUT needed)
// Run (Vivado Tcl console): source {<path to lab3 folder>/run_stim.tcl}
//////////////////////////////////////////////////////////////////////////////////
module stim_test;
    stimulus s;
    int unsigned mode_count [gen_mode_t];   // how often each mode was picked
    string seq;
    logic [31:0] R_hw[];                    // plays the role of the hardware result
    int errors;
    bit [31:0] exp_R[4];                    // hand-calculated expected result (2x2)

    initial begin
        // ---------------- STEP 1: construct ----------------
        s = new(2);   // 2x2 matrices; ONE object for the whole test -> one coverage instance
        $display("STEP 1: dim=%0d size=%0d  A.size=%0d B.size=%0d R.size=%0d",
                 s.dim, s.size, s.A.size(), s.B.size(), s.R_expected.size());

        // ---------------- STEP 2: constraint groups ----------------
        // 30 jobs. After every randomize() IMMEDIATE assertions check that the
        // values obey the rule of the chosen mode.
        repeat (30) begin
            assert (s.randomize()) else $fatal(1, "randomize failed");
            mode_count[s.mode]++;
            seq = {seq, s.mode.name(), " "};
            foreach (s.A[i]) begin
                if (s.mode == SMALL)
                    assert (s.A[i] < 16 && s.B[i] < 16)
                        else $error("SMALL violated: A=%0d B=%0d", s.A[i], s.B[i]);
                if (s.mode == EDGE)
                    assert (s.A[i] inside {0, 1, 32'h7FFF_FFFF, 32'h8000_0000, 32'hFFFF_FFFF} &&
                            s.B[i] inside {0, 1, 32'h7FFF_FFFF, 32'h8000_0000, 32'hFFFF_FFFF})
                        else $error("EDGE violated: A=%h B=%h", s.A[i], s.B[i]);
            end
        end
        $display("STEP 2: mode sequence (randc): %s", seq);
        foreach (mode_count[m]) $display("        %-5s picked %0d times", m.name(), mode_count[m]);
        $display("        stimulus coverage: %0.1f %%", s.cov_grp.get_coverage());

        // ---------------- STEP 3: compute_ref() ----------------
        // a) hand-checked example: [1 2; 3 4] x [5 6; 7 8] = [19 22; 43 50]
        s.A = '{1, 2, 3, 4};
        s.B = '{5, 6, 7, 8};
        s.compute_ref();
        exp_R = '{19, 22, 43, 50};
        foreach (exp_R[i])
            assert (s.R_expected[i] == exp_R[i])
                else $error("compute_ref wrong at %0d: got %0d, expected %0d", i, s.R_expected[i], exp_R[i]);
        $display("STEP 3a: [1 2;3 4] x [5 6;7 8] = [%0d %0d; %0d %0d]  (expected [19 22; 43 50])",
                 s.R_expected[0], s.R_expected[1], s.R_expected[2], s.R_expected[3]);
        // b) 32-bit wrap-around: FFFFFFFF*FFFFFFFF = 1 and 80000000*2 = 0 (mod 2^32)
        //    [FFFFFFFF 80000000; 0 1] x [FFFFFFFF 0; 2 1] = [1 80000000; 2 1]
        s.A = '{32'hFFFF_FFFF, 32'h8000_0000, 0, 1};
        s.B = '{32'hFFFF_FFFF, 0, 2, 1};
        s.compute_ref();
        exp_R = '{1, 32'h8000_0000, 2, 1};
        foreach (exp_R[i])
            assert (s.R_expected[i] == exp_R[i])
                else $error("compute_ref wrap-around wrong at %0d: got %h, expected %h", i, s.R_expected[i], exp_R[i]);
        $display("STEP 3b: wrap-around -> [%h %h; %h %h]  (expected [00000001 80000000; 00000002 00000001])",
                 s.R_expected[0], s.R_expected[1], s.R_expected[2], s.R_expected[3]);

        // ---------------- STEP 4: check() ----------------
        // a) correct result -> 0 errors
        R_hw = new[s.size];
        foreach (R_hw[i]) R_hw[i] = s.R_expected[i];
        errors = s.check(R_hw);
        assert (errors == 0) else $error("check() reported errors on a correct result");
        $display("STEP 4a: correct R_hw  -> check() returned %0d", errors);
        // b) broken result on purpose: one wrong value + one X -> the assertions must fire
        $display("STEP 4b: wrong R_hw on purpose (2 errors EXPECTED below):");
        R_hw[1] = 32'h1234_5678;      // wrong value
        R_hw[3] = 32'hxxxx_xxxx;      // unknown (X) from "hardware"
        errors = s.check(R_hw);
        assert (errors == 2) else $error("check() should report 2 errors, got %0d", errors);
        $display("STEP 4b: broken R_hw   -> check() returned %0d (expected 2)", errors);

        // ---------------- STEP 5: display() ----------------
        $display("STEP 5: display() of a random SMALL and a random EDGE job:");
        void'(s.randomize() with {mode == SMALL;}); s.compute_ref(); s.display();
        void'(s.randomize() with {mode == EDGE;});  s.compute_ref(); s.display();

        $display("ALL STEPS DONE");
        $finish;
    end
endmodule
