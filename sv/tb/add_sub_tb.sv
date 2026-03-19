`timescale 1ns/1ps

module add_sub_tb;

    localparam int DATA_W        = 32;
    localparam int N_SAMPLES_MAX = 2000000;

    logic clock;
    logic reset;

    // DUT input A side
    logic                      in_a_rd_en;
    logic                      in_a_empty;
    logic signed [DATA_W-1:0]  in_a_dout;

    // DUT input B side
    logic                      in_b_rd_en;
    logic                      in_b_empty;
    logic signed [DATA_W-1:0]  in_b_dout;

    // DUT output add side
    logic                      out_add_wr_en;
    logic                      out_add_full;
    logic signed [DATA_W-1:0]  out_add_din;

    // DUT output sub side
    logic                      out_sub_wr_en;
    logic                      out_sub_full;
    logic signed [DATA_W-1:0]  out_sub_din;

    // input memories
    reg signed [DATA_W-1:0] a_mem [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] b_mem [0:N_SAMPLES_MAX-1];

    // golden memories
    reg signed [DATA_W-1:0] add_golden [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] sub_golden [0:N_SAMPLES_MAX-1];

    integer n_a, n_b, n_add_golden, n_sub_golden;
    integer fd_a, fd_b, fd_add_g, fd_sub_g;
    integer fd_add_out, fd_sub_out;
    integer r;
    reg [31:0] word_tmp;

    integer a_idx;
    integer b_idx;
    integer add_out_idx;
    integer sub_out_idx;

    integer add_err_count;
    integer sub_err_count;
    integer add_match_count;
    integer sub_match_count;

    integer add_max_abs_diff;
    integer sub_max_abs_diff;
    integer add_min_diff;
    integer add_max_diff;
    integer sub_min_diff;
    integer sub_max_diff;

    longint add_sum_abs_diff;
    longint sub_sum_abs_diff;
    longint add_sum_signed_diff;
    longint sub_sum_signed_diff;

    reg signed [31:0] add_expected;
    reg signed [31:0] sub_expected;
    reg signed [31:0] add_diff;
    reg signed [31:0] sub_diff;
    integer add_abs_diff_int;
    integer sub_abs_diff_int;

    add_sub dut (
        .clock        (clock),
        .reset        (reset),

        .in_a_rd_en   (in_a_rd_en),
        .in_a_empty   (in_a_empty),
        .in_a_dout    (in_a_dout),

        .in_b_rd_en   (in_b_rd_en),
        .in_b_empty   (in_b_empty),
        .in_b_dout    (in_b_dout),

        .out_add_wr_en(out_add_wr_en),
        .out_add_full (out_add_full),
        .out_add_din  (out_add_din),

        .out_sub_wr_en(out_sub_wr_en),
        .out_sub_full (out_sub_full),
        .out_sub_din  (out_sub_din)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    task automatic load_a_file;
        begin
            n_a = 0;
            fd_a = $fopen("gold_03_audio_lpr.txt", "r");
            if (fd_a == 0) begin
                $display("ERROR: could not open gold_03_audio_lpr.txt");
                $finish;
            end
            while ((!$feof(fd_a)) && (n_a < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_a, "%h\n", word_tmp);
                if (r == 1) begin
                    a_mem[n_a] = $signed(word_tmp);
                    n_a = n_a + 1;
                end
            end
            $fclose(fd_a);
        end
    endtask

    task automatic load_b_file;
        begin
            n_b = 0;
            fd_b = $fopen("gold_09_audio_lmr.txt", "r");
            if (fd_b == 0) begin
                $display("ERROR: could not open gold_09_audio_lmr.txt");
                $finish;
            end
            while ((!$feof(fd_b)) && (n_b < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_b, "%h\n", word_tmp);
                if (r == 1) begin
                    b_mem[n_b] = $signed(word_tmp);
                    n_b = n_b + 1;
                end
            end
            $fclose(fd_b);
        end
    endtask

    task automatic load_add_golden_file;
        begin
            n_add_golden = 0;
            fd_add_g = $fopen("gold_10_left_add.txt", "r");
            if (fd_add_g == 0) begin
                $display("ERROR: could not open gold_10_left_add.txt");
                $finish;
            end
            while ((!$feof(fd_add_g)) && (n_add_golden < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_add_g, "%h\n", word_tmp);
                if (r == 1) begin
                    add_golden[n_add_golden] = $signed(word_tmp);
                    n_add_golden = n_add_golden + 1;
                end
            end
            $fclose(fd_add_g);
        end
    endtask

    task automatic load_sub_golden_file;
        begin
            n_sub_golden = 0;
            fd_sub_g = $fopen("gold_10_right_sub.txt", "r");
            if (fd_sub_g == 0) begin
                $display("ERROR: could not open gold_10_right_sub.txt");
                $finish;
            end
            while ((!$feof(fd_sub_g)) && (n_sub_golden < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_sub_g, "%h\n", word_tmp);
                if (r == 1) begin
                    sub_golden[n_sub_golden] = $signed(word_tmp);
                    n_sub_golden = n_sub_golden + 1;
                end
            end
            $fclose(fd_sub_g);
        end
    endtask

    // simple source model: current head element is always visible until DUT rd_en pops it
    always_comb begin
        in_a_empty = (a_idx >= n_a);
        in_b_empty = (b_idx >= n_b);

        in_a_dout  = in_a_empty ? '0 : a_mem[a_idx];
        in_b_dout  = in_b_empty ? '0 : b_mem[b_idx];

        out_add_full = 1'b0;
        out_sub_full = 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            if (in_a_rd_en && !in_a_empty)
                a_idx <= a_idx + 1;
            if (in_b_rd_en && !in_b_empty)
                b_idx <= b_idx + 1;
        end
    end

    always @(posedge clock) begin
        if (!reset && out_add_wr_en && !out_add_full) begin
            $fwrite(fd_add_out, "%08h\n", $unsigned(out_add_din));

            if (add_out_idx >= n_add_golden) begin
                $display("ERROR: extra ADD output at index %0d: got %08h",
                         add_out_idx, $unsigned(out_add_din));
                add_err_count <= add_err_count + 1;
            end else begin
                add_expected = add_golden[add_out_idx];
                add_diff     = out_add_din - add_expected;

                if (add_diff < add_min_diff) add_min_diff = add_diff;
                if (add_diff > add_max_diff) add_max_diff = add_diff;

                add_abs_diff_int = (add_diff < 0) ? -add_diff : add_diff;
                if (add_abs_diff_int > add_max_abs_diff) add_max_abs_diff = add_abs_diff_int;

                add_sum_abs_diff    = add_sum_abs_diff + add_abs_diff_int;
                add_sum_signed_diff = add_sum_signed_diff + add_diff;

                if (add_diff == 0) begin
                    add_match_count = add_match_count + 1;
                end else begin
                    add_err_count = add_err_count + 1;
                    $display("ADD MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             add_out_idx,
                             $unsigned(out_add_din),
                             $unsigned(add_expected),
                             add_diff);
                end
            end

            add_out_idx <= add_out_idx + 1;
        end
    end

    always @(posedge clock) begin
        if (!reset && out_sub_wr_en && !out_sub_full) begin
            $fwrite(fd_sub_out, "%08h\n", $unsigned(out_sub_din));

            if (sub_out_idx >= n_sub_golden) begin
                $display("ERROR: extra SUB output at index %0d: got %08h",
                         sub_out_idx, $unsigned(out_sub_din));
                sub_err_count <= sub_err_count + 1;
            end else begin
                sub_expected = sub_golden[sub_out_idx];
                sub_diff     = out_sub_din - sub_expected;

                if (sub_diff < sub_min_diff) sub_min_diff = sub_diff;
                if (sub_diff > sub_max_diff) sub_max_diff = sub_diff;

                sub_abs_diff_int = (sub_diff < 0) ? -sub_diff : sub_diff;
                if (sub_abs_diff_int > sub_max_abs_diff) sub_max_abs_diff = sub_abs_diff_int;

                sub_sum_abs_diff    = sub_sum_abs_diff + sub_abs_diff_int;
                sub_sum_signed_diff = sub_sum_signed_diff + sub_diff;

                if (sub_diff == 0) begin
                    sub_match_count = sub_match_count + 1;
                end else begin
                    sub_err_count = sub_err_count + 1;
                    $display("SUB MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             sub_out_idx,
                             $unsigned(out_sub_din),
                             $unsigned(sub_expected),
                             sub_diff);
                end
            end

            sub_out_idx <= sub_out_idx + 1;
        end
    end

    initial begin
        load_a_file();
        load_b_file();
        load_add_golden_file();
        load_sub_golden_file();

        if (n_a != n_b) begin
            $display("ERROR: input A/B count mismatch");
            $finish;
        end

        fd_add_out = $fopen("sv_add_out.txt", "w");
        fd_sub_out = $fopen("sv_sub_out.txt", "w");

        if ((fd_add_out == 0) || (fd_sub_out == 0)) begin
            $display("ERROR: could not open output files");
            $finish;
        end

        reset             = 1'b1;

        a_idx             = 0;
        b_idx             = 0;
        add_out_idx       = 0;
        sub_out_idx       = 0;

        add_err_count     = 0;
        sub_err_count     = 0;
        add_match_count   = 0;
        sub_match_count   = 0;

        add_max_abs_diff  = 0;
        sub_max_abs_diff  = 0;
        add_min_diff      = 2147483647;
        add_max_diff      = -2147483647;
        sub_min_diff      = 2147483647;
        sub_max_diff      = -2147483647;

        add_sum_abs_diff    = 0;
        sub_sum_abs_diff    = 0;
        add_sum_signed_diff = 0;
        sub_sum_signed_diff = 0;

        repeat (5) @(posedge clock);
        reset = 1'b0;

        // wait until both streams are consumed and outputs are produced
        wait ((a_idx >= n_a) && (b_idx >= n_b) &&
              (add_out_idx >= n_add_golden) && (sub_out_idx >= n_sub_golden));

        repeat (10) @(posedge clock);

        $fclose(fd_add_out);
        $fclose(fd_sub_out);

        $display("====================================================");
        $display("ADD/SUB simulation done.");
        $display("Input A samples       : %0d", n_a);
        $display("Input B samples       : %0d", n_b);

        $display("ADD golden read       : %0d", n_add_golden);
        $display("ADD outputs seen      : %0d", add_out_idx);
        $display("ADD mismatches        : %0d", add_err_count);
        $display("ADD exact matches     : %0d", add_match_count);
        if (add_out_idx > 0) begin
            $display("ADD min signed diff   : %0d", add_min_diff);
            $display("ADD max signed diff   : %0d", add_max_diff);
            $display("ADD max abs diff      : %0d", add_max_abs_diff);
            $display("ADD avg signed diff   : %0f", $itor(add_sum_signed_diff) / add_out_idx);
            $display("ADD avg abs diff      : %0f", $itor(add_sum_abs_diff) / add_out_idx);
        end

        $display("----------------------------------------------------");

        $display("SUB golden read       : %0d", n_sub_golden);
        $display("SUB outputs seen      : %0d", sub_out_idx);
        $display("SUB mismatches        : %0d", sub_err_count);
        $display("SUB exact matches     : %0d", sub_match_count);
        if (sub_out_idx > 0) begin
            $display("SUB min signed diff   : %0d", sub_min_diff);
            $display("SUB max signed diff   : %0d", sub_max_diff);
            $display("SUB max abs diff      : %0d", sub_max_abs_diff);
            $display("SUB avg signed diff   : %0f", $itor(sub_sum_signed_diff) / sub_out_idx);
            $display("SUB avg abs diff      : %0f", $itor(sub_sum_abs_diff) / sub_out_idx);
        end
        $display("====================================================");

        if ((add_err_count == 0) && (sub_err_count == 0))
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

endmodule