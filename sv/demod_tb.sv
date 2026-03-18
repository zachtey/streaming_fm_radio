`timescale 1ns/1ps

module demod_tb;

    localparam int INPUT_W = 16;
    localparam int DATA_W  = 32;
    localparam int GAIN_W  = 16;

    localparam int N_SAMPLES_MAX = 2000000;

    logic clk;
    logic rst;

    logic                         valid_in;
    logic signed [INPUT_W-1:0]    i_in;
    logic signed [INPUT_W-1:0]    q_in;

    logic signed [DATA_W-1:0]     demod_out;
    logic                         demod_valid_out;

    // input memories
    reg signed [INPUT_W-1:0] i_mem [0:N_SAMPLES_MAX-1];
    reg signed [INPUT_W-1:0] q_mem [0:N_SAMPLES_MAX-1];

    // golden output memory
    reg signed [DATA_W-1:0] demod_golden [0:N_SAMPLES_MAX-1];

    integer n_i;
    integer n_q;
    integer n_golden;

    integer fd_i;
    integer fd_q;
    integer fd_golden;
    integer fd_out;

    integer r;
    integer idx;
    integer out_count;
    integer err_count;

    reg [31:0] word_tmp;
    reg signed [31:0] expected_word;
    reg signed [31:0] diff;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // clock
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // load I samples
    // file format: one 16-bit hex value per line
    // ------------------------------------------------------------
    task automatic load_i_file;
        begin
            n_i = 0;
            fd_i = $fopen("sv_channel_i.txt", "r");
            if (fd_i == 0) begin
                $display("ERROR: could not open sv_channel_i.txt");
                $finish;
            end

            while (!$feof(fd_i) && n_i < N_SAMPLES_MAX) begin
                r = $fscanf(fd_i, "%h\n", word_tmp);
                if (r == 1) begin
                    i_mem[n_i] = $signed(word_tmp[15:0]);
                    n_i = n_i + 1;
                end
            end

            $fclose(fd_i);
            $display("Loaded %0d I samples from sv_channel_i.txt", n_i);
        end
    endtask

    // ------------------------------------------------------------
    // load Q samples
    // file format: one 16-bit hex value per line
    // ------------------------------------------------------------
    task automatic load_q_file;
        begin
            n_q = 0;
            fd_q = $fopen("sv_channel_q.txt", "r");
            if (fd_q == 0) begin
                $display("ERROR: could not open sv_channel_q.txt");
                $finish;
            end

            while (!$feof(fd_q) && n_q < N_SAMPLES_MAX) begin
                r = $fscanf(fd_q, "%h\n", word_tmp);
                if (r == 1) begin
                    q_mem[n_q] = $signed(word_tmp[15:0]);
                    n_q = n_q + 1;
                end
            end

            $fclose(fd_q);
            $display("Loaded %0d Q samples from sv_channel_q.txt", n_q);
        end
    endtask

    // ------------------------------------------------------------
    // load golden demod output
    // file format assumed: one 32-bit hex value per line
    // ------------------------------------------------------------
    task automatic load_golden_file;
        begin
            n_golden = 0;
            fd_golden = $fopen("stage_demod.txt", "r");
            if (fd_golden == 0) begin
                $display("ERROR: could not open stage_demod.txt");
                $finish;
            end

            while (!$feof(fd_golden) && n_golden < N_SAMPLES_MAX) begin
                r = $fscanf(fd_golden, "%h\n", word_tmp);
                if (r == 1) begin
                    demod_golden[n_golden] = $signed(word_tmp);
                    n_golden = n_golden + 1;
                end
            end

            $fclose(fd_golden);
            $display("Loaded %0d golden demod samples from stage_demod.txt", n_golden);
        end
    endtask

    // ------------------------------------------------------------
    // main stimulus
    // ------------------------------------------------------------
    initial begin
        load_i_file();
        load_q_file();
        load_golden_file();

        if (n_i != n_q) begin
            $display("ERROR: I and Q sample count mismatch: n_i=%0d n_q=%0d", n_i, n_q);
            $finish;
        end

        fd_out = $fopen("sv_demod_out.txt", "w");
        if (fd_out == 0) begin
            $display("ERROR: could not open sv_demod_out.txt");
            $finish;
        end

        rst       = 1'b1;
        valid_in  = 1'b0;
        i_in      = '0;
        q_in      = '0;
        out_count = 0;
        err_count = 0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // feed all samples, one per clock
        for (idx = 0; idx < n_i; idx = idx + 1) begin
            @(posedge clk);
            i_in     <= i_mem[idx];
            q_in     <= q_mem[idx];
            valid_in <= 1'b1;
        end

        @(posedge clk);
        valid_in <= 1'b0;
        i_in     <= '0;
        q_in     <= '0;

        // let pipeline drain
        repeat (200) @(posedge clk);

        $fclose(fd_out);

        $display("==============================================");
        $display("Simulation done.");
        $display("Input samples fed   : %0d", n_i);
        $display("Golden outputs read : %0d", n_golden);
        $display("DUT outputs seen    : %0d", out_count);
        $display("Mismatches          : %0d", err_count);
        $display("==============================================");

        if (err_count == 0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

    // ------------------------------------------------------------
    // capture and compare outputs
    // ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst && demod_valid_out) begin
            $fwrite(fd_out, "%08h\n", $unsigned(demod_out));

            if (out_count >= n_golden) begin
                $display("ERROR: extra DUT output at index %0d: got %08h",
                         out_count, $unsigned(demod_out));
                err_count <= err_count + 1;
            end else begin
                expected_word = demod_golden[out_count];

                if (demod_out !== expected_word) begin
                    diff = demod_out - expected_word;
                    $display("MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_count,
                             $unsigned(demod_out),
                             $unsigned(expected_word),
                             diff);
                    err_count <= err_count + 1;
                end
            end

            out_count <= out_count + 1;
        end
    end

endmodule