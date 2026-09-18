`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// AES Inverse S-box (InvSubBytes) using ROM lookup table
// - Synchronous read: out_byte updates on posedge clk
// - By default forced to distributed ROM instead of BRAM for fair comparison
// -----------------------------------------------------------------------------
module inv_subbytes_lut (
    input  wire       clk,
    input  wire [7:0] in_byte,
    output reg  [7:0] out_byte
);

    (* rom_style = "distributed" *) reg [7:0] isbox_rom [0:255];

    initial begin
        isbox_rom[8'h00] = 8'h52; isbox_rom[8'h01] = 8'h09; isbox_rom[8'h02] = 8'h6A; isbox_rom[8'h03] = 8'hD5;
        isbox_rom[8'h04] = 8'h30; isbox_rom[8'h05] = 8'h36; isbox_rom[8'h06] = 8'hA5; isbox_rom[8'h07] = 8'h38;
        isbox_rom[8'h08] = 8'hBF; isbox_rom[8'h09] = 8'h40; isbox_rom[8'h0A] = 8'hA3; isbox_rom[8'h0B] = 8'h9E;
        isbox_rom[8'h0C] = 8'h81; isbox_rom[8'h0D] = 8'hF3; isbox_rom[8'h0E] = 8'hD7; isbox_rom[8'h0F] = 8'hFB;

        isbox_rom[8'h10] = 8'h7C; isbox_rom[8'h11] = 8'hE3; isbox_rom[8'h12] = 8'h39; isbox_rom[8'h13] = 8'h82;
        isbox_rom[8'h14] = 8'h9B; isbox_rom[8'h15] = 8'h2F; isbox_rom[8'h16] = 8'hFF; isbox_rom[8'h17] = 8'h87;
        isbox_rom[8'h18] = 8'h34; isbox_rom[8'h19] = 8'h8E; isbox_rom[8'h1A] = 8'h43; isbox_rom[8'h1B] = 8'h44;
        isbox_rom[8'h1C] = 8'hC4; isbox_rom[8'h1D] = 8'hDE; isbox_rom[8'h1E] = 8'hE9; isbox_rom[8'h1F] = 8'hCB;

        isbox_rom[8'h20] = 8'h54; isbox_rom[8'h21] = 8'h7B; isbox_rom[8'h22] = 8'h94; isbox_rom[8'h23] = 8'h32;
        isbox_rom[8'h24] = 8'hA6; isbox_rom[8'h25] = 8'hC2; isbox_rom[8'h26] = 8'h23; isbox_rom[8'h27] = 8'h3D;
        isbox_rom[8'h28] = 8'hEE; isbox_rom[8'h29] = 8'h4C; isbox_rom[8'h2A] = 8'h95; isbox_rom[8'h2B] = 8'h0B;
        isbox_rom[8'h2C] = 8'h42; isbox_rom[8'h2D] = 8'hFA; isbox_rom[8'h2E] = 8'hC3; isbox_rom[8'h2F] = 8'h4E;

        isbox_rom[8'h30] = 8'h08; isbox_rom[8'h31] = 8'h2E; isbox_rom[8'h32] = 8'hA1; isbox_rom[8'h33] = 8'h66;
        isbox_rom[8'h34] = 8'h28; isbox_rom[8'h35] = 8'hD9; isbox_rom[8'h36] = 8'h24; isbox_rom[8'h37] = 8'hB2;
        isbox_rom[8'h38] = 8'h76; isbox_rom[8'h39] = 8'h5B; isbox_rom[8'h3A] = 8'hA2; isbox_rom[8'h3B] = 8'h49;
        isbox_rom[8'h3C] = 8'h6D; isbox_rom[8'h3D] = 8'h8B; isbox_rom[8'h3E] = 8'hD1; isbox_rom[8'h3F] = 8'h25;

        isbox_rom[8'h40] = 8'h72; isbox_rom[8'h41] = 8'hF8; isbox_rom[8'h42] = 8'hF6; isbox_rom[8'h43] = 8'h64;
        isbox_rom[8'h44] = 8'h86; isbox_rom[8'h45] = 8'h68; isbox_rom[8'h46] = 8'h98; isbox_rom[8'h47] = 8'h16;
        isbox_rom[8'h48] = 8'hD4; isbox_rom[8'h49] = 8'hA4; isbox_rom[8'h4A] = 8'h5C; isbox_rom[8'h4B] = 8'hCC;
        isbox_rom[8'h4C] = 8'h5D; isbox_rom[8'h4D] = 8'h65; isbox_rom[8'h4E] = 8'hB6; isbox_rom[8'h4F] = 8'h92;

        isbox_rom[8'h50] = 8'h6C; isbox_rom[8'h51] = 8'h70; isbox_rom[8'h52] = 8'h48; isbox_rom[8'h53] = 8'h50;
        isbox_rom[8'h54] = 8'hFD; isbox_rom[8'h55] = 8'hED; isbox_rom[8'h56] = 8'hB9; isbox_rom[8'h57] = 8'hDA;
        isbox_rom[8'h58] = 8'h5E; isbox_rom[8'h59] = 8'h15; isbox_rom[8'h5A] = 8'h46; isbox_rom[8'h5B] = 8'h57;
        isbox_rom[8'h5C] = 8'hA7; isbox_rom[8'h5D] = 8'h8D; isbox_rom[8'h5E] = 8'h9D; isbox_rom[8'h5F] = 8'h84;

        isbox_rom[8'h60] = 8'h90; isbox_rom[8'h61] = 8'hD8; isbox_rom[8'h62] = 8'hAB; isbox_rom[8'h63] = 8'h00;
        isbox_rom[8'h64] = 8'h8C; isbox_rom[8'h65] = 8'hBC; isbox_rom[8'h66] = 8'hD3; isbox_rom[8'h67] = 8'h0A;
        isbox_rom[8'h68] = 8'hF7; isbox_rom[8'h69] = 8'hE4; isbox_rom[8'h6A] = 8'h58; isbox_rom[8'h6B] = 8'h05;
        isbox_rom[8'h6C] = 8'hB8; isbox_rom[8'h6D] = 8'hB3; isbox_rom[8'h6E] = 8'h45; isbox_rom[8'h6F] = 8'h06;

        isbox_rom[8'h70] = 8'hD0; isbox_rom[8'h71] = 8'h2C; isbox_rom[8'h72] = 8'h1E; isbox_rom[8'h73] = 8'h8F;
        isbox_rom[8'h74] = 8'hCA; isbox_rom[8'h75] = 8'h3F; isbox_rom[8'h76] = 8'h0F; isbox_rom[8'h77] = 8'h02;
        isbox_rom[8'h78] = 8'hC1; isbox_rom[8'h79] = 8'hAF; isbox_rom[8'h7A] = 8'hBD; isbox_rom[8'h7B] = 8'h03;
        isbox_rom[8'h7C] = 8'h01; isbox_rom[8'h7D] = 8'h13; isbox_rom[8'h7E] = 8'h8A; isbox_rom[8'h7F] = 8'h6B;

        isbox_rom[8'h80] = 8'h3A; isbox_rom[8'h81] = 8'h91; isbox_rom[8'h82] = 8'h11; isbox_rom[8'h83] = 8'h41;
        isbox_rom[8'h84] = 8'h4F; isbox_rom[8'h85] = 8'h67; isbox_rom[8'h86] = 8'hDC; isbox_rom[8'h87] = 8'hEA;
        isbox_rom[8'h88] = 8'h97; isbox_rom[8'h89] = 8'hF2; isbox_rom[8'h8A] = 8'hCF; isbox_rom[8'h8B] = 8'hCE;
        isbox_rom[8'h8C] = 8'hF0; isbox_rom[8'h8D] = 8'hB4; isbox_rom[8'h8E] = 8'hE6; isbox_rom[8'h8F] = 8'h73;

        isbox_rom[8'h90] = 8'h96; isbox_rom[8'h91] = 8'hAC; isbox_rom[8'h92] = 8'h74; isbox_rom[8'h93] = 8'h22;
        isbox_rom[8'h94] = 8'hE7; isbox_rom[8'h95] = 8'hAD; isbox_rom[8'h96] = 8'h35; isbox_rom[8'h97] = 8'h85;
        isbox_rom[8'h98] = 8'hE2; isbox_rom[8'h99] = 8'hF9; isbox_rom[8'h9A] = 8'h37; isbox_rom[8'h9B] = 8'hE8;
        isbox_rom[8'h9C] = 8'h1C; isbox_rom[8'h9D] = 8'h75; isbox_rom[8'h9E] = 8'hDF; isbox_rom[8'h9F] = 8'h6E;

        isbox_rom[8'hA0] = 8'h47; isbox_rom[8'hA1] = 8'hF1; isbox_rom[8'hA2] = 8'h1A; isbox_rom[8'hA3] = 8'h71;
        isbox_rom[8'hA4] = 8'h1D; isbox_rom[8'hA5] = 8'h29; isbox_rom[8'hA6] = 8'hC5; isbox_rom[8'hA7] = 8'h89;
        isbox_rom[8'hA8] = 8'h6F; isbox_rom[8'hA9] = 8'hB7; isbox_rom[8'hAA] = 8'h62; isbox_rom[8'hAB] = 8'h0E;
        isbox_rom[8'hAC] = 8'hAA; isbox_rom[8'hAD] = 8'h18; isbox_rom[8'hAE] = 8'hBE; isbox_rom[8'hAF] = 8'h1B;

        isbox_rom[8'hB0] = 8'hFC; isbox_rom[8'hB1] = 8'h56; isbox_rom[8'hB2] = 8'h3E; isbox_rom[8'hB3] = 8'h4B;
        isbox_rom[8'hB4] = 8'hC6; isbox_rom[8'hB5] = 8'hD2; isbox_rom[8'hB6] = 8'h79; isbox_rom[8'hB7] = 8'h20;
        isbox_rom[8'hB8] = 8'h9A; isbox_rom[8'hB9] = 8'hDB; isbox_rom[8'hBA] = 8'hC0; isbox_rom[8'hBB] = 8'hFE;
        isbox_rom[8'hBC] = 8'h78; isbox_rom[8'hBD] = 8'hCD; isbox_rom[8'hBE] = 8'h5A; isbox_rom[8'hBF] = 8'hF4;

        isbox_rom[8'hC0] = 8'h1F; isbox_rom[8'hC1] = 8'hDD; isbox_rom[8'hC2] = 8'hA8; isbox_rom[8'hC3] = 8'h33;
        isbox_rom[8'hC4] = 8'h88; isbox_rom[8'hC5] = 8'h07; isbox_rom[8'hC6] = 8'hC7; isbox_rom[8'hC7] = 8'h31;
        isbox_rom[8'hC8] = 8'hB1; isbox_rom[8'hC9] = 8'h12; isbox_rom[8'hCA] = 8'h10; isbox_rom[8'hCB] = 8'h59;
        isbox_rom[8'hCC] = 8'h27; isbox_rom[8'hCD] = 8'h80; isbox_rom[8'hCE] = 8'hEC; isbox_rom[8'hCF] = 8'h5F;

        isbox_rom[8'hD0] = 8'h60; isbox_rom[8'hD1] = 8'h51; isbox_rom[8'hD2] = 8'h7F; isbox_rom[8'hD3] = 8'hA9;
        isbox_rom[8'hD4] = 8'h19; isbox_rom[8'hD5] = 8'hB5; isbox_rom[8'hD6] = 8'h4A; isbox_rom[8'hD7] = 8'h0D;
        isbox_rom[8'hD8] = 8'h2D; isbox_rom[8'hD9] = 8'hE5; isbox_rom[8'hDA] = 8'h7A; isbox_rom[8'hDB] = 8'h9F;
        isbox_rom[8'hDC] = 8'h93; isbox_rom[8'hDD] = 8'hC9; isbox_rom[8'hDE] = 8'h9C; isbox_rom[8'hDF] = 8'hEF;

        isbox_rom[8'hE0] = 8'hA0; isbox_rom[8'hE1] = 8'hE0; isbox_rom[8'hE2] = 8'h3B; isbox_rom[8'hE3] = 8'h4D;
        isbox_rom[8'hE4] = 8'hAE; isbox_rom[8'hE5] = 8'h2A; isbox_rom[8'hE6] = 8'hF5; isbox_rom[8'hE7] = 8'hB0;
        isbox_rom[8'hE8] = 8'hC8; isbox_rom[8'hE9] = 8'hEB; isbox_rom[8'hEA] = 8'hBB; isbox_rom[8'hEB] = 8'h3C;
        isbox_rom[8'hEC] = 8'h83; isbox_rom[8'hED] = 8'h53; isbox_rom[8'hEE] = 8'h99; isbox_rom[8'hEF] = 8'h61;

        isbox_rom[8'hF0] = 8'h17; isbox_rom[8'hF1] = 8'h2B; isbox_rom[8'hF2] = 8'h04; isbox_rom[8'hF3] = 8'h7E;
        isbox_rom[8'hF4] = 8'hBA; isbox_rom[8'hF5] = 8'h77; isbox_rom[8'hF6] = 8'hD6; isbox_rom[8'hF7] = 8'h26;
        isbox_rom[8'hF8] = 8'hE1; isbox_rom[8'hF9] = 8'h69; isbox_rom[8'hFA] = 8'h14; isbox_rom[8'hFB] = 8'h63;
        isbox_rom[8'hFC] = 8'h55; isbox_rom[8'hFD] = 8'h21; isbox_rom[8'hFE] = 8'h0C; isbox_rom[8'hFF] = 8'h7D;
    end

    always @(posedge clk) begin
        out_byte <= isbox_rom[in_byte];
    end

endmodule