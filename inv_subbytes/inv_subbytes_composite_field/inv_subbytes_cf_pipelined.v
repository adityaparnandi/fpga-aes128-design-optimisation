`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// AES-128 InvSubBytes (inverse S-box) using Composite-Field / Tower-Field arithmetic
//
// Operation implemented:
//   InvSubBytes(x) = GFInv(InvAffine(x))
//
// Reference for forward SubBytes:
//   SubBytes(x) = Affine(GFInv(x))
//
// High-level datapath:
//   Stage 0   : optional input register
//   Stage 1   : inverse affine transform
//   Stage 2a  : isomorphic map into composite/tower field + zero detect
//   Stage 2b  : split and duplicate mapped byte into GF(16) nibble paths
//   Stage 3a  : denominator partial terms and conjugate terms
//   Stage 3b  : reduce a0*a1 and form denominator in GF(16)
//   Stage 4a  : denominator squaring chain (a^2, a^4, a^8)
//   Stage 4b  : compute a^12 = a^8 * a^4 and duplicate a^12 / a^2 operands
//   Stage 4c  : denominator inverse partial products (a^12 * a^2)
//   Stage 4d  : reduce denominator inverse and provide duplicated registered copies
//   Stage 5a  : final tower-field multiply partial products
//   Stage 5b  : reduce final multiply and pack inverse byte in tower basis
//   Stage 6   : map back to AES basis using inverse isomorphism
//   Stage 7   : optional output register
//
// Timing-oriented pipelining features:
// REG_INV_AFF matches the forward core's pipeline granularity
// REG_SPLIT reduces fanout after iso_A
// split-nibble duplication reduces routing pressure into Stage 3a
// Stage 3a is split so the a0*a1 partial-product register can be placed locally
// deninv = a^12 * a^2 is split into partial-product and reduction stages
// duplicated a^12 / a^2 source registers help rebalance local fanout
// final conj * deninv multiply is split into partial-product and reduction stages
// duplicated deninv / conjugate registers reduce routing and fanout

// All logic is algorithmic and uses composite-field arithmetic only.
// No LUT/BRAM lookup table is used except in verification.
// -----------------------------------------------------------------------------
module inv_subbytes_cf_pipelined #(
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
    input  wire       clk,
    input  wire       en,
    input  wire [7:0] in_byte,
    output wire [7:0] out_byte
);

// Inverse affine transform for AES inverse S-box, b = (s<<<1) ^ (s<<<3) ^ (s<<<6) ^ 8'h05
function automatic [7:0] inv_affine;
    input [7:0] s;
    reg [7:0] r1, r3, r6;
    begin
        r1 = {s[6:0], s[7]};
        r3 = {s[4:0], s[7:5]};
        r6 = {s[1:0], s[7:2]};
        inv_affine = r1 ^ r3 ^ r6 ^ 8'h05;
    end
endfunction

// GF(16) arithmetics, Reduction polynomial: x^4 + x + 1
function automatic [6:0] gf16_mul_pp;
    input [3:0] x;
    input [3:0] y;
    reg x0,x1,x2,x3, y0,y1,y2,y3;
    reg r0,r1,r2,r3,r4,r5,r6;
    begin
        {x3,x2,x1,x0} = x;
        {y3,y2,y1,y0} = y;

        r0 = (x0 & y0);
        r1 = (x1 & y0) ^ (x0 & y1);
        r2 = (x2 & y0) ^ (x1 & y1) ^ (x0 & y2);
        r3 = (x3 & y0) ^ (x2 & y1) ^ (x1 & y2) ^ (x0 & y3);
        r4 = (x3 & y1) ^ (x2 & y2) ^ (x1 & y3);
        r5 = (x3 & y2) ^ (x2 & y3);
        r6 = (x3 & y3);

        gf16_mul_pp = {r6,r5,r4,r3,r2,r1,r0};
    end
endfunction

function automatic [3:0] gf16_mul_red;
    input [6:0] r;
    reg r0,r1,r2,r3,r4,r5,r6;
    reg m0,m1,m2,m3;
    begin
        {r6,r5,r4,r3,r2,r1,r0} = r;

        // Reduce modulo x^4 + x + 1
        m0 = r0 ^ r4;
        m1 = r1 ^ r4 ^ r5;
        m2 = r2 ^ r5 ^ r6;
        m3 = r3 ^ r6;

        gf16_mul_red = {m3,m2,m1,m0};
    end
endfunction

function automatic [3:0] gf16_mul;
    input [3:0] x;
    input [3:0] y;
    begin
        gf16_mul = gf16_mul_red(gf16_mul_pp(x,y));
    end
endfunction

function automatic [3:0] gf16_square;
    input [3:0] a;
    reg a3,a2,a1,a0;
    begin
        {a3,a2,a1,a0} = a;
        gf16_square = {a3, (a3 ^ a1), a2, (a2 ^ a0)};
    end
endfunction

function automatic [3:0] gf16_mul_mu;
    input [3:0] a;
    reg a3,a2,a1,a0;
    begin
        {a3,a2,a1,a0} = a;
        gf16_mul_mu = { (a0 ^ a3), (a2 ^ a3), (a1 ^ a2), a1 };
    end
endfunction

// Isomorphic basis transforms
function automatic [7:0] iso_A;
    input [7:0] x;
    reg x7,x6,x5,x4,x3,x2,x1,x0;
    reg y7,y6,y5,y4,y3,y2,y1,y0;
    begin
        {x7,x6,x5,x4,x3,x2,x1,x0} = x;
        y7 = x7 ^ x5;
        y6 = x7 ^ x5 ^ x3 ^ x2;
        y5 = x7 ^ x6 ^ x4 ^ x1;
        y4 = x6 ^ x5 ^ x4;
        y3 = x4 ^ x3;
        y2 = x7 ^ x6 ^ x5 ^ x4 ^ x3 ^ x2;
        y1 = x2;
        y0 = x7 ^ x5 ^ x0;
        iso_A = {y7,y6,y5,y4,y3,y2,y1,y0};
    end
endfunction

function automatic [7:0] iso_Ainv;
    input [7:0] y;
    reg y7,y6,y5,y4,y3,y2,y1,y0;
    reg x7,x6,x5,x4,x3,x2,x1,x0;
    begin
        {y7,y6,y5,y4,y3,y2,y1,y0} = y;
        x7 = y7 ^ y6 ^ y4 ^ y2;
        x6 = y7 ^ y3 ^ y2 ^ y1;
        x5 = y6 ^ y4 ^ y2;
        x4 = y7 ^ y6 ^ y3 ^ y1;
        x3 = y7 ^ y6 ^ y1;
        x2 = y1;
        x1 = y7 ^ y5 ^ y4;
        x0 = y7 ^ y0;
        iso_Ainv = {x7,x6,x5,x4,x3,x2,x1,x0};
    end
endfunction

// Stage 0: optional input register
wire [7:0] s0_w = in_byte;
wire [7:0] s0;

generate
    if (REG_IN) begin : GEN_REG_IN
        (* shreg_extract = "no" *) reg [7:0] s0_r;
        always @(posedge clk) if (en) s0_r <= s0_w;
        assign s0 = s0_r;
    end else begin : GEN_REG_IN_BYP
        assign s0 = s0_w;
    end
endgenerate

// Stage 1: inverse affine transform
wire [7:0] s1_w = inv_affine(s0);
wire [7:0] s1;

generate
    if (REG_INV_AFF) begin : GEN_REG_INV_AFF
        (* shreg_extract = "no" *) reg [7:0] s1_r;
        always @(posedge clk) if (en) s1_r <= s1_w;
        assign s1 = s1_r;
    end else begin : GEN_REG_INV_AFF_BYP
        assign s1 = s1_w;
    end
endgenerate

// Stage 2a: map into composite/tower-field basis and detect zero
wire [7:0] s2a_t_w = iso_A(s1);
wire       s2a_z_w = (s2a_t_w == 8'h00);

wire [7:0] s2a_t;
wire       s2a_z;

generate
    if (REG_ISO) begin : GEN_REG_ISO
        (* shreg_extract = "no" *) reg [7:0] t_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            t_r <= s2a_t_w;
            z_r <= s2a_z_w;
        end
        assign s2a_t = t_r;
        assign s2a_z = z_r;
    end else begin : GEN_REG_ISO_BYP
        assign s2a_t = s2a_t_w;
        assign s2a_z = s2a_z_w;
    end
endgenerate

// Stage 2b: split mapped byte into duplicated GF(16) halves to reduce fanout
wire [3:0] s2b_a1_den_w  = s2a_t[7:4];
wire [3:0] s2b_a1_pp_w   = s2a_t[7:4];
wire [3:0] s2b_a1_conj_w = s2a_t[7:4];

wire [3:0] s2b_a0_den_w  = s2a_t[3:0];
wire [3:0] s2b_a0_pp_w   = s2a_t[3:0];
wire [3:0] s2b_a0_conj_w = s2a_t[3:0];

wire [3:0] s2b_a1_den,  s2b_a1_pp,  s2b_a1_conj;
wire [3:0] s2b_a0_den,  s2b_a0_pp,  s2b_a0_conj;
wire       s2b_z;

generate
    if (REG_SPLIT) begin : GEN_REG_SPLIT
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a1den_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a1pp_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a1conj_r;

        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a0den_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a0pp_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a0conj_r;

        (* shreg_extract = "no" *) reg z_r;

        always @(posedge clk) if (en) begin
            a1den_r  <= s2b_a1_den_w;
            a1pp_r   <= s2b_a1_pp_w;
            a1conj_r <= s2b_a1_conj_w;

            a0den_r  <= s2b_a0_den_w;
            a0pp_r   <= s2b_a0_pp_w;
            a0conj_r <= s2b_a0_conj_w;

            z_r      <= s2a_z;
        end

        assign s2b_a1_den  = a1den_r;
        assign s2b_a1_pp   = a1pp_r;
        assign s2b_a1_conj = a1conj_r;

        assign s2b_a0_den  = a0den_r;
        assign s2b_a0_pp   = a0pp_r;
        assign s2b_a0_conj = a0conj_r;

        assign s2b_z       = z_r;
    end else begin : GEN_REG_SPLIT_BYP
        assign s2b_a1_den  = s2b_a1_den_w;
        assign s2b_a1_pp   = s2b_a1_pp_w;
        assign s2b_a1_conj = s2b_a1_conj_w;

        assign s2b_a0_den  = s2b_a0_den_w;
        assign s2b_a0_pp   = s2b_a0_pp_w;
        assign s2b_a0_conj = s2b_a0_conj_w;

        assign s2b_z       = s2a_z;
    end
endgenerate

// Stage 3a: denominator partial terms and conjugate terms
wire [3:0] s3a_a0_sq_w   = gf16_square(s2b_a0_den);
wire [3:0] s3a_a1_sq_w   = gf16_square(s2b_a1_den);
wire [3:0] s3a_mu_a1sq_w = gf16_mul_mu(s3a_a1_sq_w);
wire [6:0] s3a_a0a1_pp_w = gf16_mul_pp(s2b_a0_pp, s2b_a1_pp);

wire [3:0] s3a_conj1_w = s2b_a1_conj;
wire [3:0] s3a_conj0_w = s2b_a0_conj ^ s2b_a1_conj;

wire [3:0] s3a_a0_sq, s3a_a1_sq, s3a_mu_a1sq;
wire [6:0] s3a_a0a1_pp;
wire [3:0] s3a_conj1, s3a_conj0;
wire       s3a_z;

// Stage 3a misc register bank
generate
    if (REG_DEN) begin : GEN_REG_DEN_MISC
        (* shreg_extract = "no" *) reg [3:0] a0sq_r, a1sq_r, mu_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            a0sq_r <= s3a_a0_sq_w;
            a1sq_r <= s3a_a1_sq_w;
            mu_r   <= s3a_mu_a1sq_w;
            c1_r   <= s3a_conj1_w;
            c0_r   <= s3a_conj0_w;
            z_r    <= s2b_z;
        end
        assign s3a_a0_sq   = a0sq_r;
        assign s3a_a1_sq   = a1sq_r;
        assign s3a_mu_a1sq = mu_r;
        assign s3a_conj1   = c1_r;
        assign s3a_conj0   = c0_r;
        assign s3a_z       = z_r;
    end else begin : GEN_REG_DEN_MISC_BYP
        assign s3a_a0_sq   = s3a_a0_sq_w;
        assign s3a_a1_sq   = s3a_a1_sq_w;
        assign s3a_mu_a1sq = s3a_mu_a1sq_w;
        assign s3a_conj1   = s3a_conj1_w;
        assign s3a_conj0   = s3a_conj0_w;
        assign s3a_z       = s2b_z;
    end
endgenerate

// Stage 3a pp-only register bank
generate
    if (REG_DEN) begin : GEN_REG_DEN_PP
        (* shreg_extract = "no" *) reg [3:0] pp_lo_r;
        (* shreg_extract = "no" *) reg [2:0] pp_hi_r;
        always @(posedge clk) if (en) begin
            pp_lo_r <= s3a_a0a1_pp_w[3:0];
            pp_hi_r <= s3a_a0a1_pp_w[6:4];
        end
        assign s3a_a0a1_pp = {pp_hi_r, pp_lo_r};
    end else begin : GEN_REG_DEN_PP_BYP
        assign s3a_a0a1_pp = s3a_a0a1_pp_w;
    end
endgenerate

// Stage 3b: reduce a0*a1 and form denominator
wire [3:0] s3b_a0a1_w = gf16_mul_red(s3a_a0a1_pp);
wire [3:0] s3b_den_w  = s3a_a0_sq ^ s3b_a0a1_w ^ s3a_mu_a1sq;

wire [3:0] s3b_den, s3b_conj1, s3b_conj0;
wire       s3b_z;

generate
    if (REG_DEN2) begin : GEN_REG_DEN2
        (* shreg_extract = "no" *) reg [3:0] den_r, c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            den_r <= s3b_den_w;
            c1_r  <= s3a_conj1;
            c0_r  <= s3a_conj0;
            z_r   <= s3a_z;
        end
        assign s3b_den   = den_r;
        assign s3b_conj1 = c1_r;
        assign s3b_conj0 = c0_r;
        assign s3b_z     = z_r;
    end else begin : GEN_REG_DEN2_BYP
        assign s3b_den   = s3b_den_w;
        assign s3b_conj1 = s3a_conj1;
        assign s3b_conj0 = s3a_conj0;
        assign s3b_z     = s3a_z;
    end
endgenerate

// Stage 4a: denominator squaring chain
wire [3:0] s4a_a2_w = gf16_square(s3b_den);
wire [3:0] s4a_a4_w = gf16_square(s4a_a2_w);
wire [3:0] s4a_a8_w = gf16_square(s4a_a4_w);

wire [3:0] s4a_a2, s4a_a4, s4a_a8;
wire [3:0] s4a_conj1, s4a_conj0;
wire       s4a_z;

generate
    if (REG_DENINV_SQ) begin : GEN_REG_DENINV_SQ
        (* shreg_extract = "no" *) reg [3:0] a2_r, a4_r, a8_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            a2_r <= s4a_a2_w;
            a4_r <= s4a_a4_w;
            a8_r <= s4a_a8_w;
            c1_r <= s3b_conj1;
            c0_r <= s3b_conj0;
            z_r  <= s3b_z;
        end
        assign s4a_a2    = a2_r;
        assign s4a_a4    = a4_r;
        assign s4a_a8    = a8_r;
        assign s4a_conj1 = c1_r;
        assign s4a_conj0 = c0_r;
        assign s4a_z     = z_r;
    end else begin : GEN_REG_DENINV_SQ_BYP
        assign s4a_a2    = s4a_a2_w;
        assign s4a_a4    = s4a_a4_w;
        assign s4a_a8    = s4a_a8_w;
        assign s4a_conj1 = s3b_conj1;
        assign s4a_conj0 = s3b_conj0;
        assign s4a_z     = s3b_z;
    end
endgenerate

// Stage 4b: compute a12 = a8 * a4 and carry duplicated a2 forward
wire [3:0] s4b_a12_w = gf16_mul(s4a_a8, s4a_a4);

wire [3:0] s4b_a12_a, s4b_a12_b;
wire [3:0] s4b_a2_a,  s4b_a2_b;
wire [3:0] s4b_conj1, s4b_conj0;
wire       s4b_z;

generate
    if (REG_DENINV_M1) begin : GEN_REG_DENINV_M1
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a12a_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a12b_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a2a_r;
        (* shreg_extract = "no", keep = "true", equivalent_register_removal = "no", max_fanout = 2 *) reg [3:0] a2b_r;

        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;

        always @(posedge clk) if (en) begin
            a12a_r <= s4b_a12_w;
            a12b_r <= s4b_a12_w;
            a2a_r  <= s4a_a2;
            a2b_r  <= s4a_a2;
            c1_r   <= s4a_conj1;
            c0_r   <= s4a_conj0;
            z_r    <= s4a_z;
        end

        assign s4b_a12_a = a12a_r;
        assign s4b_a12_b = a12b_r;
        assign s4b_a2_a  = a2a_r;
        assign s4b_a2_b  = a2b_r;
        assign s4b_conj1 = c1_r;
        assign s4b_conj0 = c0_r;
        assign s4b_z     = z_r;
    end else begin : GEN_REG_DENINV_M1_BYP
        assign s4b_a12_a = s4b_a12_w;
        assign s4b_a12_b = s4b_a12_w;
        assign s4b_a2_a  = s4a_a2;
        assign s4b_a2_b  = s4a_a2;
        assign s4b_conj1 = s4a_conj1;
        assign s4b_conj0 = s4a_conj0;
        assign s4b_z     = s4a_z;
    end
endgenerate

// Stage 4c: denominator inverse partial products
wire [6:0] s4c_deninv_pp_a_w = gf16_mul_pp(s4b_a12_a, s4b_a2_a);
wire [6:0] s4c_deninv_pp_b_w = gf16_mul_pp(s4b_a12_b, s4b_a2_b);

wire [6:0] s4c_deninv_pp_a, s4c_deninv_pp_b;
wire [3:0] s4c_conj1, s4c_conj0;
wire       s4c_z;

generate
    if (REG_DENINV_PP) begin : GEN_REG_DENINV_PP
        (* shreg_extract = "no", keep = "true", dont_touch = "true" *) reg [6:0] pp_a_r, pp_b_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            pp_a_r <= s4c_deninv_pp_a_w;
            pp_b_r <= s4c_deninv_pp_b_w;
            c1_r   <= s4b_conj1;
            c0_r   <= s4b_conj0;
            z_r    <= s4b_z;
        end
        assign s4c_deninv_pp_a = pp_a_r;
        assign s4c_deninv_pp_b = pp_b_r;
        assign s4c_conj1       = c1_r;
        assign s4c_conj0       = c0_r;
        assign s4c_z           = z_r;
    end else begin : GEN_REG_DENINV_PP_BYP
        assign s4c_deninv_pp_a = s4c_deninv_pp_a_w;
        assign s4c_deninv_pp_b = s4c_deninv_pp_b_w;
        assign s4c_conj1       = s4b_conj1;
        assign s4c_conj0       = s4b_conj0;
        assign s4c_z           = s4b_z;
    end
endgenerate

// Stage 4d: reduce denominator inverse and duplicate registered copies
wire [3:0] s4d_deninv_a_w = gf16_mul_red(s4c_deninv_pp_a);
wire [3:0] s4d_deninv_b_w = gf16_mul_red(s4c_deninv_pp_b);

wire [3:0] s4d_deninv_main, s4d_conj1, s4d_conj0;
wire       s4d_z;

generate
    if (REG_DENINV) begin : GEN_REG_DENINV
        (* shreg_extract = "no", keep = "true", dont_touch = "true" *) reg [3:0] di_r, di2_r;
        (* shreg_extract = "no", keep = "true", dont_touch = "true" *) reg [3:0] c1a_r, c1b_r, c0a_r, c0b_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            di_r  <= s4d_deninv_a_w;
            di2_r <= s4d_deninv_b_w;

            c1a_r <= s4c_conj1;
            c1b_r <= s4c_conj1;
            c0a_r <= s4c_conj0;
            c0b_r <= s4c_conj0;

            z_r   <= s4c_z;
        end
        assign s4d_deninv_main = di_r;
        assign s4d_conj1       = c1a_r;
        assign s4d_conj0       = c0a_r;
        assign s4d_z           = z_r;
    end else begin : GEN_REG_DENINV_BYP
        assign s4d_deninv_main = s4d_deninv_a_w;
        assign s4d_conj1       = s4c_conj1;
        assign s4d_conj0       = s4c_conj0;
        assign s4d_z           = s4c_z;
    end
endgenerate

// Two registered copies of deninv are provided to reduce fanout/routing load.
wire [3:0] s4d_deninv_a;
wire [3:0] s4d_deninv_b;
wire [3:0] s4d_conj1_use;
wire [3:0] s4d_conj0_use;

generate
    if (REG_DENINV && REG_DENINV_DUP) begin : GEN_DENINV_DUP
        assign s4d_deninv_a  = GEN_REG_DENINV.di_r;
        assign s4d_deninv_b  = GEN_REG_DENINV.di2_r;
        assign s4d_conj1_use = GEN_REG_DENINV.c1a_r;
        assign s4d_conj0_use = GEN_REG_DENINV.c0b_r;
    end else begin : GEN_DENINV_DUP_BYP
        assign s4d_deninv_a  = s4d_deninv_main;
        assign s4d_deninv_b  = s4d_deninv_main;
        assign s4d_conj1_use = s4d_conj1;
        assign s4d_conj0_use = s4d_conj0;
    end
endgenerate

// Stage 5a: final tower-field multiply partial products
wire [6:0] s5a_pp1_w = s4d_z ? 7'b0 : gf16_mul_pp(s4d_conj1_use, s4d_deninv_a);
wire [6:0] s5a_pp0_w = s4d_z ? 7'b0 : gf16_mul_pp(s4d_conj0_use, s4d_deninv_b);

wire [6:0] s5a_pp1, s5a_pp0;
wire       s5a_z;

generate
    if (REG_MUL_PP) begin : GEN_REG_MUL_PP
        (* shreg_extract = "no" *) reg [6:0] pp1_r, pp0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            pp1_r <= s5a_pp1_w;
            pp0_r <= s5a_pp0_w;
            z_r   <= s4d_z;
        end
        assign s5a_pp1 = pp1_r;
        assign s5a_pp0 = pp0_r;
        assign s5a_z   = z_r;
    end else begin : GEN_REG_MUL_PP_BYP
        assign s5a_pp1 = s5a_pp1_w;
        assign s5a_pp0 = s5a_pp0_w;
        assign s5a_z   = s4d_z;
    end
endgenerate

// Stage 5b: reduce final multiply and pack byte in tower basis
wire [3:0] s5b_c1_w = s5a_z ? 4'h0 : gf16_mul_red(s5a_pp1);
wire [3:0] s5b_c0_w = s5a_z ? 4'h0 : gf16_mul_red(s5a_pp0);
wire [7:0] s5b_t_w  = {s5b_c1_w, s5b_c0_w};

wire [7:0] s5b_t;

generate
    if (REG_MUL) begin : GEN_REG_MUL
        (* shreg_extract = "no" *) reg [7:0] t_r;
        always @(posedge clk) if (en) t_r <= s5b_t_w;
        assign s5b_t = t_r;
    end else begin : GEN_REG_MUL_BYP
        assign s5b_t = s5b_t_w;
    end
endgenerate

// Stage 6: map back from composite/tower-field basis to AES basis
wire [7:0] s6_w = iso_Ainv(s5b_t);
wire [7:0] s6;

generate
    if (REG_OUT) begin : GEN_REG_OUT
        (* shreg_extract = "no" *) reg [7:0] out_r;
        always @(posedge clk) if (en) out_r <= s6_w;
        assign s6 = out_r;
    end else begin : GEN_REG_OUT_BYP
        assign s6 = s6_w;
    end
endgenerate

assign out_byte = s6;

endmodule