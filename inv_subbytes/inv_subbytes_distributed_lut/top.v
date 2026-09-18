`timescale 1ns/1ps

module top (
    input  wire        CLK100MHZ,
    input  wire        BTNC,
    input  wire [15:0] SW,
    output wire        OUT_BIT
);

    wire clk = CLK100MHZ;
    wire rst = BTNC;

    // Input register (reg-to-reg timing start)
    reg [7:0] in_r;
    always @(posedge clk) begin
        if (rst)
            in_r <= 8'h00;
        else
            in_r <= SW[7:0];
    end

    wire [7:0] core_out;

    // Inverse SubBytes LUT (distributed ROM)
    inv_subbytes_lut u_core (
        .clk      (clk),
        .in_byte  (in_r),
        .out_byte (core_out)
    );

    // Output register endpoint (reg-to-reg timing end)
    reg [7:0] out_r;
    always @(posedge clk) begin
        if (rst)
            out_r <= 8'h00;
        else
            out_r <= core_out;
    end

    // Single observable bit so design is not optimized away
    assign OUT_BIT = out_r[0];

endmodule