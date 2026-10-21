`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_top.sv  --  Lab 3: object-oriented testbench for the matrix multiplier
//
// Person B (Chanuka): class tb, AXI-Stream send/receive, concurrent assertions
// Person A (Dipon):   stimulus.sv (random matrices, reference model, check)
//                     and the FSM coverage in this file
//
// Timing rule used everywhere (the Lab 2 lesson):
//   DUT inputs only change like this:   @(posedge clk);  sig <= value;
//   -> the new value lands just AFTER the edge, so the DUT sees it at the NEXT edge.
//   A word is transferred on an edge where valid && ready were both 1.
//////////////////////////////////////////////////////////////////////////////////

module tb_top;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam int DIM_LOG    = 2;           // 2 = 4x4 for debugging, 6 = 64x64 for the final run
    localparam int DIM        = 2**DIM_LOG;
    localparam int SIZE       = DIM*DIM;
    localparam int DATA_WIDTH = 32;

    // AGU state codes (copied from mat_mul.v, module AGU), used by the FSM coverage
    localparam logic [5:0] S_IDLE   = 6'b000001,
                           S_LOAD_A = 6'b000010,
                           S_LOAD_B = 6'b000100,
                           S_CALC   = 6'b001000,
                           S_WAIT   = 6'b010000,
                           S_OUT    = 6'b100000;

    // ------------------------------------------------------------------
    // Signals, clock and DUT
    // ------------------------------------------------------------------
    // One signal per port of mat_mul, with the same names as the ports.
    // s00_axis_* = the DUT's input stream  (the testbench is the sender)
    // m00_axis_* = the DUT's output stream (the testbench is the receiver)
    logic                        s00_axi_aclk;
    logic                        s00_axi_aresetn;
    logic                        s00_axis_tready;
    logic [DATA_WIDTH-1:0]       s00_axis_tdata;
    logic                        s00_axis_tlast;
    logic                        s00_axis_tvalid;
    logic                        m00_axis_tvalid;
    logic [DATA_WIDTH-1:0]       m00_axis_tdata;
    logic [(DATA_WIDTH/8)-1:0]   m00_axis_tstrb;
    logic                        m00_axis_tlast;
    logic                        m00_axis_tready;
    logic                        sel;
    logic                        start;

    // 20 ns clock
    initial s00_axi_aclk = 0;
    always #10 s00_axi_aclk = ~s00_axi_aclk;

    // The design under test (instance name `dut`; the FSM coverage looks at dut.agu_inst)
    mat_mul #(
        .DIM_LOG(DIM_LOG),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axis_tready(s00_axis_tready),
        .s00_axis_tdata(s00_axis_tdata),
        .s00_axis_tlast(s00_axis_tlast),
        .s00_axis_tvalid(s00_axis_tvalid),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_tdata(m00_axis_tdata),
        .m00_axis_tstrb(m00_axis_tstrb),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready),
        .sel(sel),
        .start(start)
    );

    // ------------------------------------------------------------------
    // class tb: the four steps of the Lab 2 testbench as class members
    // (Lab 3 tasks 1 and 2)
    // ------------------------------------------------------------------
    class tb;
        stimulus     stim;        // Dipon's object: A, B, R_expected, compute_ref(), check()
        logic [31:0] R_hw[];      // the result words received from the DUT (logic: X stays visible)
        int          errors;

        function new();
            stim = new(DIM);
            R_hw = new[SIZE];
        endfunction

        // ---- Step 1: matrix initialization ----
        // New random A and B (constraint mode chosen by randc). The immediate
        // assertion stops the simulation if the constraints cannot be solved.
        function void init();
            assert (stim.randomize()) else $fatal(1, "generating random number failed !!!");
        endfunction

        // ---- Step 2: reference result ----
        // Dipon's software model computes R_expected = A x B, then A, B and R are printed.
        function void compute();
            stim.compute_ref();
            stim.display();        // print after compute_ref, so R is filled
        endfunction

        // ---- Step 3: feed the matrices to the DUT ----
        // Sends ONE word with the AXI-Stream handshake: put the word on the bus
        // (tdata, tvalid = 1, tlast), then wait edge by edge until the DUT had
        // tready = 1 at an edge - that is the edge where the word was taken.
        // Reading tready right at the edge gives its value just BEFORE the edge,
        // i.e. exactly what the DUT used for the handshake.
        task send_word(bit [31:0] data, bit last);
            s00_axis_tvalid <= 1;
            s00_axis_tdata  <= data;
            s00_axis_tlast  <= last;
            do @(posedge s00_axi_aclk);
            while (!s00_axis_tready);
        endtask

        // Sends matrix A (sel = 0), then matrix B (sel = 1), tlast on the last word
        // of each. Two idle edges in between: the DUT goes back to IDLE after A.
        task send();
            @(posedge s00_axi_aclk);
            sel <= 0;
            foreach (stim.A[i])
                send_word(stim.A[i], i == SIZE-1);
            s00_axis_tvalid <= 0;
            s00_axis_tlast  <= 0;

            repeat (2) @(posedge s00_axi_aclk);

            sel <= 1;
            foreach (stim.B[i])
                send_word(stim.B[i], i == SIZE-1);
            s00_axis_tvalid <= 0;
            s00_axis_tlast  <= 0;
        endtask

        // ---- Step 4: start, collect the result, compare ----
        task run_and_check();
            int n = 0;            // number of result words received

            // one-cycle start pulse
            @(posedge s00_axi_aclk); start <= 1;
            @(posedge s00_axi_aclk); start <= 0;

            // Receive loop, one turn per clock edge. A word is received on an edge
            // where tvalid && tready were both 1; the word with tlast is the last one.
            // tready is chosen randomly every cycle (~70 % ready): this back-pressure
            // makes the DUT wait sometimes, which the output assertions check.
            forever begin
                @(posedge s00_axi_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    R_hw[n] = m00_axis_tdata;
                    n = n + 1;
                    if (m00_axis_tlast)
                        break;
                end
                m00_axis_tready <= ($urandom_range(0, 99) < 70);
            end

            // stop receiving, check the word count (immediate assertion),
            // then let Dipon's check() compare every element with R_expected
            m00_axis_tready <= 0;
            assert (n == SIZE) else $error("Expected %d elements got %d", SIZE, n);
            errors = stim.check(R_hw);
            $display("Test %s ", errors == 0 ? "Pass" : "Fail");
        endtask
    endclass

    // ------------------------------------------------------------------
    // Concurrent assertions on the OUTPUT AXI-Stream (Lab 3 task 4)
    // ------------------------------------------------------------------
    // Checked at every rising clock edge, switched off during reset.
    //   |->  the right side must hold at the SAME edge
    //   |=>  the right side must hold at the NEXT edge

    // A word that is offered but not accepted stays offered.
    property p_hold;
        @(posedge s00_axi_aclk) disable iff (!s00_axi_aresetn)
        m00_axis_tvalid && !m00_axis_tready |=> m00_axis_tvalid;
    endproperty
    a_hold: assert property (p_hold) else $error("p_hold failed at %0t", $time);

    // While stalled, the offered word (data and tlast) does not change.
    property p_stable;
        @(posedge s00_axi_aclk) disable iff (!s00_axi_aresetn)
        m00_axis_tvalid && !m00_axis_tready |=> $stable(m00_axis_tdata) && $stable(m00_axis_tlast);
    endproperty
    a_stable: assert property (p_stable) else $error("p_stable failed at %0t", $time);

    // tlast only together with a valid word (the old Lab 2 output state broke this rule).
    property p_last;
        @(posedge s00_axi_aclk) disable iff (!s00_axi_aresetn)
        m00_axis_tlast |-> m00_axis_tvalid;
    endproperty
    a_last: assert property (p_last) else $error("p_last failed at %0t", $time);

    // A valid word never contains unknown (X/Z) bits.
    property p_nox;
        @(posedge s00_axi_aclk) disable iff (!s00_axi_aresetn)
        m00_axis_tvalid |-> !$isunknown(m00_axis_tdata);
    endproperty
    a_nox: assert property (p_nox) else $error("p_nox failed at %0t", $time);

    // ------------------------------------------------------------------
    // FSM coverage (Lab 3 task 5)
    // ------------------------------------------------------------------
    // Sampled on every rising clock edge (white-box: we look inside the DUT at
    // dut.agu_inst.current_state). Three coverpoints answer the handout's questions:
    //   cp_state : is every state reached?                       (unreachable states?)
    //   cp_trans : is every legal transition taken?               (wrong transitions?)
    //   cp_never : transitions that must never happen              (wrong transitions?)
    //   + cov_hold below: how many cycles each state is held       (held long enough?)
    // Report after the run:  xcrg -report_format html -dir <sim folder>/xsim.covdb
    localparam int CALC_CYCLES = DIM*DIM*DIM;   // CALC: one cycle per (row, col, temp)
    localparam int WAIT_CYCLES = 3;             // WAIT: 2-cycle BRAM+MAC pipeline drain + R[0] prefetch

    covergroup cov_fsm @(posedge s00_axi_aclk);
        // 1) every state visited
        cp_state : coverpoint dut.agu_inst.current_state {
            bins idle   = {S_IDLE};
            bins load_a = {S_LOAD_A};
            bins load_b = {S_LOAD_B};
            bins calc   = {S_CALC};
            bins wait_s = {S_WAIT};          // 'wait' is a keyword, so wait_s
            bins out    = {S_OUT};
        }
        // 2) every legal transition of the AGU state diagram
        cp_trans : coverpoint dut.agu_inst.current_state {
            bins idle_to_loadA = (S_IDLE   => S_LOAD_A);
            bins loadA_to_idle = (S_LOAD_A => S_IDLE);
            bins idle_to_loadB = (S_IDLE   => S_LOAD_B);
            bins loadB_to_idle = (S_LOAD_B => S_IDLE);
            bins idle_to_calc  = (S_IDLE   => S_CALC);
            bins calc_to_wait  = (S_CALC   => S_WAIT);
            bins wait_to_out   = (S_WAIT   => S_OUT);
            bins out_to_idle   = (S_OUT    => S_IDLE);
        }
        // 3) transitions that must NEVER happen. weight = 0: they do not count in the score,
        //    but the report shows their hit count (must stay 0).
        cp_never : coverpoint dut.agu_inst.current_state {
            option.weight = 0;
            bins loadA_to_calc = (S_LOAD_A => S_CALC);
            bins loadA_to_loadB= (S_LOAD_A => S_LOAD_B);
            bins calc_to_idle  = (S_CALC   => S_IDLE);
            bins calc_to_out   = (S_CALC   => S_OUT);
            bins wait_to_idle  = (S_WAIT   => S_IDLE);
            bins out_to_calc   = (S_OUT    => S_CALC);
            bins idle_to_out   = (S_IDLE   => S_OUT);
        }
    endgroup

    cov_fsm fsm_cov = new();

    // ---- How long is each state held? ----
    // The lecture writes this as a repetition bin, e.g. (S_CALC[*64] => S_WAIT),
    // but Vivado 2025.2 crashes on [*N] inside transition bins ("wrong state type
    // while Populating tbin" / kernel FATAL_ERROR - tested). So we measure it:
    // count the cycles spent in the current state; when the state changes,
    // sample cov_hold with that length and check it with immediate assertions.
    logic [5:0]  fsm_prev  = '0;     // state during the previous cycle
    int unsigned fsm_cnt   = 0;      // cycles spent in fsm_prev so far
    logic [5:0]  left_state;         // the state that was just left
    int unsigned left_len;           // ... and how many cycles it was held

    covergroup cov_hold;             // sampled by hand when a state is left
        cp_loadA : coverpoint left_len iff (left_state == S_LOAD_A) { bins exactly_SIZE = {SIZE}; }
        cp_loadB : coverpoint left_len iff (left_state == S_LOAD_B) { bins exactly_SIZE = {SIZE}; }
        cp_calc  : coverpoint left_len iff (left_state == S_CALC)   { bins exactly_DIM3 = {CALC_CYCLES}; }
        cp_wait  : coverpoint left_len iff (left_state == S_WAIT)   { bins exactly_3    = {WAIT_CYCLES}; }
        cp_out   : coverpoint left_len iff (left_state == S_OUT)    { bins stalled      = {[SIZE+1 : 100*SIZE]}; }
    endgroup
    cov_hold hold_cov = new();

    always @(posedge s00_axi_aclk) begin
        logic [5:0] cur;
        if (s00_axi_aresetn) begin
            cur = dut.agu_inst.current_state;    // read at the edge = state of the cycle that just ended
            if (cur == fsm_prev)
                fsm_cnt++;
            else begin
                if (fsm_cnt != 0) begin          // a state was left: record and check its length
                    left_state = fsm_prev;
                    left_len   = fsm_cnt;
                    hold_cov.sample();
                    case (left_state)
                        S_LOAD_A, S_LOAD_B:
                            assert (left_len >= SIZE)
                                else $error("FSM: LOAD held %0d cycles, needs >= %0d (one per word)", left_len, SIZE);
                        S_CALC:
                            assert (left_len == CALC_CYCLES)
                                else $error("FSM: CALC held %0d cycles, expected %0d (DIM^3)", left_len, CALC_CYCLES);
                        S_WAIT:
                            assert (left_len == WAIT_CYCLES)
                                else $error("FSM: WAIT held %0d cycles, expected %0d", left_len, WAIT_CYCLES);
                        S_OUT:
                            assert (left_len >= SIZE)
                                else $error("FSM: OUT held %0d cycles, needs >= %0d (one per word)", left_len, SIZE);
                        default: ;
                    endcase
                    if (left_state != S_IDLE)
                        $display("FSM: %-6s held %0d cycles", state_name(left_state), left_len);
                end
                fsm_prev = cur;
                fsm_cnt  = 1;
            end
        end
    end

    function string state_name(logic [5:0] st);
        case (st)
            S_IDLE:   return "IDLE";
            S_LOAD_A: return "LOAD_A";
            S_LOAD_B: return "LOAD_B";
            S_CALC:   return "CALC";
            S_WAIT:   return "WAIT";
            S_OUT:    return "OUT";
            default:  return "??";
        endcase
    endfunction

    // ------------------------------------------------------------------
    // The test itself
    // ------------------------------------------------------------------
    tb t;                                      // handle declared here, object created below

    initial begin
        // start values for every input the testbench drives; reset active (aresetn = 0)
        s00_axi_aresetn = 0;
        s00_axis_tdata  = 0;
        s00_axis_tlast  = 0;
        s00_axis_tvalid = 0;
        m00_axis_tready = 0;
        sel             = 0;
        start           = 0;

        // hold reset for 2 clock edges, then release it
        repeat (2) @(posedge s00_axi_aclk);
        s00_axi_aresetn <= 1;
        t = new();

        // three complete jobs back-to-back WITHOUT reset in between
        // (randc: every constraint mode is used once)
        repeat (3) begin
            t.init();
            t.compute();
            t.send();
            t.run_and_check();
        end
        $display("tb_top: all runs finished");
        $display("FSM coverage (cov_fsm, states + transitions): %0.1f %%", fsm_cov.get_coverage());
        $display("FSM coverage (cov_hold, cycles per state)   : %0.1f %%", hold_cov.get_coverage());
        $finish;
    end

endmodule
