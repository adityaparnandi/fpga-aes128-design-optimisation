// ============================================================================
// AES MixColumns using COMPOSITE-FIELD arithmetic
// ----------------------------------------------------------------------------
// Big picture:
//  - We implement GF(2^8) multiplication by mapping bytes into a tower field
//    GF((2^4)^2), multiplying there, then mapping back.
//  - All math is XOR/AND combinational logic (no tables, no xtime).
//  - Parameters are used to control pipelining.
// ============================================================================

`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// GF(2^4) core with irreducible polynomial p(t) = t^4 + t + 1  (0x13)
// ----------------------------------------------------------------------------

// Addition in GF(2^4) is bitwise XOR (since coefficients are mod-2)
function [3:0] gf16_add;
  input [3:0] x, y;
  begin
    gf16_add = x ^ y; // XOR is + in GF(2)
  end
endfunction

// Multiplication in GF(2^4) modulo p(t) = t^4 + t + 1
function [3:0] gf16_mul;
  input [3:0] x, y;   // x = x3 t^3 + ... + x0; y = y3 t^3 + ... + y0
  // Declare temporaries as 1-bit regs (Verilog-2001 requirement)
  reg x0,x1,x2,x3, y0,y1,y2,y3;
  // r0..r6 are coefficients of the UNREDUCED product (degree up to 6)
  reg r0,r1,r2,r3,r4,r5,r6;
  // m0..m3 will be the REDUCED coefficients (degree 0..3)
  reg m0,m1,m2,m3;
  begin
    // Concatenation assignment: split the 4-bit vector into individual bits
    // {x3,x2,x1,x0} = x means x3=x[3], x2=x[2], ...
    {x3,x2,x1,x0} = x;
    {y3,y2,y1,y0} = y;

    // Polynomial multiply over GF(2):
    // AND = multiply coefficients; XOR = sum coefficients mod-2.
    r0 = (x0 & y0);                                      // coeff of t^0
    r1 = (x1 & y0) ^ (x0 & y1);                          // coeff of t^1
    r2 = (x2 & y0) ^ (x1 & y1) ^ (x0 & y2);              // coeff of t^2
    r3 = (x3 & y0) ^ (x2 & y1) ^ (x1 & y2) ^ (x0 & y3);  // coeff of t^3
    r4 = (x3 & y1) ^ (x2 & y2) ^ (x1 & y3);              // coeff of t^4
    r5 = (x3 & y2) ^ (x2 & y3);                          // coeff of t^5
    r6 = (x3 & y3);                                      // coeff of t^6

    // Reduction modulo t^4 + t + 1:
    // Replace high-degree terms using:
    //   t^4 ≡ t + 1
    //   t^5 ≡ t^2 + t
    //   t^6 ≡ t^3 + t^2
    // Fold r4,r5,r6 down into degrees 0..3 accordingly.
    m0 = r0 ^ r4;            // deg0: r0 + r4
    m1 = r1 ^ r4 ^ r5;       // deg1: r1 + r4 + r5
    m2 = r2 ^ r5 ^ r6;       // deg2: r2 + r5 + r6
    m3 = r3 ^ r6;            // deg3: r3 + r6

    gf16_mul = {m3,m2,m1,m0}; // pack back to nibble (MSB..LSB)
  end
endfunction

// ----------------------------------------------------------------------------
// Tower-field multiply in GF((2^4)^2) with relation v^2 = v + MU
// Represent a byte as a' = a0 + a1*v, b' = b0 + b1*v with a0,a1,b0,b1 ∈ GF(2^4)
// Product: a'*b' = (a0*b0 + MU*(a1*b1)) + (a0*b1 + a1*b0 + a1*b1)*v
// ----------------------------------------------------------------------------
function [7:0] gf_tower_mul;
  input [3:0] a1, a0;  // tower components of 'a'  (a' = a0 + a1*v)
  input [3:0] b1, b0;  // tower components of 'b'  (b' = b0 + b1*v)
  input [3:0] MU;      // tower constant μ in GF(2^4)
  reg [3:0] a0b0, a1b1, a0b1, a1b0;
  reg [3:0] mu_a1b1;
  reg [3:0] c0, c1;
  begin
    // Four GF(2^4) sub-products (calls the 4-bit multiplier above)
    a0b0    = gf16_mul(a0, b0);
    a1b1    = gf16_mul(a1, b1);
    a0b1    = gf16_mul(a0, b1);
    a1b0    = gf16_mul(a1, b0);
    mu_a1b1 = gf16_mul(MU, a1b1); // μ*(a1*b1)

    // Apply the tower-field product identities:
    c0 = gf16_add(a0b0, mu_a1b1);                  // c0 = a0b0 + μ·a1b1
    c1 = gf16_add(gf16_add(a0b1, a1b0), a1b1);     // c1 = a0b1 + a1b0 + a1b1

    gf_tower_mul = {c1, c0}; // pack as {high nibble, low nibble}
  end
endfunction

// ----------------------------------------------------------------------------
// Linear isomorphisms between AES basis (byte) and tower basis ({x1,x0})
// These are 8x8 binary linear maps (XOR of selected bits).
// ----------------------------------------------------------------------------

// Map AES byte -> tower pair {x1,x0} (two 4-bit nibbles)
function [7:0] iso_A;
  input [7:0] x;                           // x[7] = MSB
  reg x7,x6,x5,x4,x3,x2,x1,x0;             // split x into bits
  reg y7,y6,y5,y4,y3,y2,y1,y0;             // outputs (y7..y4)=x1, (y3..y0)=x0
  begin
    {x7,x6,x5,x4,x3,x2,x1,x0} = x;

    // Each yk is XOR of some xi: that's a row of the 8x8 matrix A.
    y7 = x7 ^ x5 ^ x4 ^ x2;
    y6 = x7 ^ x6 ^ x4 ^ x3 ^ x1;
    y5 = x6 ^ x5 ^ x3 ^ x2 ^ x0;
    y4 = x7 ^ x5 ^ x4 ^ x2 ^ x1;

    y3 = x7 ^ x6 ^ x1 ^ x0;
    y2 = x6 ^ x5 ^ x2 ^ x1;
    y1 = x5 ^ x4 ^ x3 ^ x0;
    y0 = x4 ^ x3 ^ x2 ^ x1;

    iso_A = {y7,y6,y5,y4, y3,y2,y1,y0};
  end
endfunction

// Map tower pair {c1,c0} back to AES basis byte
function [7:0] iso_Ainv;
  input [7:0] y;                           // y[7:4]=c1, y[3:0]=c0
  reg y7,y6,y5,y4,y3,y2,y1,y0;
  reg x7,x6,x5,x4,x3,x2,x1,x0;
  begin
    {y7,y6,y5,y4,y3,y2,y1,y0} = y;

    // Rows of A^{-1}: pick bits to XOR back to AES basis
    x7 = y7 ^ y6 ^ y5 ^ y2;
    x6 = y7 ^ y5 ^ y4 ^ y1;
    x5 = y6 ^ y4 ^ y3 ^ y0;
    x4 = y7 ^ y6 ^ y5 ^ y4;

    x3 = y5 ^ y4 ^ y3 ^ y2;
    x2 = y6 ^ y3 ^ y2 ^ y1;
    x1 = y7 ^ y2 ^ y1 ^ y0;
    x0 = y4 ^ y1 ^ y0;

    iso_Ainv = {x7,x6,x5,x4,x3,x2,x1,x0};
  end
endfunction

// ----------------------------------------------------------------------------
// GF(2^8) multiply via composite field, with OPTIONAL pipeline regs between ops.
//
// Parameters (each adds ~1 cycle of latency when set to 1):
//   REG_ISO   : insert reg AFTER iso_A mapping of {a,b}
//               - implemented at: iso_q = (REG_ISO ? iso_r : iso_d)
//   REG_TOWER : insert reg AFTER tower multiply c_t
//               - implemented at: c_t_q = (REG_TOWER ? c_t_r : c_t_d)
//   REG_INV   : insert reg AFTER inverse mapping iso_Ainv
//               - implemented at: prod_q = (REG_INV ? prod_r : prod_d)
//
// What the "param check" is doing:
//   - We ALWAYS compute the combinational result (e.g. iso_d, c_t_d, prod_d).
//   - We also have a register capturing that result every clock (e.g. iso_r).
//   - The ternary select chooses either the registered value (pipelined) or the
//     combinational value (unpipelined) based on the parameter.
//
// Notes:
//   - This file does NOT include valid/ready signals; enabling regs increases
//     latency but throughput can still be 1/cycle when used in a fully unrolled
// ----------------------------------------------------------------------------
module gf256_mul_cf #(
  parameter integer REG_ISO   = 0,
  parameter integer REG_TOWER = 0,
  parameter integer REG_INV   = 0
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire [7:0]  a,
  input  wire [7:0]  b,
  output wire [7:0]  product
);
  // Tower constant μ (in GF(2^4)); must match the chosen A/A^{-1}.
  localparam [3:0] MU = 4'b1000; // μ = t^3

  // --- Op #1: iso_A mapping (combinational) ---
  wire [15:0] iso_d = {iso_A(a), iso_A(b)};  // {a_t, b_t}

  // Optional reg after iso_A: iso_r captures iso_d, iso_q selects reg vs bypass
  reg  [15:0] iso_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) iso_r <= 16'h0000;
    else        iso_r <= iso_d;
  end
  wire [15:0] iso_q = (REG_ISO ? iso_r : iso_d);

  wire [7:0] a_t = iso_q[15:8];
  wire [7:0] b_t = iso_q[7:0];
  wire [3:0] a1  = a_t[7:4], a0 = a_t[3:0];
  wire [3:0] b1  = b_t[7:4], b0 = b_t[3:0];

  // --- Op #2: tower multiply (combinational) ---
  wire [7:0] c_t_d = gf_tower_mul(a1,a0, b1,b0, MU);

  // Optional reg after tower multiply: c_t_r captures c_t_d, c_t_q selects
  reg  [7:0] c_t_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) c_t_r <= 8'h00;
    else        c_t_r <= c_t_d;
  end
  wire [7:0] c_t_q = (REG_TOWER ? c_t_r : c_t_d);

  // --- Op #3: inverse mapping back to AES basis (combinational) ---
  wire [7:0] prod_d = iso_Ainv(c_t_q);

  // Optional reg after inverse mapping: prod_r captures prod_d, prod_q selects
  reg  [7:0] prod_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) prod_r <= 8'h00;
    else        prod_r <= prod_d;
  end
  wire [7:0] prod_q = (REG_INV ? prod_r : prod_d);

  assign product = prod_q;

endmodule

// ----------------------------------------------------------------------------
// Column-level MixColumns with optional pipelineing.
//
// Parameters:
//   REG_ISO/REG_TOWER/REG_INV : forwarded into gf256_mul_cf (see above)
//   REG_OUT                  : optional reg after the final MixColumns XOR matrix
//                              - implemented at: col_out = (REG_OUT ? col_out_r : col_d)
//
// Alignment note (why we delay col_in):
//   - 02·s terms come out of gf256_mul_cf with latency = REG_ISO+REG_TOWER+REG_INV
//   - We delay the original column by the SAME optional registers so the 01·s
//     terms (and the extra XOR for 03·s) line up in time with 02·s.
// ----------------------------------------------------------------------------
module aes_mixcolumns_cf #(
  parameter integer REG_ISO   = 0,
  parameter integer REG_TOWER = 0,
  parameter integer REG_INV   = 0,
  parameter integer REG_OUT   = 0
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire [31:0] col_in,
  output wire [31:0] col_out
);
  // Delay the whole column through the same optional stages as the multiplier.
  // Each stage has a register + a bypass select

  wire [31:0] col0_d = col_in;

  reg  [31:0] col_iso_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) col_iso_r <= 32'h0;
    else        col_iso_r <= col0_d;
  end
  wire [31:0] col_iso_q = (REG_ISO ? col_iso_r : col0_d);

  reg  [31:0] col_tower_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) col_tower_r <= 32'h0;
    else        col_tower_r <= col_iso_q;
  end
  wire [31:0] col_tower_q = (REG_TOWER ? col_tower_r : col_iso_q);

  reg  [31:0] col_inv_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) col_inv_r <= 32'h0;
    else        col_inv_r <= col_tower_q;
  end
  wire [31:0] col_delayed = (REG_INV ? col_inv_r : col_tower_q);

  // Byte slicing (MSB-first)
  wire [7:0] s0 = col_delayed[31:24];
  wire [7:0] s1 = col_delayed[23:16];
  wire [7:0] s2 = col_delayed[15:8];
  wire [7:0] s3 = col_delayed[7:0];

  // 02· via composite-field multiplier (same latency as col_delayed)
  wire [7:0] s0x2, s1x2, s2x2, s3x2;
  gf256_mul_cf #(.REG_ISO(REG_ISO), .REG_TOWER(REG_TOWER), .REG_INV(REG_INV))
    m20(.clk(clk), .rst_n(rst_n), .a(s0), .b(8'h02), .product(s0x2));
  gf256_mul_cf #(.REG_ISO(REG_ISO), .REG_TOWER(REG_TOWER), .REG_INV(REG_INV))
    m21(.clk(clk), .rst_n(rst_n), .a(s1), .b(8'h02), .product(s1x2));
  gf256_mul_cf #(.REG_ISO(REG_ISO), .REG_TOWER(REG_TOWER), .REG_INV(REG_INV))
    m22(.clk(clk), .rst_n(rst_n), .a(s2), .b(8'h02), .product(s2x2));
  gf256_mul_cf #(.REG_ISO(REG_ISO), .REG_TOWER(REG_TOWER), .REG_INV(REG_INV))
    m23(.clk(clk), .rst_n(rst_n), .a(s3), .b(8'h02), .product(s3x2));

  // 03·s = 02·s ⊕ 01·s  (use delayed s* so it aligns with s*x2)
  wire [7:0] s0x3 = s0x2 ^ s0;
  wire [7:0] s1x3 = s1x2 ^ s1;
  wire [7:0] s2x3 = s2x2 ^ s2;
  wire [7:0] s3x3 = s3x2 ^ s3;

  // Final matrix add (⊕) is XOR in GF(2)
  wire [7:0] o0_d = s0x2 ^ s1x3 ^ s2    ^ s3;
  wire [7:0] o1_d = s0    ^ s1x2 ^ s2x3 ^ s3;
  wire [7:0] o2_d = s0    ^ s1    ^ s2x2 ^ s3x3;
  wire [7:0] o3_d = s0x3 ^ s1    ^ s2    ^ s3x2;

  wire [31:0] col_d = {o0_d,o1_d,o2_d,o3_d};

  // Optional output register: captures col_d, then col_out selects reg vs bypass
  reg  [31:0] col_out_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) col_out_r <= 32'h0;
    else        col_out_r <= col_d;
  end
  assign col_out = (REG_OUT ? col_out_r : col_d);

endmodule
