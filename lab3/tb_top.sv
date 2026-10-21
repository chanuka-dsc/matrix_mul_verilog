`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_top.sv  --  Lab 3, Person B (Chanuka): interface, assertions, coverage
//
// Works together with Dipon's stimulus.sv (class `stimulus`, see TEAM_PLAN.md).
// Until that file is ready, the project uses stimulus_standin.sv instead.
//
// THE ONE TIMING RULE (the Lab 2 lesson):
//   change DUT inputs only like this:   @(posedge clk);  sig <= value;
//   -> the new value lands just AFTER the edge, so the DUT sees it at the NEXT edge.
//   A word is transferred on an edge where valid && ready were both 1.
//////////////////////////////////////////////////////////////////////////////////

module tb_top;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam int DIM_LOG = 2;              // 4x4 while debugging, 6 (64x64) for the final run
    localparam int DIM     = 2**DIM_LOG;
    localparam int SIZE    = DIM*DIM;
    localparam int DATA_WIDTH    = 32;
    
    // AGU state codes (copied from mat_mul.v, module AGU) - used by the coverage in STEP 6
    localparam logic [5:0] S_IDLE   = 6'b000001,
                           S_LOAD_A = 6'b000010,
                           S_LOAD_B = 6'b000100,
                           S_CALC   = 6'b001000,
                           S_WAIT   = 6'b010000,
                           S_OUT    = 6'b100000;

    // ------------------------------------------------------------------
    // STEP 1: signals, clock, DUT
    // ------------------------------------------------------------------
    // TODO 1a: one `logic` for every port of mat_mul. Use the SAME names as the ports.
    logic s00_axi_aclk;
    logic s00_axi_aresetn;
    logic s00_axis_tready;                            
    logic [DATA_WIDTH-1:0] s00_axis_tdata;
    logic s00_axis_tlast;
    logic s00_axis_tvalid;
    logic m00_axis_tvalid;
    logic [DATA_WIDTH-1 : 0] m00_axis_tdata;
    logic [(DATA_WIDTH/8)-1 : 0] m00_axis_tstrb;
    logic m00_axis_tlast;
    logic  m00_axis_tready;
    logic sel;
    logic start;
//   Ports: s00_axi_aclk, s00_axi_aresetn,
    //          s00_axis_tready, s00_axis_tdata [31:0], s00_axis_tlast, s00_axis_tvalid,
    //          m00_axis_tvalid, m00_axis_tdata [31:0], m00_axis_tstrb [3:0], m00_axis_tlast, m00_axis_tready,
    //          sel, start


    // TODO 1b: a 20 ns clock (same two lines as in your Lab 2 testbenches)
    initial s00_axi_aclk = 0;
    always #10 s00_axi_aclk = ~s00_axi_aclk;

    // TODO 1c: the DUT. Name the instance `dut` (STEP 6 uses dut.agu_inst.current_state).
    mat_mul # (
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
    // STEP 2-4: class tb  (the four steps of the Lab 2 testbench as members)
    // ------------------------------------------------------------------
    class tb;
        stimulus   stim;          // Dipon's object: A, B, R_expected, compute_ref(), check()
        logic [31:0] R_hw[];        // the result words we receive from the DUT
        int        errors;

        function new();
            stim = new(DIM);
            R_hw = new[SIZE];
        endfunction

        // ---- Lab 3 step 1: matrix initialization ----
        function void init();
            // TODO 2a: randomize stim; if it fails, stop the simulation.
            //   Immediate assertion form (lecture Verification II, slide 12):
            //   assert (<something that must be true>) else $fatal(1, "message");
            //   Then call stim.display() so you can see what was generated.
            
            assert( stim.randomize()) else $fatal (1, "generating random number failed !!!");
        endfunction

        // ---- Lab 3 step 2: reference result ----
        function void compute();
            // TODO 2b: one line - let Dipon's class compute R_expected.
            stim.compute_ref();
            stim.display();        // print A, B and the expected R (after compute_ref, so R is filled)
        endfunction

        // ---- Lab 3 step 3: feed the matrices to the DUT ----
        // Sends ONE word with the AXI-Stream handshake and returns after it was accepted.
        task send_word(bit [31:0] data, bit last);
            // TODO 3a:
            //   1. put the word on the bus with '<=' : tdata, tvalid = 1, tlast = last
            //   2. wait for clock edges until the DUT had tready = 1 at an edge.
            //      Pattern:   do @(posedge clk); while (!s00_axis_tready);
            //      (reading tready right at the edge gives the value it had JUST BEFORE
            //       the edge, i.e. exactly what the DUT used for the handshake)
            s00_axis_tvalid <= 1;
            s00_axis_tdata <= data;
            s00_axis_tlast <= last;
            do @(posedge s00_axi_aclk);
            while(!s00_axis_tready);

        endtask

        task send();
            // TODO 3b:
            //   - start aligned to the clock:  @(posedge clk);
            //   - sel <= 0, then send every element of stim.A with send_word (last=1 on the last one)
            //   - after the last word: tvalid <= 0, tlast <= 0
            //   - same for stim.B with sel <= 1
            //   Loop example:  foreach (stim.A[i]) send_word(stim.A[i], i == SIZE-1);
            //   Tip: put 1-2 idle clock edges between A and B (the DUT goes back to IDLE in between).
            
            @(posedge s00_axi_aclk);
            sel <= 0; 
            foreach(stim.A[i])
                send_word(stim.A[i], i == SIZE-1);
            s00_axis_tvalid <= 0;
            s00_axis_tlast <= 0;
            
            repeat (2) @(posedge s00_axi_aclk );
            
            sel <= 1; 
            foreach(stim.B[i])
                send_word(stim.B[i], i == SIZE-1);
            s00_axis_tvalid <= 0;
            s00_axis_tlast <= 0;
        endtask

        // ---- Lab 3 step 4: start, collect the result, compare ----
        task run_and_check();
            int n = 0;            // number of result words received
            // TODO 4a: a ONE-cycle start pulse:   @(posedge clk); start <= 1;  @(posedge clk); start <= 0;
            @(posedge s00_axi_aclk); start <= 1;
            @(posedge s00_axi_aclk); start <= 0;
            // TODO 4b: receive loop. On every clock edge:
            //   - if (m00_axis_tvalid && m00_axis_tready) -> store m00_axis_tdata in R_hw[n], n++,
            //     and leave the loop if m00_axis_tlast was 1 on that word
            //   - then choose the NEXT tready randomly (back-pressure, ~70 % ready):
            //       m00_axis_tready <= ($urandom_range(0, 99) < 70);
            //   Loop form:  forever begin @(posedge clk); ... if (...) break; end
            
            forever begin
                @(posedge s00_axi_aclk);
                if (m00_axis_tvalid && m00_axis_tready) begin
                    R_hw[n] = m00_axis_tdata;
                    n = n + 1 ;
                    if (m00_axis_tlast)
                        break;
                 end
                 m00_axis_tready <= ($urandom_range(0, 99) < 70);
                
            end     
            // TODO 4c: after the loop: m00_axis_tready <= 0;
            //   immediate assertion: exactly SIZE words arrived (else $error)
            //   errors = stim.check(R_hw);   then print PASS / FAIL with $display
            m00_axis_tready <= 0;
            assert (n == SIZE) else $error("Expected %d elements got %d", SIZE, n);
            errors = stim.check(R_hw);
            $display("Test %s ", errors == 0 ? "Pass" : "Fail");
        endtask
    endclass

    // ------------------------------------------------------------------
    // STEP 5: concurrent assertions on the OUTPUT AXI-Stream (Lab 3 task 4)
    // ------------------------------------------------------------------
    // Lecture form (Verification II, slides 15-20):
    //   property p_name;
    //       @(posedge clk) disable iff (!s00_axi_aresetn)
    //       <condition> |=> <what must hold one cycle later>;      // or |-> for the same cycle
    //   endproperty
    //   a_name: assert property (p_name) else $error("p_name failed at %0t", $time);
    //
    // TODO 5a: a word is held until it is accepted:     tvalid && !tready |=> tvalid
    // TODO 5b: the word does not change while stalled:  tvalid && !tready |=> $stable(tdata) && $stable(tlast)
    // TODO 5c: tlast only together with a valid word:   tlast |-> tvalid
    // TODO 5d: no unknown data on the bus:              tvalid |-> !$isunknown(tdata)
    //   (all four use the m00_axis_* signals)


    // ------------------------------------------------------------------
    // STEP 6: FSM transition coverage (Lab 3 task 5)
    // ------------------------------------------------------------------
    // Lecture form (Verification II, slide 37):
    //   covergroup cov_fsm @(posedge clk);
    //       coverpoint dut.agu_inst.current_state {
    //           bins idle_to_loadA = (S_IDLE => S_LOAD_A);
    //           ...
    //       }
    //   endgroup
    //   cov_fsm fsm_cov = new();
    // TODO 6: bins for every transition of the AGU:
    //   IDLE->LOAD_A, LOAD_A->IDLE, IDLE->LOAD_B, LOAD_B->IDLE, IDLE->CALC, CALC->WAIT, WAIT->OUT, OUT->IDLE
    //   + one bin for OUT held 3 or more cycles (happens with back-pressure):  (S_OUT [*3:$])
    //   Report (Tcl console, after the run):  xcrg -report_format html -dir <path to xsim.covdb>


    // ------------------------------------------------------------------
    // STEP 7: the test itself
    // ------------------------------------------------------------------
    tb t;                                      // declare the handle here, create it below

    initial begin
        // TODO 7a: start values for every input you drive (all 0; aresetn = 0 = reset active)
        s00_axi_aresetn = 0;                         
        s00_axis_tdata = 0;
        s00_axis_tlast = 0;
        s00_axis_tvalid = 0;
        m00_axis_tready = 0;
        sel = 0;
        start = 0;
        // TODO 7b: hold reset for 2 clock edges, then release it (with <= after an edge)
        repeat (2) @(posedge s00_axi_aclk);
        s00_axi_aresetn <= 1 ;
        t = new();

        // TODO 7c: run the four steps a few times in a row WITHOUT reset in between,
        //   e.g. repeat (3) begin t.init(); t.compute(); t.send(); t.run_and_check(); end
        //   (with randc, 3 runs = every mode once)
        repeat (3) begin
            t.init();
            t.compute();
            t.send();
            t.run_and_check();
        end
        $display("tb_top: all runs finished");
        $finish;
    end

endmodule
