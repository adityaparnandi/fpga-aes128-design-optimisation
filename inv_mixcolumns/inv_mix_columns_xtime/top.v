`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// top.v
// ----------------------------------------------------------------------------
// Wrapper used for synthesis / implementation timing of inv_mixcolumns_xtime.
// ----------------------------------------------------------------------------

module top (
    input  wire        clk,
    input  wire        en,
    input  wire [31:0] col_in,
    output wire [31:0] col_out
);

    inv_mixcolumns_xtime u_inv_mixcolumns (
        .clk     (clk),
        .en      (en),
        .col_in  (col_in),
        .col_out (col_out)
    );

endmodule