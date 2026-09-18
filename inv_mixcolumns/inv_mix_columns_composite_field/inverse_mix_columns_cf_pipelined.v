`timescale 1ns/1ps

module inverseMixcomposite (
    input  wire        clk,
    input  wire        en,
    input  wire [31:0] col_in,
    output wire [31:0] col_out
);

    // bytes (MSB first)
    wire [7:0] a = col_in[31:24];
    wire [7:0] b = col_in[23:16];
    wire [7:0] c = col_in[15:8];
    wire [7:0] d = col_in[7:0];

    // constant used in tower multiplication (GF(2^4) extension)
    localparam [3:0] MU = 4'b1000;

    // GF(2^4) add (xor)
    function automatic [3:0] gf16_add;
        input [3:0] x;
        input [3:0] y;
        begin
            gf16_add = x ^ y;
        end
    endfunction

    // GF(2^4) multiply (polynomial multiplication + reduction)
    // Reduction matches x^4 + x + 1
    function automatic [3:0] gf16_mul;
        input [3:0] x;
        input [3:0] y;
        reg x0,x1,x2,x3, y0,y1,y2,y3;
        reg r0,r1,r2,r3,r4,r5,r6;
        reg m0,m1,m2,m3;
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

            // reduce modulo x^4 + x + 1
            m0 = r0 ^ r4;
            m1 = r1 ^ r4 ^ r5;
            m2 = r2 ^ r5 ^ r6;
            m3 = r3 ^ r6;

            gf16_mul = {m3,m2,m1,m0};
        end
    endfunction

    // Tower field multiplication:
    // (a1*t + a0) * (b1*t + b0) in GF((2^4)^2) with t^2 + t + mu
    function automatic [7:0] gf_tower_mul;
        input [3:0] a1;
        input [3:0] a0;
        input [3:0] b1;
        input [3:0] b0;
        input [3:0] mu;
        reg [3:0] a0b0, a1b1, a0b1, a1b0, mu_a1b1;
        reg [3:0] c0, c1;
        begin
            a0b0    = gf16_mul(a0, b0);
            a1b1    = gf16_mul(a1, b1);
            a0b1    = gf16_mul(a0, b1);
            a1b0    = gf16_mul(a1, b0);
            mu_a1b1 = gf16_mul(mu, a1b1);

            c0 = gf16_add(a0b0, mu_a1b1);
            c1 = gf16_add(gf16_add(a0b1, a1b0), a1b1);

            gf_tower_mul = {c1, c0};
        end
    endfunction

    // isomorphism A (AES <-> tower)
    function automatic [7:0] iso_A;
        input [7:0] x;
        reg x7,x6,x5,x4,x3,x2,x1,x0;
        reg y7,y6,y5,y4,y3,y2,y1,y0;
        begin
            {x7,x6,x5,x4,x3,x2,x1,x0} = x;
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

    // inverse isomorphism A^{-1}
    function automatic [7:0] iso_Ainv;
        input [7:0] y;
        reg y7,y6,y5,y4,y3,y2,y1,y0;
        reg x7,x6,x5,x4,x3,x2,x1,x0;
        begin
            {y7,y6,y5,y4,y3,y2,y1,y0} = y;
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

    // ---- Constant bytes ----
    localparam [7:0] C09 = 8'h09;
    localparam [7:0] C0B = 8'h0B;
    localparam [7:0] C0D = 8'h0D;
    localparam [7:0] C0E = 8'h0E;

    // Tower-domain constants (combinational)
    wire [7:0] C09_t = iso_A(C09);
    wire [7:0] C0B_t = iso_A(C0B);
    wire [7:0] C0D_t = iso_A(C0D);
    wire [7:0] C0E_t = iso_A(C0E);

    // =========================================================================
    // Pipeline Stage 1: iso_A on input bytes (AES -> tower)
    // =========================================================================
    reg [7:0] a_t_r, b_t_r, c_t_r, d_t_r;

    always @(posedge clk) begin
        if (en) begin
            a_t_r <= iso_A(a);
            b_t_r <= iso_A(b);
            c_t_r <= iso_A(c);
            d_t_r <= iso_A(d);
        end
    end

    // =========================================================================
    // Pipeline Stage 2: tower multiplication by constants (tower domain)
    // Compute {a,b,c,d} * {09,0B,0D,0E} => 16 products
    // =========================================================================
    wire [3:0] a1 = a_t_r[7:4], a0 = a_t_r[3:0];
    wire [3:0] b1 = b_t_r[7:4], b0 = b_t_r[3:0];
    wire [3:0] c1 = c_t_r[7:4], c0 = c_t_r[3:0];
    wire [3:0] d1 = d_t_r[7:4], d0 = d_t_r[3:0];

    wire [3:0] k09_1 = C09_t[7:4], k09_0 = C09_t[3:0];
    wire [3:0] k0b_1 = C0B_t[7:4], k0b_0 = C0B_t[3:0];
    wire [3:0] k0d_1 = C0D_t[7:4], k0d_0 = C0D_t[3:0];
    wire [3:0] k0e_1 = C0E_t[7:4], k0e_0 = C0E_t[3:0];

    wire [7:0] a09_t_w = gf_tower_mul(a1,a0, k09_1,k09_0, MU);
    wire [7:0] a0b_t_w = gf_tower_mul(a1,a0, k0b_1,k0b_0, MU);
    wire [7:0] a0d_t_w = gf_tower_mul(a1,a0, k0d_1,k0d_0, MU);
    wire [7:0] a0e_t_w = gf_tower_mul(a1,a0, k0e_1,k0e_0, MU);

    wire [7:0] b09_t_w = gf_tower_mul(b1,b0, k09_1,k09_0, MU);
    wire [7:0] b0b_t_w = gf_tower_mul(b1,b0, k0b_1,k0b_0, MU);
    wire [7:0] b0d_t_w = gf_tower_mul(b1,b0, k0d_1,k0d_0, MU);
    wire [7:0] b0e_t_w = gf_tower_mul(b1,b0, k0e_1,k0e_0, MU);

    wire [7:0] c09_t_w = gf_tower_mul(c1,c0, k09_1,k09_0, MU);
    wire [7:0] c0b_t_w = gf_tower_mul(c1,c0, k0b_1,k0b_0, MU);
    wire [7:0] c0d_t_w = gf_tower_mul(c1,c0, k0d_1,k0d_0, MU);
    wire [7:0] c0e_t_w = gf_tower_mul(c1,c0, k0e_1,k0e_0, MU);

    wire [7:0] d09_t_w = gf_tower_mul(d1,d0, k09_1,k09_0, MU);
    wire [7:0] d0b_t_w = gf_tower_mul(d1,d0, k0b_1,k0b_0, MU);
    wire [7:0] d0d_t_w = gf_tower_mul(d1,d0, k0d_1,k0d_0, MU);
    wire [7:0] d0e_t_w = gf_tower_mul(d1,d0, k0e_1,k0e_0, MU);

    reg [7:0] a09_t_r, a0b_t_r, a0d_t_r, a0e_t_r;
    reg [7:0] b09_t_r, b0b_t_r, b0d_t_r, b0e_t_r;
    reg [7:0] c09_t_r, c0b_t_r, c0d_t_r, c0e_t_r;
    reg [7:0] d09_t_r, d0b_t_r, d0d_t_r, d0e_t_r;

    always @(posedge clk) begin
        if (en) begin
            a09_t_r <= a09_t_w;  a0b_t_r <= a0b_t_w;  a0d_t_r <= a0d_t_w;  a0e_t_r <= a0e_t_w;
            b09_t_r <= b09_t_w;  b0b_t_r <= b0b_t_w;  b0d_t_r <= b0d_t_w;  b0e_t_r <= b0e_t_w;
            c09_t_r <= c09_t_w;  c0b_t_r <= c0b_t_w;  c0d_t_r <= c0d_t_w;  c0e_t_r <= c0e_t_w;
            d09_t_r <= d09_t_w;  d0b_t_r <= d0b_t_w;  d0d_t_r <= d0d_t_w;  d0e_t_r <= d0e_t_w;
        end
    end

    // =========================================================================
    // Pipeline Stage 3: iso_Ainv (tower -> AES) on all 16 products
    // =========================================================================
    wire [7:0] a09_w = iso_Ainv(a09_t_r);
    wire [7:0] a0b_w = iso_Ainv(a0b_t_r);
    wire [7:0] a0d_w = iso_Ainv(a0d_t_r);
    wire [7:0] a0e_w = iso_Ainv(a0e_t_r);

    wire [7:0] b09_w = iso_Ainv(b09_t_r);
    wire [7:0] b0b_w = iso_Ainv(b0b_t_r);
    wire [7:0] b0d_w = iso_Ainv(b0d_t_r);
    wire [7:0] b0e_w = iso_Ainv(b0e_t_r);

    wire [7:0] c09_w = iso_Ainv(c09_t_r);
    wire [7:0] c0b_w = iso_Ainv(c0b_t_r);
    wire [7:0] c0d_w = iso_Ainv(c0d_t_r);
    wire [7:0] c0e_w = iso_Ainv(c0e_t_r);

    wire [7:0] d09_w = iso_Ainv(d09_t_r);
    wire [7:0] d0b_w = iso_Ainv(d0b_t_r);
    wire [7:0] d0d_w = iso_Ainv(d0d_t_r);
    wire [7:0] d0e_w = iso_Ainv(d0e_t_r);

    reg [7:0] a09_r, a0b_r, a0d_r, a0e_r;
    reg [7:0] b09_r, b0b_r, b0d_r, b0e_r;
    reg [7:0] c09_r, c0b_r, c0d_r, c0e_r;
    reg [7:0] d09_r, d0b_r, d0d_r, d0e_r;

    always @(posedge clk) begin
        if (en) begin
            a09_r <= a09_w;  a0b_r <= a0b_w;  a0d_r <= a0d_w;  a0e_r <= a0e_w;
            b09_r <= b09_w;  b0b_r <= b0b_w;  b0d_r <= b0d_w;  b0e_r <= b0e_w;
            c09_r <= c09_w;  c0b_r <= c0b_w;  c0d_r <= c0d_w;  c0e_r <= c0e_w;
            d09_r <= d09_w;  d0b_r <= d0b_w;  d0d_r <= d0d_w;  d0e_r <= d0e_w;
        end
    end

    // =========================================================================
    // Pipeline Stage 4: XOR combine for InvMixColumns + register output
    // =========================================================================
    wire [7:0] out0_w = a0e_r ^ b0b_r ^ c0d_r ^ d09_r;
    wire [7:0] out1_w = a09_r ^ b0e_r ^ c0b_r ^ d0d_r;
    wire [7:0] out2_w = a0d_r ^ b09_r ^ c0e_r ^ d0b_r;
    wire [7:0] out3_w = a0b_r ^ b0d_r ^ c09_r ^ d0e_r;

    reg [31:0] col_out_r;
    always @(posedge clk) begin
        if (en) begin
            col_out_r <= {out0_w, out1_w, out2_w, out3_w};
        end
    end

    assign col_out = col_out_r;

endmodule
