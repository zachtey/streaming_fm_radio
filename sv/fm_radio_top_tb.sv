`timescale 1ns/1ps

module fm_radio_top_tb;

    localparam int N_BYTES_MAX = 4000000;
    localparam int N_AUDIO_MAX = 2000000;

    logic               clock;
    logic               reset;

    logic [7:0]         iq_byte;
    logic               iq_valid;
    logic               iq_ready;

    logic signed [31:0] out_left;
    logic signed [31:0] out_right;
    logic               out_valid;
    logic               out_ready;

    reg [7:0] iq_mem [0:N_BYTES_MAX-1];
    reg signed [31:0] left_gold_mem  [0:N_AUDIO_MAX-1];
    reg signed [31:0] right_gold_mem [0:N_AUDIO_MAX-1];

    integer n_bytes, n_left_gold, n_right_gold;
    integer r;
    reg [31:0] word_tmp;

    integer byte_idx;
    integer out_idx;
    integer err_left, err_right;
    integer match_left, match_right;

    reg signed [31:0] exp_left, exp_right;
    reg signed [31:0] diff_left, diff_right;

    integer fd_left_out, fd_right_out;

    fm_radio_top dut (
        .clock    (clock),
        .reset    (reset),
        .iq_byte  (iq_byte),
        .iq_valid (iq_valid),
        .iq_ready (iq_ready),
        .out_left (out_left),
        .out_right(out_right),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    assign out_ready = 1'b1;

    task automatic load_usrp_bytes;
        integer fd_local;
        begin
            n_bytes = 0;
            fd_local = $fopen("usrp.txt", "r");
            if (fd_local == 0) begin
                $display("ERROR: could not open usrp.txt");
                $finish;
            end
            while ((!$feof(fd_local)) && (n_bytes < N_BYTES_MAX)) begin
                r = $fscanf(fd_local, "%h\n", word_tmp);
                if (r == 1) begin
                    iq_mem[n_bytes] = word_tmp[7:0];
                    n_bytes = n_bytes + 1;
                end
            end
            $fclose(fd_local);
        end
    endtask

    task automatic load_left_golden;
        integer fd_local;
        begin
            n_left_gold = 0;
            fd_local = $fopen("gold_12_left_gain.txt", "r");
            if (fd_local == 0) begin
                $display("ERROR: could not open gold_12_left_gain.txt");
                $finish;
            end
            while ((!$feof(fd_local)) && (n_left_gold < N_AUDIO_MAX)) begin
                r = $fscanf(fd_local, "%h\n", word_tmp);
                if (r == 1) begin
                    left_gold_mem[n_left_gold] = $signed(word_tmp);
                    n_left_gold = n_left_gold + 1;
                end
            end
            $fclose(fd_local);
        end
    endtask

    task automatic load_right_golden;
        integer fd_local;
        begin
            n_right_gold = 0;
            fd_local = $fopen("gold_12_right_gain.txt", "r");
            if (fd_local == 0) begin
                $display("ERROR: could not open gold_12_right_gain.txt");
                $finish;
            end
            while ((!$feof(fd_local)) && (n_right_gold < N_AUDIO_MAX)) begin
                r = $fscanf(fd_local, "%h\n", word_tmp);
                if (r == 1) begin
                    right_gold_mem[n_right_gold] = $signed(word_tmp);
                    n_right_gold = n_right_gold + 1;
                end
            end
            $fclose(fd_local);
        end
    endtask

    initial begin
        load_usrp_bytes();
        load_left_golden();
        load_right_golden();

        if (n_left_gold != n_right_gold) begin
            $display("ERROR: left/right golden counts do not match");
            $finish;
        end

        fd_left_out  = $fopen("sv_left_audio_out.txt", "w");
        fd_right_out = $fopen("sv_right_audio_out.txt", "w");

        if ((fd_left_out == 0) || (fd_right_out == 0)) begin
            $display("ERROR: could not open output files");
            $finish;
        end

        reset       = 1'b1;
        iq_byte     = '0;
        iq_valid    = 1'b0;

        byte_idx     = 0;
        out_idx      = 0;
        err_left     = 0;
        err_right    = 0;
        match_left   = 0;
        match_right  = 0;

        repeat (5) @(posedge clock);
        reset = 1'b0;
        repeat (2) @(posedge clock);

        while (byte_idx < n_bytes) begin
            @(negedge clock);
            if (iq_ready) begin
                iq_byte  = iq_mem[byte_idx];
                iq_valid = 1'b1;
                byte_idx = byte_idx + 1;
            end else begin
                iq_valid = 1'b0;
                iq_byte  = '0;
            end
        end

        @(negedge clock);
        iq_valid = 1'b0;
        iq_byte  = '0;

        wait (out_idx >= n_left_gold);
        repeat (50) @(posedge clock);

        $fclose(fd_left_out);
        $fclose(fd_right_out);

        $display("====================================================");
        $display("FM RADIO TOP simulation done.");
        $display("Input bytes fed      : %0d", n_bytes);
        $display("Audio outputs seen   : %0d", out_idx);
        $display("Left mismatches      : %0d", err_left);
        $display("Right mismatches     : %0d", err_right);
        $display("Left exact matches   : %0d", match_left);
        $display("Right exact matches  : %0d", match_right);
        if ((err_left == 0) && (err_right == 0))
            $display("PASS");
        else
            $display("FAIL");
        $display("====================================================");

        $finish;
    end

    always @(posedge clock) begin
        if (!reset && out_valid && out_ready) begin
            $fwrite(fd_left_out,  "%08h\n", $unsigned(out_left));
            $fwrite(fd_right_out, "%08h\n", $unsigned(out_right));

            if (out_idx < n_left_gold) begin
                exp_left  = left_gold_mem[out_idx];
                diff_left = out_left - exp_left;
                if (diff_left == 0)
                    match_left = match_left + 1;
                else begin
                    err_left = err_left + 1;
                    $display("LEFT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_idx, $unsigned(out_left), $unsigned(exp_left), diff_left);
                end
            end

            if (out_idx < n_right_gold) begin
                exp_right  = right_gold_mem[out_idx];
                diff_right = out_right - exp_right;
                if (diff_right == 0)
                    match_right = match_right + 1;
                else begin
                    err_right = err_right + 1;
                    $display("RIGHT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_idx, $unsigned(out_right), $unsigned(exp_right), diff_right);
                end
            end

            out_idx = out_idx + 1;
        end
    end

endmodule
