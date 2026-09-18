// ============================================================================
// AES MixColumns using XTIME
// ----------------------------------------------------------------------------
// Big picture:
//  - We implement GF(2^8) multiplication by 0x02 using xtime() (shift + reduce).
//  - Then 0x03·byte = (0x02·byte) ⊕ byte.
//  - MixColumns is a fixed XOR matrix per 32-bit column (4 bytes).
//  - Parameters are used to control pipelining.
// ============================================================================
//
// Forward MixColumns per column (over GF(2^8))
//   o0 = 02·s0 ⊕ 03·s1 ⊕ 01·s2 ⊕ 01·s3
//   o1 = 01·s0 ⊕ 02·s1 ⊕ 03·s2 ⊕ 01·s3
//   o2 = 01·s0 ⊕ 01·s1 ⊕ 02·s2 ⊕ 03·s3
//   o3 = 03·s0 ⊕ 01·s1 ⊕ 01·s2 ⊕ 02·s3
//
// Pipeline cut points (per column):
//   REG_X2  : register after xtime() results (02·s) and aligned raw bytes
//             - used at: x2_q = (REG_X2 ? x2_r : x2_d) and s1_q = (REG_X2 ? s1_r : col_in)
//   REG_X3  : register after computing 03·s = 02·s ⊕ s (and carry s, x2 for alignment)
//             - used at: {s2_q,x2_2q,x3_q} = (REG_X3 ? regs : comb)
//   REG_OUT : register after final MixColumns XOR matrix
//             - used at: col_out = (REG_OUT ? col_out_r : col_d)
//
// What the "param check" is doing
//   - We ALWAYS compute the combinational result (e.g. x2_d, x3_d, col_d).
//   - We also have a register capturing that result every clock, even if REG_*=0.
//   - The ternary select chooses which value is USED by the datapath:
//        REG_*=1  -> use the registered value (adds a pipeline stage)
//        REG_*=0  -> bypass the register and use the combinational value
//     Unused registers are not implemented
// ============================================================================

`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// 32-bit column MixColumns using xtime(), with optional pipelining registers.
// col_in  = {s0,s1,s2,s3} (MSB-first bytes)
// col_out = {o0,o1,o2,o3} (MSB-first bytes)
// ----------------------------------------------------------------------------
module aes_mixcolumns_xtime #(
  parameter integer REG_X2  = 0,
  parameter integer REG_X3  = 0,
  parameter integer REG_OUT = 0
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire [31:0] col_in,
  output wire [31:0] col_out
);

  // --------------------------------------------------------------------------
  // xtime: multiply by 0x02 in GF(2^8) with AES polynomial reduction (0x11B).
  //   xtime(x) = (x<<1) XOR (0x1B if x[7]==1 else 0x00)
  // --------------------------------------------------------------------------
  function [7:0] xtime;
    input [7:0] x;
    begin
      xtime = {x[6:0],1'b0} ^ (8'h1B & {8{x[7]}});
    end
  endfunction

  // Slice input bytes (MSB-first)
  wire [7:0] s0 = col_in[31:24];
  wire [7:0] s1 = col_in[23:16];
  wire [7:0] s2 = col_in[15:8];
  wire [7:0] s3 = col_in[7:0];

  // --------------------------------------------------------------------------
  // Op #1: compute 02·s (xtime) for each byte
  // --------------------------------------------------------------------------
  wire [31:0] x2_d = { xtime(s0), xtime(s1), xtime(s2), xtime(s3) };

  // Optional reg after xtime: capture x2_d and also delay raw bytes for alignment
  reg  [31:0] x2_r;
  reg  [31:0] s1_r;   // aligned raw bytes after REG_X2 stage
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x2_r <= 32'h0;
      s1_r <= 32'h0;
    end else begin
      x2_r <= x2_d;
      s1_r <= col_in;
    end
  end
  wire [31:0] x2_q = (REG_X2 ? x2_r : x2_d);
  wire [31:0] s1_q = (REG_X2 ? s1_r : col_in);

  // --------------------------------------------------------------------------
  // Op #2: compute 03·s = 02·s ⊕ s
  // --------------------------------------------------------------------------
  wire [31:0] x3_d = x2_q ^ s1_q;

  // Optional reg after x3: capture x3_d and also carry s and x2 for alignment
  reg [31:0] x3_r;
  reg [31:0] x2_2r;
  reg [31:0] s2_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      x3_r  <= 32'h0;
      x2_2r <= 32'h0;
      s2_r  <= 32'h0;
    end else begin
      x3_r  <= x3_d;
      x2_2r <= x2_q;
      s2_r  <= s1_q;
    end
  end
  wire [31:0] x3_q  = (REG_X3 ? x3_r  : x3_d);
  wire [31:0] x2_2q = (REG_X3 ? x2_2r : x2_q);
  wire [31:0] s2_q  = (REG_X3 ? s2_r  : s1_q);

  // Unpack aligned signals for the XOR matrix
  wire [7:0] s0_a  = s2_q[31:24];
  wire [7:0] s1_a  = s2_q[23:16];
  wire [7:0] s2_a  = s2_q[15:8];
  wire [7:0] s3_a  = s2_q[7:0];

  wire [7:0] s0x2 = x2_2q[31:24];
  wire [7:0] s1x2 = x2_2q[23:16];
  wire [7:0] s2x2 = x2_2q[15:8];
  wire [7:0] s3x2 = x2_2q[7:0];

  wire [7:0] s0x3 = x3_q[31:24];
  wire [7:0] s1x3 = x3_q[23:16];
  wire [7:0] s2x3 = x3_q[15:8];
  wire [7:0] s3x3 = x3_q[7:0];

  // --------------------------------------------------------------------------
  // Op #3: MixColumns XOR matrix 
  // --------------------------------------------------------------------------
  wire [7:0] o0_d = s0x2 ^ s1x3 ^ s2_a ^ s3_a;
  wire [7:0] o1_d = s0_a ^ s1x2 ^ s2x3 ^ s3_a;
  wire [7:0] o2_d = s0_a ^ s1_a ^ s2x2 ^ s3x3;
  wire [7:0] o3_d = s0x3 ^ s1_a ^ s2_a ^ s3x2;

  wire [31:0] col_d = {o0_d, o1_d, o2_d, o3_d};

  // Optional output reg after matrix
  reg [31:0] col_out_r;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) col_out_r <= 32'h0;
    else        col_out_r <= col_d;
  end
  assign col_out = (REG_OUT ? col_out_r : col_d);

endmodule

// ----------------------------------------------------------------------------
// 128-bit state wrapper (4 columns), pipeline regs are per-column.
// state_in/state_out are packed MSB-first as {col0,col1,col2,col3}.
// ----------------------------------------------------------------------------
module aes_mixcolumns_state_xtime #(
  parameter integer REG_X2  = 0,
  parameter integer REG_X3  = 0,
  parameter integer REG_OUT = 0
)(
  input  wire         clk,
  input  wire         rst_n,
  input  wire [127:0] state_in,
  output wire [127:0] state_out
);

  wire [31:0] col0_in = state_in[127:96];
  wire [31:0] col1_in = state_in[95:64];
  wire [31:0] col2_in = state_in[63:32];
  wire [31:0] col3_in = state_in[31:0];

  wire [31:0] col0_out, col1_out, col2_out, col3_out;

  aes_mixcolumns_xtime #(.REG_X2(REG_X2), .REG_X3(REG_X3), .REG_OUT(REG_OUT))
    c0(.clk(clk), .rst_n(rst_n), .col_in(col0_in), .col_out(col0_out));

  aes_mixcolumns_xtime #(.REG_X2(REG_X2), .REG_X3(REG_X3), .REG_OUT(REG_OUT))
    c1(.clk(clk), .rst_n(rst_n), .col_in(col1_in), .col_out(col1_out));

  aes_mixcolumns_xtime #(.REG_X2(REG_X2), .REG_X3(REG_X3), .REG_OUT(REG_OUT))
    c2(.clk(clk), .rst_n(rst_n), .col_in(col2_in), .col_out(col2_out));

  aes_mixcolumns_xtime #(.REG_X2(REG_X2), .REG_X3(REG_X3), .REG_OUT(REG_OUT))
    c3(.clk(clk), .rst_n(rst_n), .col_in(col3_in), .col_out(col3_out));

  assign state_out = {col0_out, col1_out, col2_out, col3_out};

endmodule
