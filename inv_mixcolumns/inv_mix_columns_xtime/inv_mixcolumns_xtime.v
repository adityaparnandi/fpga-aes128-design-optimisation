`timescale 1ns/1ps

// ============================================================================
// AES Inverse MixColumns using XTIME
// ----------------------------------------------------------------------------
// Big picture:
//  - Uses repeated xtime() operations to generate x2, x4 and x8.
//  - These are combined to produce multiplication by 09, 0B, 0D and 0E.
//  - The datapath is fully pipelined to reduce combinational delay.
//  - A new 32-bit AES column can be accepted every clock cycle.
// ============================================================================
//
// Inverse MixColumns:
//
//   o0 = 0E*a ^ 0B*b ^ 0D*c ^ 09*d
//   o1 = 09*a ^ 0E*b ^ 0B*c ^ 0D*d
//   o2 = 0D*a ^ 09*b ^ 0E*c ^ 0B*d
//   o3 = 0B*a ^ 0D*b ^ 09*c ^ 0E*d
//
// Constant multiplication:
//
//   09*x = x8 ^ x
//   0B*x = x8 ^ x2 ^ x
//   0D*x = x8 ^ x4 ^ x
//   0E*x = x8 ^ x4 ^ x2
//
// Pipeline:
//   x2 -> x4 -> x8 -> partial constants -> constants -> XOR pairs -> output
// ============================================================================

module inv_mixcolumns_xtime (
    input  wire        clk,
    input  wire        en,
    input  wire [31:0] col_in,
    output wire [31:0] col_out
);

    wire [7:0] a = col_in[31:24];
    wire [7:0] b = col_in[23:16];
    wire [7:0] c = col_in[15:8];
    wire [7:0] d = col_in[7:0];


    // ------------------------------------------------------------------------
    // xtime - multiply by 02 in GF(2^8)
    // ------------------------------------------------------------------------
    function [7:0] xtime;
        input [7:0] x;
        begin
            xtime = {x[6:0], 1'b0} ^ (8'h1B & {8{x[7]}});
        end
    endfunction


    // =========================================================================
    // Pipeline 1 - x2
    // =========================================================================

    reg [7:0] a_s1, b_s1, c_s1, d_s1;
    reg [7:0] a2_s1, b2_s1, c2_s1, d2_s1;

    always @(posedge clk) begin
        if (en) begin
            a_s1 <= a;
            b_s1 <= b;
            c_s1 <= c;
            d_s1 <= d;

            a2_s1 <= xtime(a);
            b2_s1 <= xtime(b);
            c2_s1 <= xtime(c);
            d2_s1 <= xtime(d);
        end
    end


    // =========================================================================
    // Pipeline 2 - x4
    // =========================================================================

    reg [7:0] a_s2, b_s2, c_s2, d_s2;

    reg [7:0] a2_s2, b2_s2, c2_s2, d2_s2;
    reg [7:0] a4_s2, b4_s2, c4_s2, d4_s2;

    always @(posedge clk) begin
        if (en) begin
            a_s2 <= a_s1;
            b_s2 <= b_s1;
            c_s2 <= c_s1;
            d_s2 <= d_s1;

            a2_s2 <= a2_s1;
            b2_s2 <= b2_s1;
            c2_s2 <= c2_s1;
            d2_s2 <= d2_s1;

            a4_s2 <= xtime(a2_s1);
            b4_s2 <= xtime(b2_s1);
            c4_s2 <= xtime(c2_s1);
            d4_s2 <= xtime(d2_s1);
        end
    end


    // =========================================================================
    // Pipeline 3 - x8
    // =========================================================================

    reg [7:0] a_s3, b_s3, c_s3, d_s3;

    reg [7:0] a2_s3, b2_s3, c2_s3, d2_s3;
    reg [7:0] a4_s3, b4_s3, c4_s3, d4_s3;
    reg [7:0] a8_s3, b8_s3, c8_s3, d8_s3;

    always @(posedge clk) begin
        if (en) begin
            a_s3 <= a_s2;
            b_s3 <= b_s2;
            c_s3 <= c_s2;
            d_s3 <= d_s2;

            a2_s3 <= a2_s2;
            b2_s3 <= b2_s2;
            c2_s3 <= c2_s2;
            d2_s3 <= d2_s2;

            a4_s3 <= a4_s2;
            b4_s3 <= b4_s2;
            c4_s3 <= c4_s2;
            d4_s3 <= d4_s2;

            a8_s3 <= xtime(a4_s2);
            b8_s3 <= xtime(b4_s2);
            c8_s3 <= xtime(c4_s2);
            d8_s3 <= xtime(d4_s2);
        end
    end


    // =========================================================================
    // Pipeline 4 - first part of constant multiplications
    // =========================================================================

    reg [7:0] a_e_init;
    reg [7:0] b_bi_init;
    reg [7:0] c_di_init;

    reg [7:0] b_e_init;
    reg [7:0] c_bi_init;
    reg [7:0] d_di_init;

    reg [7:0] a_di_init;
    reg [7:0] c_e_init;
    reg [7:0] d_bi_init;

    reg [7:0] a_bi_init;
    reg [7:0] b_di_init;
    reg [7:0] d_e_init;

    reg [7:0] a_s4, b_s4, c_s4, d_s4;
    reg [7:0] a2_s4, b2_s4, c2_s4, d2_s4;

    reg [7:0] a9_s4;
    reg [7:0] b9_s4;
    reg [7:0] c9_s4;
    reg [7:0] d9_s4;

    always @(posedge clk) begin
        if (en) begin

            // 0E / 0B / 0D partial terms
            a_e_init  <= a8_s3 ^ a4_s3;
            b_bi_init <= b8_s3 ^ b2_s3;
            c_di_init <= c8_s3 ^ c4_s3;

            b_e_init  <= b8_s3 ^ b4_s3;
            c_bi_init <= c8_s3 ^ c2_s3;
            d_di_init <= d8_s3 ^ d4_s3;

            a_di_init <= a8_s3 ^ a4_s3;
            c_e_init  <= c8_s3 ^ c4_s3;
            d_bi_init <= d8_s3 ^ d2_s3;

            a_bi_init <= a8_s3 ^ a2_s3;
            b_di_init <= b8_s3 ^ b4_s3;
            d_e_init  <= d8_s3 ^ d4_s3;

            // Delay values needed in the next stage
            a_s4 <= a_s3;
            b_s4 <= b_s3;
            c_s4 <= c_s3;
            d_s4 <= d_s3;

            a2_s4 <= a2_s3;
            b2_s4 <= b2_s3;
            c2_s4 <= c2_s3;
            d2_s4 <= d2_s3;

            // 09*x = x8 ^ x
            a9_s4 <= a8_s3 ^ a_s3;
            b9_s4 <= b8_s3 ^ b_s3;
            c9_s4 <= c8_s3 ^ c_s3;
            d9_s4 <= d8_s3 ^ d_s3;
        end
    end


    // =========================================================================
    // Pipeline 5 - finish 09 / 0B / 0D / 0E values
    // =========================================================================

    reg [7:0] a_e,  b_bi, c_di, d_9;
    reg [7:0] a_9,  b_e,  c_bi, d_di;
    reg [7:0] a_di, b_9,  c_e,  d_bi;
    reg [7:0] a_bi, b_di, c_9,  d_e;

    always @(posedge clk) begin
        if (en) begin

            // Output byte 0 terms
            a_e  <= a_e_init ^ a2_s4;
            b_bi <= b_bi_init ^ b_s4;
            c_di <= c_di_init ^ c_s4;
            d_9  <= d9_s4;

            // Output byte 1 terms
            a_9  <= a9_s4;
            b_e  <= b_e_init ^ b2_s4;
            c_bi <= c_bi_init ^ c_s4;
            d_di <= d_di_init ^ d_s4;

            // Output byte 2 terms
            a_di <= a_di_init ^ a_s4;
            b_9  <= b9_s4;
            c_e  <= c_e_init ^ c2_s4;
            d_bi <= d_bi_init ^ d_s4;

            // Output byte 3 terms
            a_bi <= a_bi_init ^ a_s4;
            b_di <= b_di_init ^ b_s4;
            c_9  <= c9_s4;
            d_e  <= d_e_init ^ d2_s4;
        end
    end


    // =========================================================================
    // Pipeline 6 - pairwise XORs
    // =========================================================================

    reg [7:0] out0_a, out0_b;
    reg [7:0] out1_a, out1_b;
    reg [7:0] out2_a, out2_b;
    reg [7:0] out3_a, out3_b;

    always @(posedge clk) begin
        if (en) begin
            out0_a <= a_e  ^ b_bi;
            out0_b <= c_di ^ d_9;

            out1_a <= a_9  ^ b_e;
            out1_b <= c_bi ^ d_di;

            out2_a <= a_di ^ b_9;
            out2_b <= c_e  ^ d_bi;

            out3_a <= a_bi ^ b_di;
            out3_b <= c_9  ^ d_e;
        end
    end


    // =========================================================================
    // Pipeline 7 - final XOR
    // =========================================================================

    reg [7:0] out0;
    reg [7:0] out1;
    reg [7:0] out2;
    reg [7:0] out3;

    always @(posedge clk) begin
        if (en) begin
            out0 <= out0_a ^ out0_b;
            out1 <= out1_a ^ out1_b;
            out2 <= out2_a ^ out2_b;
            out3 <= out3_a ^ out3_b;
        end
    end


    assign col_out = {out0, out1, out2, out3};

endmodule