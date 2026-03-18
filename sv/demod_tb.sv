`timescale 1ns/1ps

module demod_tb;

    localparam int INPUT_W       = 16;
    localparam int DATA_W        = 32;
    localparam int GAIN_W        = 16;
    localparam int N_SAMPLES_MAX = 2000000;

    logic clk;
    logic rst;

    logic                      valid_in;
    logic signed [INPUT_W-1:0] i_in;
    logic signed [INPUT_W-1:0] q_in;

    logic signed [DATA_W-1:0]  demod_out;
    logic                      demod_valid_out;

    reg signed [INPUT_W-1:0] i_mem        [0:N_SAMPLES_MAX-1];
    reg signed [INPUT_W-1:0] q_mem        [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0]  demod_golden [0:N_SAMPLES_MAX-1];

    integer n_i, n_q, n_golden;
    integer fd_i, fd_q, fd_golden, fd_out;
    integer r, idx, out_count, err_count;
    reg [31:0]        word_tmp;
    reg signed [31:0] expected_word;
    reg signed [31:0] diff;
    integer abs_diff_int;

    integer max_abs_diff;
    integer min_diff;
    integer max_diff;
    longint sum_abs_diff;
    longint sum_signed_diff;
    integer match_count;

    integer within_1_count;
    integer within_2_count;
    integer within_4_count;
    integer within_8_count;
    integer within_16_count;
    integer within_32_count;
    integer within_64_count;
    integer within_128_count;

    demod #(
        .INPUT_W(INPUT_W),
        .DATA_W (DATA_W),
        .GAIN_W (GAIN_W)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .valid_in       (valid_in),
        .i_in           (i_in),
        .q_in           (q_in),
        .demod_out      (demod_out),
        .demod_valid_out(demod_valid_out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic load_i_file;
        begin
            n_i = 0;
            fd_i = $fopen("sv_channel_i.txt", "r");
            if (fd_i == 0) begin
                $display("ERROR: could not open sv_channel_i.txt");
                $finish;
            end
            while ((!$feof(fd_i)) && (n_i < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_i, "%h\n", word_tmp);
                if (r == 1) begin
                    i_mem[n_i] = $signed(word_tmp[15:0]);
                    n_i = n_i + 1;
                end
            end
            $fclose(fd_i);
            $display("Loaded %0d I samples", n_i);
        end
    endtask

    task automatic load_q_file;
        begin
            n_q = 0;
            fd_q = $fopen("sv_channel_q.txt", "r");
            if (fd_q == 0) begin
                $display("ERROR: could not open sv_channel_q.txt");
                $finish;
            end
            while ((!$feof(fd_q)) && (n_q < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_q, "%h\n", word_tmp);
                if (r == 1) begin
                    q_mem[n_q] = $signed(word_tmp[15:0]);
                    n_q = n_q + 1;
                end
            end
            $fclose(fd_q);
            $display("Loaded %0d Q samples", n_q);
        end
    endtask

    task automatic load_golden_file;
        begin
            n_golden = 0;
            fd_golden = $fopen("stage_demod.txt", "r");
            if (fd_golden == 0) begin
                $display("ERROR: could not open stage_demod.txt");
                $finish;
            end
            while ((!$feof(fd_golden)) && (n_golden < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_golden, "%h\n", word_tmp);
                if (r == 1) begin
                    demod_golden[n_golden] = $signed(word_tmp);
                    n_golden = n_golden + 1;
                end
            end
            $fclose(fd_golden);
            $display("Loaded %0d golden demod samples", n_golden);
        end
    endtask

    initial begin
        load_i_file();
        load_q_file();
        load_golden_file();

        if (n_i != n_q) begin
            $display("ERROR: I/Q count mismatch");
            $finish;
        end

        fd_out = $fopen("sv_demod_out.txt", "w");
        if (fd_out == 0) begin
            $display("ERROR: could not open sv_demod_out.txt");
            $finish;
        end

        rst              = 1'b1;
        valid_in         = 1'b0;
        i_in             = '0;
        q_in             = '0;
        out_count        = 0;
        err_count        = 0;
        match_count      = 0;
        max_abs_diff     = 0;
        min_diff         = 2147483647;
        max_diff         = -2147483647;
        sum_abs_diff     = 0;
        sum_signed_diff  = 0;
        within_1_count   = 0;
        within_2_count   = 0;
        within_4_count   = 0;
        within_8_count   = 0;
        within_16_count  = 0;
        within_32_count  = 0;
        within_64_count  = 0;
        within_128_count = 0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        for (idx = 0; idx < n_i; idx = idx + 1) begin
            @(negedge clk);
            i_in     = i_mem[idx];
            q_in     = q_mem[idx];
            valid_in = 1'b1;
        end

        @(negedge clk);
        valid_in = 1'b0;
        i_in     = '0;
        q_in     = '0;

        fork
            begin
                wait (out_count == (n_i - 1));
            end
            begin
                repeat (500000) @(posedge clk);
                $display("ERROR: timeout waiting for outputs");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $fclose(fd_out);

        $display("====================================================");
        $display("Simulation done.");
        $display("Input samples fed    : %0d", n_i);
        $display("Golden outputs read  : %0d", n_golden);
        $display("DUT outputs seen     : %0d", out_count);
        $display("Golden compare start : golden[1]");
        $display("Mismatches           : %0d", err_count);
        $display("Exact matches        : %0d", match_count);

        if (out_count > 0) begin
            $display("Min signed diff      : %0d", min_diff);
            $display("Max signed diff      : %0d", max_diff);
            $display("Max abs diff         : %0d", max_abs_diff);
            $display("Avg signed diff      : %0f", $itor(sum_signed_diff) / out_count);
            $display("Avg abs diff         : %0f", $itor(sum_abs_diff) / out_count);

            $display("|diff| <= 1          : %0d", within_1_count);
            $display("|diff| <= 2          : %0d", within_2_count);
            $display("|diff| <= 4          : %0d", within_4_count);
            $display("|diff| <= 8          : %0d", within_8_count);
            $display("|diff| <= 16         : %0d", within_16_count);
            $display("|diff| <= 32         : %0d", within_32_count);
            $display("|diff| <= 64         : %0d", within_64_count);
            $display("|diff| <= 128        : %0d", within_128_count);
        end

        $display("====================================================");

        if (err_count == 0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

    always @(posedge clk) begin
        if (!rst && demod_valid_out) begin
            $fwrite(fd_out, "%08h\n", $unsigned(demod_out));

            if ((out_count + 1) >= n_golden) begin
                $display("ERROR: extra DUT output at index %0d: got %08h",
                         out_count, $unsigned(demod_out));
                err_count = err_count + 1;
            end else begin
                expected_word = demod_golden[out_count + 1];
                diff = demod_out - expected_word;

                if (diff < min_diff)
                    min_diff = diff;
                if (diff > max_diff)
                    max_diff = diff;

                abs_diff_int = (diff < 0) ? -diff : diff;

                if (abs_diff_int > max_abs_diff)
                    max_abs_diff = abs_diff_int;

                sum_abs_diff    = sum_abs_diff + abs_diff_int;
                sum_signed_diff = sum_signed_diff + diff;

                if (abs_diff_int <= 1)
                    within_1_count = within_1_count + 1;
                if (abs_diff_int <= 2)
                    within_2_count = within_2_count + 1;
                if (abs_diff_int <= 4)
                    within_4_count = within_4_count + 1;
                if (abs_diff_int <= 8)
                    within_8_count = within_8_count + 1;
                if (abs_diff_int <= 16)
                    within_16_count = within_16_count + 1;
                if (abs_diff_int <= 32)
                    within_32_count = within_32_count + 1;
                if (abs_diff_int <= 64)
                    within_64_count = within_64_count + 1;
                if (abs_diff_int <= 128)
                    within_128_count = within_128_count + 1;

                if (diff == 0) begin
                    match_count = match_count + 1;
                end else begin
                    err_count = err_count + 1;
                    $display("MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_count,
                             $unsigned(demod_out),
                             $unsigned(expected_word),
                             diff);
                end
            end

            out_count = out_count + 1;
        end
    end

endmodule