`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// top.v (Nexys4 DDR-style)
// - Ports match: CLK100MHZ, BTNC, SW[15:0], LED[15:0]
// - Works with: create_clock ... [get_ports CLK100MHZ]
// - Configurable wrapper pipelining via parameters REG_IN / REG_OUT
// -----------------------------------------------------------------------------
module top #(
    parameter integer REG_IN  = 1,  // 1 = register input column
    parameter integer REG_OUT = 0   // 1 = register output (adds extra stage)
)(
    input  wire        CLK100MHZ,
    input  wire        BTNC,      // active-high reset button
    input  wire [15:0] SW,
    output wire [15:0] LED
);

    wire rst = BTNC;

    // Build a 32-bit column from switches (simple demo stimulus)
    wire [31:0] col_in_raw = {SW, SW};

    // --------------------------
    // Optional input register
    // --------------------------
    wire [31:0] col_in_core;
    generate
        if (REG_IN) begin : GEN_REG_IN
            reg [31:0] col_in_r;
            always @(posedge CLK100MHZ) begin
                if (rst)
                    col_in_r <= 32'h0;
                else
                    col_in_r <= col_in_raw;
            end
            assign col_in_core = col_in_r;
        end else begin : GEN_NO_REG_IN
            assign col_in_core = col_in_raw;
        end
    endgenerate

    // --------------------------
    // Inverse MixColumns core
    // (your pipelined inverseMixcomposite module)
    // --------------------------
    wire [31:0] col_out_core;

    inverseMixcomposite u_inv_mc (
        .clk     (CLK100MHZ),
        .en      (1'b1),
        .col_in  (col_in_core),
        .col_out (col_out_core)
    );

    // --------------------------
    // Optional output register
    // --------------------------
    wire [31:0] col_out_final;
    generate
        if (REG_OUT) begin : GEN_REG_OUT
            reg [31:0] col_out_r;
            always @(posedge CLK100MHZ) begin
                if (rst)
                    col_out_r <= 32'h0;
                else
                    col_out_r <= col_out_core;
            end
            assign col_out_final = col_out_r;
        end else begin : GEN_NO_REG_OUT
            assign col_out_final = col_out_core;
        end
    endgenerate

    // Display lower 16 bits on LEDs
    assign LED = col_out_final[15:0];

endmodule
