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

//TODO
wire en_A;
wire rw_A;
wire [SIZE_LOG-1:0] addr_A;
wire en_B;
wire rw_B;
wire [SIZE_LOG-1:0] addr_B;
wire en_R;
wire rw_R;
wire [SIZE_LOG-1:0] addr_R;
wire [DATA_WIDTH-1:0]data_A;
wire [DATA_WIDTH-1:0]data_B;
wire [DATA_WIDTH-1:0]data_R;


// Input capture on the FALLING edge.
// The testbench changes tvalid/tlast/sel/start with blocking (=) and tdata with
// non-blocking (<=) assignments exactly at the rising edge, so at that edge the
// design would see a mix of new and old values (race). Half a cycle later, at the
// falling edge, all of them have settled, so these copies always belong together.
reg [DATA_WIDTH-1:0] tdata_q;
reg tvalid_q, tlast_q, sel_q, start_q;

always @(negedge s00_axi_aclk) begin
    tdata_q  <= s00_axis_tdata;
    tvalid_q <= s00_axis_tvalid;
    tlast_q  <= s00_axis_tlast;
    sel_q    <= sel;
    start_q  <= start;
end

wire first;
reg [0:0]clear;
assign first = en_A == 1  &&  rw_A == 0  &&  addr_A[DIM_LOG-1:0] == 0; // in CALC, and the first product of a new result element
always @(posedge s00_axi_aclk) begin
    clear <= first;
end

AGU  #(.DIM_LOG(DIM_LOG), .DATA_WIDTH(DATA_WIDTH)) agu (.sel(sel_q), .start(start_q), .en_A(en_A), .en_B(en_B), .en_R(en_R), .rw_A(rw_A), .rw_B(rw_B), .rw_R(rw_R),
            .addr_A(addr_A), .addr_B(addr_B), .addr_R(addr_R), .s00_axi_aclk(s00_axi_aclk), .s00_axi_aresetn(s00_axi_aresetn),
            .s00_axis_tready(s00_axis_tready), .s00_axis_tlast(tlast_q), .s00_axis_tvalid(tvalid_q),
            .m00_axis_tvalid(m00_axis_tvalid), .m00_axis_tlast(m00_axis_tlast), .m00_axis_tready(m00_axis_tready));

bram #(.DIM_LOG(DIM_LOG), .DATA_WIDTH(DATA_WIDTH)) matA (
     .s00_axi_aclk(s00_axi_aclk),
     .s00_axi_aresetn(s00_axi_aresetn),  
     .en(en_A),
     .rw(rw_A),
     .addr(addr_A),
     .data_in(tdata_q),
     .data_out(data_A)
);


bram #(.DIM_LOG(DIM_LOG), .DATA_WIDTH(DATA_WIDTH)) matB (
     .s00_axi_aclk(s00_axi_aclk),
     .s00_axi_aresetn(s00_axi_aresetn),  
     .en(en_B),
     .rw(rw_B),
     .addr(addr_B),
     .data_in(tdata_q),
     .data_out(data_B)
);

wire [DATA_WIDTH-1:0] data_out_R;

assign m00_axis_tdata = data_out_R;
assign m00_axis_tstrb = 4'hf;
bram #(.DIM_LOG(DIM_LOG), .DATA_WIDTH(DATA_WIDTH)) matR (
     .s00_axi_aclk(s00_axi_aclk),
     .s00_axi_aresetn(s00_axi_aresetn),  
     .en(en_R),
     .rw(rw_R),
     .addr(addr_R),
     .data_in(data_R),
     .data_out(data_out_R)
);

MAC #(.DIM_LOG(DIM_LOG), .DATA_WIDTH(DATA_WIDTH)) mac (
         .s00_axi_aclk(s00_axi_aclk),
         .s00_axi_aresetn(s00_axi_aresetn),
         .clear(clear),
         .data_A(data_A),
         .data_B(data_B),
         .data_R(data_R)
     );
     
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
// clear = 1 loads 0 into regAcc. 
// First operands of a new element must arrive at the same edge as clear. 
// data_R (= sum) holds the finished total for ONE clock cycle: ...
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

localparam S_IDLE = 0, S_LOAD_A = 1, S_LOAD_B = 2, S_CALC = 3, S_OUTPUT = 4;

reg [2:0]state;
reg [SIZE_LOG-1: 0] counter;
reg [DIM_LOG -1: 0]row;
reg [DIM_LOG -1: 0]col;
reg [DIM_LOG -1: 0]temp;

reg [0: 0]last_d1;
reg [0: 0]last_d2;
reg [0: 0]wr_d1;
reg [0: 0]wr_d2;
reg [SIZE_LOG-1: 0]addR_d1;
reg [SIZE_LOG-1: 0]addR_d2;
wire last;

reg [0: 0]out_valid;
reg [0: 0]out_last;
assign last = (row == DIM-1) && (col == DIM-1) && (temp == DIM-1);
always @(posedge s00_axi_aclk) begin
        if (!s00_axi_aresetn) 
            state <= S_IDLE;
        else begin
            case (state)
                
                S_IDLE: begin
           
                    counter <= 0;
                    row <= 0;
                    col <= 0;
                    temp <= 0;
                    last_d1 <= 0;
                    last_d2 <= 0;
                    wr_d1 <= 0;
                    wr_d2 <= 0;
                    out_valid <= 0;
                    out_last <= 0;

                if(s00_axis_tvalid && sel == 0)
                        state <= S_LOAD_A;
                    else if (s00_axis_tvalid && sel == 1)
                        state <= S_LOAD_B;
                    else if (start)
                        state <= S_CALC;
                    else
                        state <= S_IDLE;
                end
                
                S_LOAD_A: begin
  
                    if(s00_axis_tvalid) begin
                        counter <= counter + 1;
                        if (s00_axis_tlast) begin          
                            state <= S_IDLE;
                         end
                    end
                end
                
                S_LOAD_B: begin
                   
                    if(s00_axis_tvalid) begin
                        counter <= counter + 1;
                        if (s00_axis_tlast)
                            state <= S_IDLE;
                    end
                end
                
                S_CALC: begin
                    
                    if(temp < (DIM - 1)) 
                        temp <= temp + 1;
                    else if (col < DIM - 1)begin
                        temp <= 0;
                        col <= col + 1;
                    end 
                    else begin
                        temp <= 0;
                        col <= 0;
                        row <= row + 1;    
                    end
                    
                    last_d1 <= last;
                    
                    last_d2 <= last_d1;
                    
                    wr_d1  <= temp == DIM - 1;
                    
                    wr_d2 <= wr_d1;
                    
                    addR_d1 <= row * DIM + col;
                    
                    addR_d2 <= addR_d1;
                    
                    if(last_d2) 
                        state <= S_OUTPUT;  
                end
                
                S_OUTPUT: begin
                    out_valid <= 1;
                    counter <= counter + 1;
                    out_last <= counter == SIZE -1;
                    
                    if(out_last && out_valid && m00_axis_tready ) 
                            state <= S_IDLE;
                end
                
                default : state <= S_IDLE;
            endcase
        end      
    
end

always @(*) begin
    s00_axis_tready  = 0;
    en_A  = 0;
    en_B  = 0;
    en_R  = 0;
    rw_A  = 0;
    rw_B = 0;
    rw_R = 0;
    addr_A = 0;
    addr_B = 0;
    addr_R = 0;
    m00_axis_tvalid  = 0;
    m00_axis_tlast = 0;
    case (state)        
        S_IDLE:
        ;
        
        S_LOAD_A: begin
           s00_axis_tready = 1;
           rw_A = 1;
           addr_A = counter;
           if(s00_axis_tvalid)
                en_A = 1;
 
        end
        
        S_LOAD_B: begin
           s00_axis_tready = 1;
           addr_B = counter;
           rw_B = 1;
           if(s00_axis_tvalid) 
                en_B = 1;
        end
        
        S_CALC: begin
            en_A = 1;
            rw_A = 0;
            en_B = 1;
            rw_B = 0;
            
            addr_A = row*DIM + temp;
            addr_B = temp*DIM + col;
            
            en_R = wr_d2;
            rw_R = 1;
            addr_R = addR_d2;
        end
        
        S_OUTPUT: begin
            m00_axis_tvalid = out_valid;
            m00_axis_tlast = out_last;
            en_R = 1;
            rw_R = 0;
            addr_R = counter;
        end
        
    endcase
end
endmodule

