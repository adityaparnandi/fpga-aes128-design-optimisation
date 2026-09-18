`timescale 1ns/1ps

module top #(
    parameter integer REG_IN         = 1,
    parameter integer REG_INV_AFF    = 1,
    parameter integer REG_ISO        = 1,
    parameter integer REG_SPLIT      = 1,
    parameter integer REG_DEN        = 1,
    parameter integer REG_DEN2       = 1,
    parameter integer REG_DENINV_SQ  = 1,
    parameter integer REG_DENINV_M1  = 1,
    parameter integer REG_DENINV_PP  = 1,
    parameter integer REG_DENINV     = 1,
    parameter integer REG_DENINV_DUP = 1,
    parameter integer REG_MUL_PP     = 1,
    parameter integer REG_MUL        = 1,
    parameter integer REG_OUT        = 1
)(
    input  wire        CLK100MHZ,
    input  wire        BTNC,
    input  wire [15:0] SW,
    output wire        OUT_BIT
);

wire clk = CLK100MHZ;
wire rst = BTNC;

// Registered input so timing is reg-to-reg and logic is not optimized away
reg [7:0] in_r;
always @(posedge clk) begin
    if (rst)
        in_r <= 8'h00;
    else
        in_r <= SW[7:0];
end

wire [7:0] core_out;

inv_subbytes_cf_pipelined #(
    .REG_IN         (REG_IN),
    .REG_INV_AFF    (REG_INV_AFF),
    .REG_ISO        (REG_ISO),
    .REG_SPLIT      (REG_SPLIT),
    .REG_DEN        (REG_DEN),
    .REG_DEN2       (REG_DEN2),
    .REG_DENINV_SQ  (REG_DENINV_SQ),
    .REG_DENINV_M1  (REG_DENINV_M1),
    .REG_DENINV_PP  (REG_DENINV_PP),
    .REG_DENINV     (REG_DENINV),
    .REG_DENINV_DUP (REG_DENINV_DUP),
    .REG_MUL_PP     (REG_MUL_PP),
    .REG_MUL        (REG_MUL),
    .REG_OUT        (REG_OUT)
) u_core (
    .clk      (clk),
    .en       (1'b1),
    .in_byte  (in_r),
    .out_byte (core_out)
);

// Registered output endpoint
reg [7:0] out_r;
always @(posedge clk) begin
    if (rst)
        out_r <= 8'h00;
    else
        out_r <= core_out;
end

// Single observable output bit keeps Vivado from optimising the design away
assign OUT_BIT = out_r[0];

endmodule