`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// AES-128 SubBytes (forward S-box) using Composite-Field / Tower-Field arithmetic
//
// Operation implemented:
//   SubBytes(x) = Affine(GFInv(x))
//
// Reference for inverse SubBytes:
//   InvSubBytes(x) = GFInv(InvAffine(x))
//
// Brief working:
//   1. Map the 8-bit AES input byte into the composite/tower-field basis using iso_A().
//   2. Split the mapped byte into two GF(16) nibbles.
//   3. Compute the multiplicative inverse in composite field form using denominator/conjugate operations in GF(16).
//   4. Map the inverse byte back into the AES basis using iso_Ainv().
//   5. Apply the forward affine transform to produce the AES S-box output.
//
// Timing-driven improvements included (to reduce logic depth, fanout and Vivado routing on long datapaths):
//   - pipelined a0*a1 in the denominator path
//   - added REG_SPLIT after iso_A to reduce fanout
//   - pipelined deninv = a12 * a2 as: partial products -> register -> reduction
//   - pipelined the final tower multiply conj*deninv as: partial products -> register -> reduction
//   - duplicated the deninv register in GEN_REG_DENINV to reduce fanout
//   - duplicated the deninv partial-product register in GEN_REG_DENINV_PP to reduce routing into di_r/di2_r
//   - duplicated the conj registers before the final multiply to reduce routing into the pp1/pp0 cones
//
// All logic is algorithmic and uses composite-field arithmetic only.
// No LUT/BRAM lookup table is used, to keep comparison fair against the LUT-based SubBytes implementation.
// -----------------------------------------------------------------------------
module subbytes_cf_pipelined #(
    parameter integer REG_IN         = 1,
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
    parameter integer REG_AFF        = 1,
    parameter integer REG_OUT        = 1
)(
    input  wire       clk,
    input  wire       en,
    input  wire [7:0] in_byte,
    output wire [7:0] out_byte
);

// Forward affine transform:
// s = b ^ (b<<<1) ^ (b<<<2) ^ (b<<<3) ^ (b<<<4) ^ 8'h63
function automatic [7:0] fwd_affine;
    input [7:0] b;
    reg [7:0] r1, r2, r3, r4;
    begin
        r1 = {b[6:0], b[7]};
        r2 = {b[5:0], b[7:6]};
        r3 = {b[4:0], b[7:5]};
        r4 = {b[3:0], b[7:4]};
        fwd_affine = b ^ r1 ^ r2 ^ r3 ^ r4 ^ 8'h63;
    end
endfunction

// GF(16) multiply split: partial products + reduction
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

        // reduce modulo x^4 + x + 1
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

// Isomorphisms
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

// Stage 0: input stage
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

// Stage 1a: iso_A + zero detect
wire [7:0] t1_w = iso_A(s0);
wire       z1_w = (t1_w == 8'h00);

wire [7:0] t1;
wire       z1;
generate
    if (REG_ISO) begin : GEN_REG_ISO
        (* shreg_extract = "no" *) reg [7:0] t1_r;
        (* shreg_extract = "no" *) reg       z1_r;
        always @(posedge clk) if (en) begin
            t1_r <= t1_w;
            z1_r <= z1_w;
        end
        assign t1 = t1_r;
        assign z1 = z1_r;
    end else begin : GEN_REG_ISO_BYP
        assign t1 = t1_w;
        assign z1 = z1_w;
    end
endgenerate

// Stage 1b: split nibbles to reduce fanout
wire [3:0] a1_s_w = t1[7:4];
wire [3:0] a0_s_w = t1[3:0];

wire [3:0] a1_s, a0_s;
wire       z1s;
generate
    if (REG_SPLIT) begin : GEN_REG_SPLIT
        (* shreg_extract = "no" *) reg [3:0] a1_r, a0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            a1_r <= a1_s_w;
            a0_r <= a0_s_w;
            z_r  <= z1;
        end
        assign a1_s = a1_r;
        assign a0_s = a0_r;
        assign z1s  = z_r;
    end else begin : GEN_REG_SPLIT_BYP
        assign a1_s = a1_s_w;
        assign a0_s = a0_s_w;
        assign z1s  = z1;
    end
endgenerate

// Stage 2A: denominator partials + conjugate + pipelined a0*a1
wire [3:0] a0_sq_2a_w   = gf16_square(a0_s);
wire [3:0] a1_sq_2a_w   = gf16_square(a1_s);
wire [3:0] mu_a1sq_2a_w = gf16_mul_mu(a1_sq_2a_w);
wire [6:0] a0a1_pp_2a_w = gf16_mul_pp(a0_s, a1_s);

wire [3:0] conj1_2a_w = a1_s;
wire [3:0] conj0_2a_w = a0_s ^ a1_s;

wire [3:0] a0_sq_2a, a1_sq_2a, mu_a1sq_2a;
wire [6:0] a0a1_pp_2a;
wire [3:0] conj1_2a, conj0_2a;
wire       z2a;
generate
    if (REG_DEN) begin : GEN_REG_DEN
        (* shreg_extract = "no" *) reg [3:0] a0sq_r, a1sq_r, mu_r;
        (* shreg_extract = "no" *) reg [6:0] pp_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            a0sq_r <= a0_sq_2a_w;
            a1sq_r <= a1_sq_2a_w;
            mu_r   <= mu_a1sq_2a_w;
            pp_r   <= a0a1_pp_2a_w;
            c1_r   <= conj1_2a_w;
            c0_r   <= conj0_2a_w;
            z_r    <= z1s;
        end
        assign a0_sq_2a   = a0sq_r;
        assign a1_sq_2a   = a1sq_r;
        assign mu_a1sq_2a = mu_r;
        assign a0a1_pp_2a = pp_r;
        assign conj1_2a   = c1_r;
        assign conj0_2a   = c0_r;
        assign z2a        = z_r;
    end else begin : GEN_REG_DEN_BYP
        assign a0_sq_2a   = a0_sq_2a_w;
        assign a1_sq_2a   = a1_sq_2a_w;
        assign mu_a1sq_2a = mu_a1sq_2a_w;
        assign a0a1_pp_2a = a0a1_pp_2a_w;
        assign conj1_2a   = conj1_2a_w;
        assign conj0_2a   = conj0_2a_w;
        assign z2a        = z1s;
    end
endgenerate

// Stage 2B: reduce a0a1 and form denominator
wire [3:0] a0a1_2b_w = gf16_mul_red(a0a1_pp_2a);
wire [3:0] den2_w    = a0_sq_2a ^ a0a1_2b_w ^ mu_a1sq_2a;

wire [3:0] den2, conj1_2, conj0_2;
wire       z2;
generate
    if (REG_DEN2) begin : GEN_REG_DEN2
        (* shreg_extract = "no" *) reg [3:0] den_r, c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            den_r <= den2_w;
            c1_r  <= conj1_2a;
            c0_r  <= conj0_2a;
            z_r   <= z2a;
        end
        assign den2    = den_r;
        assign conj1_2 = c1_r;
        assign conj0_2 = c0_r;
        assign z2      = z_r;
    end else begin : GEN_REG_DEN2_BYP
        assign den2    = den2_w;
        assign conj1_2 = conj1_2a;
        assign conj0_2 = conj0_2a;
        assign z2      = z2a;
    end
endgenerate

// Stage 3A: den^2, den^4, den^8
wire [3:0] den_a2_w = gf16_square(den2);
wire [3:0] den_a4_w = gf16_square(den_a2_w);
wire [3:0] den_a8_w = gf16_square(den_a4_w);

wire [3:0] den_a2, den_a4, den_a8;
wire [3:0] conj1_3a, conj0_3a;
wire       z3a;
generate
    if (REG_DENINV_SQ) begin : GEN_REG_DENINV_SQ
        (* shreg_extract = "no" *) reg [3:0] a2_r, a4_r, a8_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            a2_r <= den_a2_w;
            a4_r <= den_a4_w;
            a8_r <= den_a8_w;
            c1_r <= conj1_2;
            c0_r <= conj0_2;
            z_r  <= z2;
        end
        assign den_a2   = a2_r;
        assign den_a4   = a4_r;
        assign den_a8   = a8_r;
        assign conj1_3a = c1_r;
        assign conj0_3a = c0_r;
        assign z3a      = z_r;
    end else begin : GEN_REG_DENINV_SQ_BYP
        assign den_a2   = den_a2_w;
        assign den_a4   = den_a4_w;
        assign den_a8   = den_a8_w;
        assign conj1_3a = conj1_2;
        assign conj0_3a = conj0_2;
        assign z3a      = z2;
    end
endgenerate

// Stage 3B: a12 = a8 * a4
wire [3:0] den_a12_w = gf16_mul(den_a8, den_a4);

wire [3:0] den_a12, den_a2_d;
wire [3:0] conj1_3b, conj0_3b;
wire       z3b;
generate
    if (REG_DENINV_M1) begin : GEN_REG_DENINV_M1
        (* shreg_extract = "no" *) reg [3:0] a12_r, a2_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            a12_r <= den_a12_w;
            a2_r  <= den_a2;
            c1_r  <= conj1_3a;
            c0_r  <= conj0_3a;
            z_r   <= z3a;
        end
        assign den_a12  = a12_r;
        assign den_a2_d = a2_r;
        assign conj1_3b = c1_r;
        assign conj0_3b = c0_r;
        assign z3b      = z_r;
    end else begin : GEN_REG_DENINV_M1_BYP
        assign den_a12  = den_a12_w;
        assign den_a2_d = den_a2;
        assign conj1_3b = conj1_3a;
        assign conj0_3b = conj0_3a;
        assign z3b      = z3a;
    end
endgenerate

// Stage 3C: deninv partial products = a12 * a2
wire [6:0] deninv_pp_w = gf16_mul_pp(den_a12, den_a2_d);

wire [6:0] deninv_pp_a, deninv_pp_b;
wire [3:0] conj1_3c, conj0_3c;
wire       z3c;
generate
    if (REG_DENINV_PP) begin : GEN_REG_DENINV_PP
        (* shreg_extract = "no", keep = "true", dont_touch = "true" *) reg [6:0] pp_a_r, pp_b_r;
        (* shreg_extract = "no" *) reg [3:0] c1_r, c0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            pp_a_r <= deninv_pp_w;
            pp_b_r <= deninv_pp_w;
            c1_r   <= conj1_3b;
            c0_r   <= conj0_3b;
            z_r    <= z3b;
        end
        assign deninv_pp_a = pp_a_r;
        assign deninv_pp_b = pp_b_r;
        assign conj1_3c    = c1_r;
        assign conj0_3c    = c0_r;
        assign z3c         = z_r;
    end else begin : GEN_REG_DENINV_PP_BYP
        assign deninv_pp_a = deninv_pp_w;
        assign deninv_pp_b = deninv_pp_w;
        assign conj1_3c    = conj1_3b;
        assign conj0_3c    = conj0_3b;
        assign z3c         = z3b;
    end
endgenerate

// Stage 3D: deninv = reduce(a12 * a2)
// Duplicated deninv registers are preserved for routing/fanout reduction.
wire [3:0] deninv3_a_w = gf16_mul_red(deninv_pp_a);
wire [3:0] deninv3_b_w = gf16_mul_red(deninv_pp_b);

wire [3:0] deninv3_main, conj1_3, conj0_3;
wire       z3;
generate
    if (REG_DENINV) begin : GEN_REG_DENINV
        (* shreg_extract = "no", keep = "true", dont_touch = "true" *) reg [3:0] di_r, di2_r;
        (* shreg_extract = "no", keep = "true", dont_touch = "true" *) reg [3:0] c1a_r, c1b_r, c0a_r, c0b_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            di_r  <= deninv3_a_w;
            di2_r <= deninv3_b_w;

            c1a_r <= conj1_3c;
            c1b_r <= conj1_3c;
            c0a_r <= conj0_3c;
            c0b_r <= conj0_3c;

            z_r   <= z3c;
        end
        assign deninv3_main = di_r;
        assign conj1_3      = c1a_r;
        assign conj0_3      = c0a_r;
        assign z3           = z_r;
    end else begin : GEN_REG_DENINV_BYP
        assign deninv3_main = deninv3_a_w;
        assign conj1_3      = conj1_3c;
        assign conj0_3      = conj0_3c;
        assign z3           = z3c;
    end
endgenerate

// Provide two deninv copies to the final multipliers.
// When REG_DENINV_DUP = 1, duplicated registers are used to reduce fanout/routing load.
wire [3:0] deninv3_a;
wire [3:0] deninv3_b;
wire [3:0] conj1_4a;
wire [3:0] conj0_4a;
generate
    if (REG_DENINV && REG_DENINV_DUP) begin : GEN_DENINV_DUP
        assign deninv3_a = GEN_REG_DENINV.di_r;
        assign deninv3_b = GEN_REG_DENINV.di2_r;

        assign conj1_4a  = GEN_REG_DENINV.c1a_r;
        assign conj0_4a  = GEN_REG_DENINV.c0b_r;
    end else begin : GEN_DENINV_DUP_BYP
        assign deninv3_a = deninv3_main;
        assign deninv3_b = deninv3_main;
        assign conj1_4a  = conj1_3;
        assign conj0_4a  = conj0_3;
    end
endgenerate

// Stage 4A: partial products for conj*deninv
wire [6:0] pp1_4a_w = z3 ? 7'b0 : gf16_mul_pp(conj1_4a, deninv3_a);
wire [6:0] pp0_4a_w = z3 ? 7'b0 : gf16_mul_pp(conj0_4a, deninv3_b);

wire [6:0] pp1_4a, pp0_4a;
wire       z4a;
generate
    if (REG_MUL_PP) begin : GEN_REG_MUL_PP
        (* shreg_extract = "no" *) reg [6:0] pp1_r, pp0_r;
        (* shreg_extract = "no" *) reg       z_r;
        always @(posedge clk) if (en) begin
            pp1_r <= pp1_4a_w;
            pp0_r <= pp0_4a_w;
            z_r   <= z3;
        end
        assign pp1_4a = pp1_r;
        assign pp0_4a = pp0_r;
        assign z4a    = z_r;
    end else begin : GEN_REG_MUL_PP_BYP
        assign pp1_4a = pp1_4a_w;
        assign pp0_4a = pp0_4a_w;
        assign z4a    = z3;
    end
endgenerate

// Stage 4B: reduce partial products to nibbles and pack the tower inverse
wire [3:0] c1_4b_w = z4a ? 4'h0 : gf16_mul_red(pp1_4a);
wire [3:0] c0_4b_w = z4a ? 4'h0 : gf16_mul_red(pp0_4a);
wire [7:0] t4_w    = {c1_4b_w, c0_4b_w};

wire [7:0] t4;
generate
    if (REG_MUL) begin : GEN_REG_MUL
        (* shreg_extract = "no" *) reg [7:0] t4_r;
        always @(posedge clk) if (en) t4_r <= t4_w;
        assign t4 = t4_r;
    end else begin : GEN_REG_MUL_BYP
        assign t4 = t4_w;
    end
endgenerate

// Stage 5: map the composite-field inverse back to the AES basis
wire [7:0] inv5_w = iso_Ainv(t4);

wire [7:0] inv5;
generate
    if (REG_AFF) begin : GEN_REG_INV_AES
        (* shreg_extract = "no" *) reg [7:0] inv_r;
        always @(posedge clk) if (en) inv_r <= inv5_w;
        assign inv5 = inv_r;
    end else begin : GEN_REG_INV_AES_BYP
        assign inv5 = inv5_w;
    end
endgenerate

// Stage 6: forward affine for the final S-box
wire [7:0] s6_w = fwd_affine(inv5);

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