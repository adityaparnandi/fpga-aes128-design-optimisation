`timescale 1ns/1ps
// ----------------------------------------------------------------------------
// top_cf_nexys4ddr.v
// ----------------------------------------------------------------------------
// Nexys4 DDR top-level for COMPOSITE-FIELD MixColumns (aes_mixcolumns_cf).
// Ports match cons_nexys4ddr_min.xdc: CLK100MHZ, BTNC, SW[15:0], LED[15:0].
//
// Demo behaviour:
//  - Forms a 32-bit column input from switches: {SW, SW}
//  - Displays lower 16 bits of MixColumns output on LEDs
// ----------------------------------------------------------------------------
module top (
  input  wire        CLK100MHZ,
  input  wire        BTNC,      // active-HIGH reset button
  input  wire [15:0] SW,
  output wire [15:0] LED
);
  wire rst_n = ~BTNC;

  // ---- Pipeline enables (edit to sweep) ----
  localparam integer REG_ISO   = 1;
  localparam integer REG_TOWER = 1;
  localparam integer REG_INV   = 1;
  localparam integer REG_OUT   = 1;

  wire [31:0] col_in  = {SW, SW};
  wire [31:0] col_out;

  aes_mixcolumns_cf #(
    .REG_ISO  (REG_ISO),
    .REG_TOWER(REG_TOWER),
    .REG_INV  (REG_INV),
    .REG_OUT  (REG_OUT)
  ) u_mc (
    .clk     (CLK100MHZ),
    .rst_n   (rst_n),
    .col_in  (col_in),
    .col_out (col_out)
  );

  assign LED = col_out[15:0];
endmodule
