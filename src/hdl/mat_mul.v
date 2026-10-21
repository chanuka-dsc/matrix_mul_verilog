`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// mat_mul.v
//
// Uppsala University
// Yuan Yao <yuan.yao@it.uu.se>
// For the course 1DT109 Accelerating System with Programmable Logic Components
//
//////////////////////////////////////////////////////////////////////////////////


module mat_mul #
    (
        parameter integer DIM_LOG = 1,     /* matrix dimension in log2; e.g. A[8][8] has the DIM of 8, DIM_LOG of 3, and SIZE of 64; change this as desired;
                                              you will need to set this parameter in the testbench and the ARM software in the SDK. */
        parameter integer DIM = 2**DIM_LOG,
        parameter integer SIZE = DIM*DIM,
        parameter integer SIZE_LOG = 2*DIM_LOG,
        parameter integer DATA_WIDTH = 32
    )
    (
        // Clock and Reset shared with the AXI-Lite Slave Port
        input wire  s00_axi_aclk,
        input wire  s00_axi_aresetn,
        
        // AXI-Stream Slave
        output wire  s00_axis_tready,
        input  wire  [DATA_WIDTH-1 : 0] s00_axis_tdata,
        input  wire  s00_axis_tlast,
        input  wire  s00_axis_tvalid,
        
        // AXI-Stream Master
        output wire  m00_axis_tvalid,
        output wire  [DATA_WIDTH-1 : 0] m00_axis_tdata,
        output wire  [(DATA_WIDTH/8)-1 : 0] m00_axis_tstrb,
        output wire  m00_axis_tlast,
        input  wire  m00_axis_tready,
        
        // Matrix-select and Start signals coming from the AXI-Lite Slave Port
        input wire sel,
        input wire start
    );


// 1. Declare internal wires to connect the modules
    wire en_A, en_B, en_R;
    wire rw_A, rw_B, rw_R;
    wire [SIZE_LOG-1 : 0] addr_A, addr_B, addr_R;
    wire [DATA_WIDTH-1 : 0] b_data_A, b_data_B, b_data_R;
    reg  mac_clear;   // MAC clear: generated below from the matA read address

    // 2. Instantiate the Address Generator Unit (Controller)
    AGU #(
        .DIM_LOG(DIM_LOG),
        .DIM(DIM),
        .SIZE(SIZE),
        .SIZE_LOG(SIZE_LOG),
        .DATA_WIDTH(DATA_WIDTH)
    ) agu_inst (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axis_tready(s00_axis_tready),
        .s00_axis_tlast(s00_axis_tlast),
        .s00_axis_tvalid(s00_axis_tvalid),
        .m00_axis_tvalid(m00_axis_tvalid),
        .m00_axis_tlast(m00_axis_tlast),
        .m00_axis_tready(m00_axis_tready),
        .sel(sel),
        .start(start),
        .en_A(en_A), .en_B(en_B), .en_R(en_R),
        .rw_A(rw_A), .rw_B(rw_B), .rw_R(rw_R),
        .addr_A(addr_A), .addr_B(addr_B), .addr_R(addr_R)
    );

    // 3. Instantiate the three Block RAMs (Storage)
    bram #(
        .DIM_LOG(DIM_LOG),
        .DIM(DIM),
        .SIZE(SIZE),
        .SIZE_LOG(SIZE_LOG),
        .DATA_WIDTH(DATA_WIDTH)
    ) matA_inst (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .en(en_A),
        .rw(rw_A),
        .addr(addr_A),
        .data_in(s00_axis_tdata), 
        .data_out(b_data_A)
    );

    bram #(
        .DIM_LOG(DIM_LOG),
        .DIM(DIM),
        .SIZE(SIZE),
        .SIZE_LOG(SIZE_LOG),
        .DATA_WIDTH(DATA_WIDTH)
    ) matB_inst (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .en(en_B),
        .rw(rw_B),
        .addr(addr_B),
        .data_in(s00_axis_tdata), 
        .data_out(b_data_B)
    );

    bram #(
        .DIM_LOG(DIM_LOG),
        .DIM(DIM),
        .SIZE(SIZE),
        .SIZE_LOG(SIZE_LOG),
        .DATA_WIDTH(DATA_WIDTH)
    ) matR_inst (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .en(en_R),
        .rw(rw_R),
        .addr(addr_R),
        .data_in(b_data_R),       
        .data_out(m00_axis_tdata) 
    );

    // 4. Instantiate the Multiply-Accumulate Unit (Datapath)
    MAC #(
        .DIM_LOG(DIM_LOG),
        .DIM(DIM),
        .SIZE(SIZE),
        .SIZE_LOG(SIZE_LOG),
        .DATA_WIDTH(DATA_WIDTH)
    ) mac_inst (
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .clear(mac_clear),
        .data_A(b_data_A),
        .data_B(b_data_B),
        .data_R(b_data_R)
    );

    // 5. MAC clear: when the AGU reads A[row][0] (temp = low DIM_LOG bits of addr_A == 0)
    //    the next element starts. BRAM read latency is 1 cycle, so clear is registered once
    //    and reaches the MAC at the same edge as the first operands of the element.
    always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) mac_clear <= 1'b0;
        else mac_clear <= en_A && !rw_A && (addr_A[DIM_LOG-1 : 0] == 0);
    end

    assign m00_axis_tstrb = {(DATA_WIDTH/8){1'b1}};   // all bytes valid
       
endmodule

module bram #
(
    parameter integer DIM_LOG = 1,
    parameter integer DIM = 2**DIM_LOG,
    parameter integer SIZE = DIM*DIM,
    parameter integer SIZE_LOG = 2*DIM_LOG,
    parameter integer DATA_WIDTH = 32
)
(
    input wire s00_axi_aclk,
    input wire s00_axi_aresetn,  
    input wire en,
    input wire rw,
    input wire [SIZE_LOG-1 : 0] addr,
    input wire [DATA_WIDTH-1 : 0] data_in,
    output reg [DATA_WIDTH-1 : 0] data_out
);

//TODO
// rw = 1 -> write, rw = 0 -> read
 reg [DATA_WIDTH - 1: 0] mem [0:SIZE-1];
    
    always @(posedge s00_axi_aclk) begin
        if(en && rw)
            mem[addr] <= data_in;
    end
    
    always @(posedge s00_axi_aclk) begin
        if(en && !rw)
            data_out <= mem[addr];
    end

endmodule

module MAC #
(
    parameter integer DIM_LOG = 1,
    parameter integer DIM = 2**DIM_LOG,
    parameter integer SIZE = DIM*DIM,
    parameter integer SIZE_LOG = 2*DIM_LOG,
    parameter integer DATA_WIDTH = 32
)
(
    input wire s00_axi_aclk,
    input wire s00_axi_aresetn,
    input wire clear, 
    input wire [DATA_WIDTH-1 : 0] data_A,
    input wire [DATA_WIDTH-1 : 0] data_B,
    output wire [DATA_WIDTH-1 : 0] data_R
);

//TODO
// 3 registers: regA, regB (operands from the BRAMs) and regAcc (running sum).
// clear = 1 loads 0 into regAcc; the first operands of a new element arrive at the same edge.
// data_R (= sum) is the finished element in the cycle after its last operands are registered.
     reg [DATA_WIDTH-1 : 0]regA;
     reg [DATA_WIDTH-1 : 0] regB;
     reg [DATA_WIDTH-1 : 0] regAcc;
     
     wire [DATA_WIDTH-1 : 0] product;
     wire [DATA_WIDTH-1 : 0] sum;
     
     assign product = regA * regB;
     assign sum = product + regAcc;
     
     always @(posedge s00_axi_aclk) begin
        if(!s00_axi_aresetn) begin
            regAcc <= 0;
            regA <= 0;
            regB <= 0;
        end
        else begin
            regA <= data_A;
            regB <= data_B;
            if (clear)
                regAcc <= 0;
            else
                regAcc <=  sum;
        end
     end
    
     assign data_R = sum; 

endmodule

module AGU #
(
    parameter integer DIM_LOG = 1,
    parameter integer DIM = 2**DIM_LOG,
    parameter integer SIZE = DIM*DIM,
    parameter integer SIZE_LOG = 2*DIM_LOG,
    parameter integer DATA_WIDTH = 32
)
(
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    
    // AXI-Stream Slave
    output reg  s00_axis_tready,
    input wire  s00_axis_tlast,
    input wire  s00_axis_tvalid,
        
    // AXI-Stream Master
    output reg  m00_axis_tvalid,
    output reg  m00_axis_tlast,
    input wire  m00_axis_tready,
    
    input wire sel,
    input wire start,
    
    output reg en_A,
    output reg en_B,
    output reg en_R,
    output reg rw_A,
    output reg rw_B,
    output reg rw_R,
    output reg [SIZE_LOG-1 : 0] addr_A,
    output reg [SIZE_LOG-1 : 0] addr_B,
    output reg [SIZE_LOG-1 : 0] addr_R
);

//TODO
// 5 states, as in the lab manual (one-hot encoding)
localparam S_0 = 5'b00001; // S_IDLE      : all control signals at default
localparam S_1 = 5'b00010; // S_LOAD_A    : receive matA over AXI-Stream (sequential addresses)
localparam S_2 = 5'b00100; // S_LOAD_B    : receive matB over AXI-Stream (sequential addresses)
localparam S_3 = 5'b01000; // S_CALCULATE : read A/B, MAC, write R; then drain the pipeline
localparam S_4 = 5'b10000; // S_OUTPUT    : send matR over AXI-Stream

reg [4:0] current_state, next_state;
reg [SIZE_LOG-1 : 0] mem_counter;
reg [DIM_LOG-1 : 0] row, col, temp;
reg [1:0] wait_counter;     // counts drain cycles at the end of S_CALCULATE
reg addr_done;              // all row/col/temp addresses have been issued

reg [1:0] write_en_pipe;
reg [SIZE_LOG-1 : 0] addr_R_pipe [0:1];

// State Transition
always @(posedge s00_axi_aclk) begin
    if (!s00_axi_aresetn) current_state <= S_0;
    else current_state <= next_state;
end

// Next State Logic
always @(*) begin
    next_state = current_state;
    case (current_state)
        S_0: begin
            if (s00_axis_tvalid && sel == 1'b0) next_state = S_1;
            else if (s00_axis_tvalid && sel == 1'b1) next_state = S_2;
            else if (start) next_state = S_3;
        end
        S_1: if (s00_axis_tvalid && s00_axis_tready && s00_axis_tlast) next_state = S_0;
        S_2: if (s00_axis_tvalid && s00_axis_tready && s00_axis_tlast) next_state = S_0;
        // leave CALCULATE once the last sum is written and R[0] is pre-fetched
        S_3: if (addr_done && wait_counter == 2'd2) next_state = S_4;
        S_4: if (m00_axis_tvalid && m00_axis_tready && m00_axis_tlast) next_state = S_0;
        default: next_state = S_0;
    endcase
end

// Counters, Pointers, and Delay Lines
always @(posedge s00_axi_aclk) begin
    if (!s00_axi_aresetn) begin
        mem_counter <= 0; row <= 0; col <= 0; temp <= 0; wait_counter <= 0; addr_done <= 0;
        write_en_pipe <= 0;
        addr_R_pipe[0] <= 0; addr_R_pipe[1] <= 0;
    end else begin
        // SHIFT REGISTER: write enable/address used after 2 cycles
        // (1 cycle BRAM read + 1 cycle MAC input register; sum is combinational)
        write_en_pipe[0] <= (current_state == S_3 && !addr_done && temp == DIM - 1);
        write_en_pipe[1] <= write_en_pipe[0];

        addr_R_pipe[0] <= (row << DIM_LOG) + col;
        addr_R_pipe[1] <= addr_R_pipe[0];

        case (current_state)
            S_0: begin
                mem_counter <= 0; row <= 0; col <= 0; temp <= 0; wait_counter <= 0; addr_done <= 0;
            end
            S_1, S_2: begin
                if (s00_axis_tvalid && s00_axis_tready)
                    mem_counter <= s00_axis_tlast ? 0 : mem_counter + 1;
            end
            S_3: begin
                if (!addr_done) begin
                    if (row == DIM-1 && col == DIM-1 && temp == DIM-1) addr_done <= 1;
                    if (temp == DIM - 1) begin
                        temp <= 0;
                        if (col == DIM - 1) begin
                            col <= 0;
                            if (row != DIM - 1) row <= row + 1;
                        end else col <= col + 1;
                    end else temp <= temp + 1;
                end else
                    wait_counter <= wait_counter + 1;   // drain: 0, 1, 2
            end
            S_4: begin
                if (m00_axis_tvalid && m00_axis_tready)
                    mem_counter <= m00_axis_tlast ? 0 : mem_counter + 1;
            end
        endcase
    end
end

// Output 
always @(*) begin
    s00_axis_tready = 1'b0; m00_axis_tvalid = 1'b0; m00_axis_tlast = 1'b0;
    en_A = 1'b0; rw_A = 1'b0; addr_A = 0;
    en_B = 1'b0; rw_B = 1'b0; addr_B = 0;
    en_R = 1'b0; rw_R = 1'b0; addr_R = 0;
    
    case (current_state)
        S_1: begin s00_axis_tready = 1'b1; en_A = s00_axis_tvalid; rw_A = 1'b1; addr_A = mem_counter; end
        S_2: begin s00_axis_tready = 1'b1; en_B = s00_axis_tvalid; rw_B = 1'b1; addr_B = mem_counter; end
        S_3: begin
            en_A = !addr_done; rw_A = 1'b0; addr_A = (row << DIM_LOG) + temp;   // A[row][temp]
            en_B = !addr_done; rw_B = 1'b0; addr_B = (temp << DIM_LOG) + col;   // B[temp][col]
            
            // Write the MAC sum into R[row][col] 2 cycles after its last operands were addressed,
            // or pre-fetch R[0] on the last drain cycle so it is on m00_axis_tdata in S_OUTPUT
            en_R = write_en_pipe[1] | (addr_done && wait_counter == 2'd2); 
            rw_R = write_en_pipe[1]; 
            if (addr_done && wait_counter == 2'd2)
                addr_R = 0;
            else
                addr_R = addr_R_pipe[1];
        end
        S_4: begin
            m00_axis_tvalid = 1'b1; 
            en_R = m00_axis_tready; // Only advance BRAM read if testbench is ready
            rw_R = 1'b0; 
            addr_R = mem_counter + 1; // Read one cycle ahead
            if (mem_counter == SIZE - 1) m00_axis_tlast = 1'b1;
        end
    endcase
end
endmodule
