`timescale 1ns/1ps

// ============================================================================
// Testbench - inv_mixcolumns_xtime
// ----------------------------------------------------------------------------
//  - Compares the pipelined implementation against a behavioural GF(2^8)
//    reference calculation.
//  - Consecutive inputs are changed every clock to verify pipeline alignment.
// ============================================================================

module tb_inv_mixcolumns_xtime;

    reg         clk;
    reg         en;
    reg  [31:0] col_in;

    wire [31:0] col_out;


    inv_mixcolumns_xtime dut (
        .clk     (clk),
        .en      (en),
        .col_in  (col_in),
        .col_out (col_out)
    );


    // 100 MHz simulation clock
    always #5 clk = ~clk;


    // ------------------------------------------------------------------------
    // Reference GF(2^8) arithmetic
    // ------------------------------------------------------------------------

    function [7:0] xtime_ref;
        input [7:0] x;
        begin
            xtime_ref = {x[6:0], 1'b0} ^ (8'h1B & {8{x[7]}});
        end
    endfunction


    function [7:0] gf_mul;
        input [7:0] x;
        input [7:0] y;

        integer mul_idx;

        reg [7:0] a;
        reg [7:0] b;
        reg [7:0] p;

        begin
            a = x;
            b = y;
            p = 8'h00;

            for (mul_idx = 0; mul_idx < 8; mul_idx = mul_idx + 1) begin
                if (b[0])
                    p = p ^ a;

                a = xtime_ref(a);
                b = b >> 1;
            end

            gf_mul = p;
        end
    endfunction


    function [31:0] inv_mixcolumns_ref;
        input [31:0] x;

        reg [7:0] a;
        reg [7:0] b;
        reg [7:0] c;
        reg [7:0] d;

        reg [7:0] o0;
        reg [7:0] o1;
        reg [7:0] o2;
        reg [7:0] o3;

        begin
            a = x[31:24];
            b = x[23:16];
            c = x[15:8];
            d = x[7:0];

            o0 = gf_mul(a, 8'h0E) ^
                 gf_mul(b, 8'h0B) ^
                 gf_mul(c, 8'h0D) ^
                 gf_mul(d, 8'h09);

            o1 = gf_mul(a, 8'h09) ^
                 gf_mul(b, 8'h0E) ^
                 gf_mul(c, 8'h0B) ^
                 gf_mul(d, 8'h0D);

            o2 = gf_mul(a, 8'h0D) ^
                 gf_mul(b, 8'h09) ^
                 gf_mul(c, 8'h0E) ^
                 gf_mul(d, 8'h0B);

            o3 = gf_mul(a, 8'h0B) ^
                 gf_mul(b, 8'h0D) ^
                 gf_mul(c, 8'h09) ^
                 gf_mul(d, 8'h0E);

            inv_mixcolumns_ref = {o0, o1, o2, o3};
        end
    endfunction


    // ------------------------------------------------------------------------
    // Expected output pipeline
    // ------------------------------------------------------------------------

    reg [31:0] expected [0:6];
    reg        valid    [0:6];

    integer pipe_idx;
    integer init_idx;
    integer stim_idx;

    integer errors;
    integer checks;


    always @(posedge clk) begin
        if (en) begin

            for (pipe_idx = 6; pipe_idx > 0; pipe_idx = pipe_idx - 1) begin
                expected[pipe_idx] <= expected[pipe_idx-1];
                valid[pipe_idx]    <= valid[pipe_idx-1];
            end

           expected[0] <= inv_mixcolumns_ref(col_in);
            valid[0]    <= 1'b1;

            #1;

            if (valid[6]) begin
                checks = checks + 1;

                if (col_out !== expected[6]) begin
                    errors = errors + 1;

                    $display(
                        "FAIL: expected=%h  received=%h",
                        expected[6],
                        col_out
                    );
                end
            end
        end
    end


    // ------------------------------------------------------------------------
    // Test stimulus
    // ------------------------------------------------------------------------

    initial begin

        clk    = 0;
        en     = 0;
        col_in = 32'h00000000;

        errors = 0;
        checks = 0;

        for (init_idx = 0; init_idx < 7; init_idx = init_idx + 1) begin
            expected[init_idx] = 32'h00000000;
            valid[init_idx]    = 1'b0;
        end


        // Start pipeline
        repeat (2) @(posedge clk);

        @(negedge clk);
        en = 1;


        // AES example columns
        @(negedge clk);
        col_in = 32'hBA75F47A;

        @(negedge clk);
        col_in = 32'h84A48D32;

        @(negedge clk);
        col_in = 32'hE88D060E;

        @(negedge clk);
        col_in = 32'h1B407D5D;


        // Additional changing inputs
        for (stim_idx = 0; stim_idx < 100; stim_idx = stim_idx + 1) begin
            @(negedge clk);
            col_in = $random;
        end


        // Flush pipeline
        repeat (8) begin
            @(negedge clk);
            col_in = 32'h00000000;
        end


        @(negedge clk);
        en = 0;


        if (errors == 0)
            $display("PASS: %0d InvMixColumns checks passed.", checks);
        else
            $display("FAIL: %0d errors from %0d checks.", errors, checks);


        #20;
        $finish;

    end

endmodule