`timescale 1ns/1ps
// ----------------------------------------------------------------------------
// top.v
// ----------------------------------------------------------------------------
// Nexys4 DDR top-level for XTIME MixColumns (aes_mixcolumns_xtime).
// Ports match cons.xdc: CLK100MHZ, BTNC, SW[15:0], LED[15:0].
// ----------------------------------------------------------------------------
module top (
  input  wire        CLK100MHZ,
  input  wire        BTNC,
  input  wire [15:0] SW,
  output wire [15:0] LED
);
  wire rst_n = ~BTNC;

  localparam integer REG_X2  = 1;
  localparam integer REG_X3  = 1;
  localparam integer REG_OUT = 1;

  wire [31:0] col_in  = {SW, SW};
  wire [31:0] col_out;

  aes_mixcolumns_xtime #(
    .REG_X2  (REG_X2),
    .REG_X3  (REG_X3),
    .REG_OUT (REG_OUT)
  ) u_mc (
    .clk     (CLK100MHZ),
    .rst_n   (rst_n),
    .col_in  (col_in),
    .col_out (col_out)
  );

  assign LED = col_out[15:0];
endmodule
