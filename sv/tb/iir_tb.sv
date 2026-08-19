`timescale 1ns/1ps
import fm_radio_pkg::*;

module iir_tb;

    localparam int DATA_W        = 32;
    localparam int COEFF_W       = 32;
    localparam int TAPS          = 2;
    localparam int SCALE_SHIFT   = 10;
    localparam int N_SAMPLES_MAX = 2000000;

    localparam logic signed [COEFF_W-1:0] X_COEFFS [0:TAPS-1] = IIR_X_COEFFS;
    localparam logic signed [COEFF_W-1:0] Y_COEFFS [0:TAPS-1] = IIR_Y_COEFFS;

    logic                     clock;
    logic                     reset;

    logic                     in_rd_en;
    logic                     in_empty;
    logic signed [DATA_W-1:0] in_dout;

    logic                     out_wr_en;
    logic                     out_full;
    logic signed [DATA_W-1:0] out_din;

    reg signed [DATA_W-1:0] input_mem  [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] golden_mem [0:N_SAMPLES_MAX-1];

    integer n_input, n_golden;
    integer fd_in, fd_golden, fd_out;
    integer r;
    reg [31:0] word_tmp;

    integer in_idx;
    integer out_idx;

    integer err_count;
    integer match_count;

    integer max_abs_diff;
    integer min_diff;
    integer max_diff;
    integer abs_diff_int;

    longint sum_abs_diff;
    longint sum_signed_diff;

    reg signed [31:0] expected_word;
    reg signed [31:0] diff;

    iir #(
        .DATA_W     (DATA_W),
        .COEFF_W    (COEFF_W),
        .TAPS       (TAPS),
        .SCALE_SHIFT(SCALE_SHIFT),
        .X_COEFFS   (X_COEFFS),
        .Y_COEFFS   (Y_COEFFS)
    ) dut (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (in_rd_en),
        .in_empty (in_empty),
        .in_dout  (in_dout),
        .out_wr_en(out_wr_en),
        .out_full (out_full),
        .out_din  (out_din)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    task automatic load_input_file;
        begin
            n_input = 0;
            fd_in = $fopen("gold_10_left_add.txt", "r");
            if (fd_in == 0) begin
                $display("ERROR: could not open gold_10_left_add.txt");
                $finish;
            end

            while ((!$feof(fd_in)) && (n_input < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_in, "%h\n", word_tmp);
                if (r == 1) begin
                    input_mem[n_input] = $signed(word_tmp);
                    n_input = n_input + 1;
                end
            end

            $fclose(fd_in);
        end
    endtask

    task automatic load_golden_file;
        begin
            n_golden = 0;
            fd_golden = $fopen("gold_11_left_deemph.txt", "r");
            if (fd_golden == 0) begin
                $display("ERROR: could not open gold_11_left_deemph.txt");
                $finish;
            end

            while ((!$feof(fd_golden)) && (n_golden < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_golden, "%h\n", word_tmp);
                if (r == 1) begin
                    golden_mem[n_golden] = $signed(word_tmp);
                    n_golden = n_golden + 1;
                end
            end

            $fclose(fd_golden);
        end
    endtask

    // FIFO source model
    always_comb begin
        in_empty = (in_idx >= n_input);
        in_dout  = in_empty ? '0 : input_mem[in_idx];

        // sink always ready
        out_full = 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            if (in_rd_en && !in_empty)
                in_idx <= in_idx + 1;
        end
    end

    always @(posedge clock) begin
        if (!reset && out_wr_en && !out_full) begin
            $fwrite(fd_out, "%08h\n", $unsigned(out_din));

            if (out_idx >= n_golden) begin
                $display("ERROR: extra DUT output at index %0d: got %08h",
                         out_idx, $unsigned(out_din));
                err_count <= err_count + 1;
            end else begin
                expected_word = golden_mem[out_idx];
                diff          = out_din - expected_word;

                if (diff < min_diff) min_diff = diff;
                if (diff > max_diff) max_diff = diff;

                abs_diff_int = (diff < 0) ? -diff : diff;
                if (abs_diff_int > max_abs_diff) max_abs_diff = abs_diff_int;

                sum_abs_diff    = sum_abs_diff + abs_diff_int;
                sum_signed_diff = sum_signed_diff + diff;

                if (diff == 0) begin
                    match_count = match_count + 1;
                end else begin
                    err_count = err_count + 1;
                    $display("MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_idx,
                             $unsigned(out_din),
                             $unsigned(expected_word),
                             diff);
                end
            end

            out_idx <= out_idx + 1;
        end
    end

    initial begin
        load_input_file();
        load_golden_file();

        fd_out = $fopen("sv_iir_out.txt", "w");
        if (fd_out == 0) begin
            $display("ERROR: could not open sv_iir_out.txt");
            $finish;
        end

        reset          = 1'b1;
        in_idx         = 0;
        out_idx        = 0;
        err_count      = 0;
        match_count    = 0;
        max_abs_diff   = 0;
        min_diff       = 2147483647;
        max_diff       = -2147483647;
        sum_abs_diff   = 0;
        sum_signed_diff = 0;

        repeat (5) @(posedge clock);
        reset = 1'b0;

        wait ((in_idx >= n_input) && (out_idx >= n_golden));

        repeat (10) @(posedge clock);

        $fclose(fd_out);

        $display("====================================================");
        $display("IIR simulation done.");
        $display("Input samples fed    : %0d", n_input);
        $display("Golden outputs read  : %0d", n_golden);
        $display("DUT outputs seen     : %0d", out_idx);
        $display("Mismatches           : %0d", err_count);
        $display("Exact matches        : %0d", match_count);

        if (out_idx > 0) begin
            $display("Min signed diff      : %0d", min_diff);
            $display("Max signed diff      : %0d", max_diff);
            $display("Max abs diff         : %0d", max_abs_diff);
            $display("Avg signed diff      : %0f", $itor(sum_signed_diff) / out_idx);
            $display("Avg abs diff         : %0f", $itor(sum_abs_diff) / out_idx);
        end

        $display("====================================================");

        if (err_count == 0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

endmodule