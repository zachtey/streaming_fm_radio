// `timescale 1ns/1ps

// module fm_radio_top_tb;

//     localparam int N_BYTES_MAX   = 4000000;
//     localparam int N_AUDIO_MAX   = 2000000;

//     // Only inspect the buggy region
//     localparam int DBG_FIRST = 67;
//     localparam int DBG_LAST  = 79;

//     logic               clock;
//     logic               reset;

//     logic [7:0]         iq_byte;
//     logic               iq_valid;
//     logic               iq_ready;

//     logic signed [31:0] out_left;
//     logic signed [31:0] out_right;
//     logic               out_valid;
//     logic               out_ready;

//     reg [7:0] iq_mem [0:N_BYTES_MAX-1];
//     reg signed [31:0] left_gold_mem  [0:N_AUDIO_MAX-1];
//     reg signed [31:0] right_gold_mem [0:N_AUDIO_MAX-1];

//     // Stage goldens for debug
//     reg signed [31:0] gold_lpr_mem       [0:N_AUDIO_MAX-1];
//     reg signed [31:0] gold_lmr_mem       [0:N_AUDIO_MAX-1];
//     reg signed [31:0] gold_left_add_mem  [0:N_AUDIO_MAX-1];
//     reg signed [31:0] gold_right_sub_mem [0:N_AUDIO_MAX-1];
//     reg signed [31:0] gold_left_de_mem   [0:N_AUDIO_MAX-1];
//     reg signed [31:0] gold_right_de_mem  [0:N_AUDIO_MAX-1];

//     integer n_bytes, n_left_gold, n_right_gold;
//     integer n_lpr_gold, n_lmr_gold, n_left_add_gold, n_right_sub_gold, n_left_de_gold, n_right_de_gold;

//     integer r;
//     reg [31:0] word_tmp;

//     integer byte_idx;
//     integer out_idx;
//     integer err_left, err_right;
//     integer match_left, match_right;

//     reg signed [31:0] exp_left, exp_right;
//     reg signed [31:0] diff_left, diff_right;

//     integer fd_left_out, fd_right_out;

//     fm_radio_top dut (
//         .clock    (clock),
//         .reset    (reset),
//         .iq_byte  (iq_byte),
//         .iq_valid (iq_valid),
//         .iq_ready (iq_ready),
//         .out_left (out_left),
//         .out_right(out_right),
//         .out_valid(out_valid),
//         .out_ready(out_ready)
//     );

//     initial clock = 1'b0;
//     always #5 clock = ~clock;

//     assign out_ready = 1'b1;

//     task automatic load_bytes(
//         input string fname,
//         output integer count,
//         output reg [7:0] mem [0:N_BYTES_MAX-1]
//     );
//         integer fd_local;
//         begin
//             count = 0;
//             fd_local = $fopen(fname, "r");
//             if (fd_local == 0) begin
//                 $display("ERROR: could not open %s", fname);
//                 $finish;
//             end
//             while ((!$feof(fd_local)) && (count < N_BYTES_MAX)) begin
//                 r = $fscanf(fd_local, "%h\n", word_tmp);
//                 if (r == 1) begin
//                     mem[count] = word_tmp[7:0];
//                     count = count + 1;
//                 end
//             end
//             $fclose(fd_local);
//         end
//     endtask

//     task automatic load_words(
//         input string fname,
//         output integer count,
//         output reg signed [31:0] mem [0:N_AUDIO_MAX-1]
//     );
//         integer fd_local;
//         begin
//             count = 0;
//             fd_local = $fopen(fname, "r");
//             if (fd_local == 0) begin
//                 $display("ERROR: could not open %s", fname);
//                 $finish;
//             end
//             while ((!$feof(fd_local)) && (count < N_AUDIO_MAX)) begin
//                 r = $fscanf(fd_local, "%h\n", word_tmp);
//                 if (r == 1) begin
//                     mem[count] = $signed(word_tmp);
//                     count = count + 1;
//                 end
//             end
//             $fclose(fd_local);
//         end
//     endtask

//     task automatic print_debug_window;
//         input integer idx_dbg;
//         reg signed [31:0] st_lpr, st_lmr, st_add, st_sub, st_lde, st_rde;
//         reg signed [31:0] gd_lpr, gd_lmr, gd_add, gd_sub, gd_lde, gd_rde;
//         begin
//             st_lpr = dut.u_fm_radio.lpr_dout;
//             st_lmr = dut.u_fm_radio.lmr_dout;
//             st_add = dut.u_fm_radio.add_dout;
//             st_sub = dut.u_fm_radio.sub_dout;
//             st_lde = dut.u_fm_radio.lde_dout;
//             st_rde = dut.u_fm_radio.rde_dout;

//             gd_lpr = gold_lpr_mem[idx_dbg];
//             gd_lmr = gold_lmr_mem[idx_dbg];
//             gd_add = gold_left_add_mem[idx_dbg];
//             gd_sub = gold_right_sub_mem[idx_dbg];
//             gd_lde = gold_left_de_mem[idx_dbg];
//             gd_rde = gold_right_de_mem[idx_dbg];

//             $display("------------------------------------------------------------");
//             $display("DBG output_idx=%0d", idx_dbg);
//             $display("FINAL LEFT : got=%08h exp=%08h diff=%0d",
//                      $unsigned(out_left), $unsigned(exp_left), out_left - exp_left);
//             $display("FINAL RIGHT: got=%08h exp=%08h diff=%0d",
//                      $unsigned(out_right), $unsigned(exp_right), out_right - exp_right);

//             $display("LPR      : got=%08h gold=%08h diff=%0d",
//                      $unsigned(st_lpr), $unsigned(gd_lpr), st_lpr - gd_lpr);
//             $display("LMR      : got=%08h gold=%08h diff=%0d",
//                      $unsigned(st_lmr), $unsigned(gd_lmr), st_lmr - gd_lmr);
//             $display("LEFT_ADD : got=%08h gold=%08h diff=%0d",
//                      $unsigned(st_add), $unsigned(gd_add), st_add - gd_add);
//             $display("RIGHT_SUB: got=%08h gold=%08h diff=%0d",
//                      $unsigned(st_sub), $unsigned(gd_sub), st_sub - gd_sub);
//             $display("LEFT_DE  : got=%08h gold=%08h diff=%0d",
//                      $unsigned(st_lde), $unsigned(gd_lde), st_lde - gd_lde);
//             $display("RIGHT_DE : got=%08h gold=%08h diff=%0d",
//                      $unsigned(st_rde), $unsigned(gd_rde), st_rde - gd_rde);

//             $display("state-ish empties: lpr=%0b lmr=%0b add=%0b sub=%0b lde=%0b rde=%0b lg=%0b rg=%0b",
//                      dut.u_fm_radio.lpr_empty,
//                      dut.u_fm_radio.lmr_empty,
//                      dut.u_fm_radio.add_empty,
//                      dut.u_fm_radio.sub_empty,
//                      dut.u_fm_radio.lde_empty,
//                      dut.u_fm_radio.rde_empty,
//                      dut.u_fm_radio.lg_empty,
//                      dut.u_fm_radio.rg_empty);
//             $display("------------------------------------------------------------");
//         end
//     endtask

//     initial begin
//         load_bytes("usrp.txt", n_bytes, iq_mem);

//         load_words("gold_12_left_gain.txt",  n_left_gold,  left_gold_mem);
//         load_words("gold_12_right_gain.txt", n_right_gold, right_gold_mem);

//         load_words("gold_03_audio_lpr.txt",   n_lpr_gold,       gold_lpr_mem);
//         load_words("gold_09_audio_lmr.txt",   n_lmr_gold,       gold_lmr_mem);
//         load_words("gold_10_left_add.txt",    n_left_add_gold,  gold_left_add_mem);
//         load_words("gold_10_right_sub.txt",   n_right_sub_gold, gold_right_sub_mem);
//         load_words("gold_11_left_deemph.txt", n_left_de_gold,   gold_left_de_mem);
//         load_words("gold_11_right_deemph.txt",n_right_de_gold,  gold_right_de_mem);

//         if (n_left_gold != n_right_gold) begin
//             $display("ERROR: left/right golden counts do not match");
//             $finish;
//         end

//         fd_left_out  = $fopen("sv_left_audio_out.txt", "w");
//         fd_right_out = $fopen("sv_right_audio_out.txt", "w");

//         if ((fd_left_out == 0) || (fd_right_out == 0)) begin
//             $display("ERROR: could not open output files");
//             $finish;
//         end

//         reset       = 1'b1;
//         iq_byte     = '0;
//         iq_valid    = 1'b0;

//         byte_idx     = 0;
//         out_idx      = 0;
//         err_left     = 0;
//         err_right    = 0;
//         match_left   = 0;
//         match_right  = 0;

//         repeat (5) @(posedge clock);
//         reset = 1'b0;
//         repeat (2) @(posedge clock);

//         while (byte_idx < n_bytes) begin
//             @(negedge clock);
//             if (iq_ready) begin
//                 iq_byte  = iq_mem[byte_idx];
//                 iq_valid = 1'b1;
//                 byte_idx = byte_idx + 1;
//             end else begin
//                 iq_valid = 1'b0;
//                 iq_byte  = '0;
//             end
//         end

//         @(negedge clock);
//         iq_valid = 1'b0;
//         iq_byte  = '0;

//         wait (out_idx >= n_left_gold);
//         repeat (20) @(posedge clock);

//         $fclose(fd_left_out);
//         $fclose(fd_right_out);

//         $display("====================================================");
//         $display("FM RADIO TOP simulation done.");
//         $display("Input bytes fed      : %0d", n_bytes);
//         $display("Audio outputs seen   : %0d", out_idx);
//         $display("Left mismatches      : %0d", err_left);
//         $display("Right mismatches     : %0d", err_right);
//         $display("Left exact matches   : %0d", match_left);
//         $display("Right exact matches  : %0d", match_right);
//         if ((err_left == 0) && (err_right == 0))
//             $display("PASS");
//         else
//             $display("FAIL");
//         $display("====================================================");

//         $finish;
//     end

//     always @(posedge clock) begin
//         if (!reset && out_valid && out_ready) begin
//             $fwrite(fd_left_out,  "%08h\n", $unsigned(out_left));
//             $fwrite(fd_right_out, "%08h\n", $unsigned(out_right));

//             exp_left   = left_gold_mem[out_idx];
//             exp_right  = right_gold_mem[out_idx];
//             diff_left  = out_left - exp_left;
//             diff_right = out_right - exp_right;

//             if (diff_left == 0)
//                 match_left = match_left + 1;
//             else begin
//                 err_left = err_left + 1;
//                 if (out_idx >= DBG_FIRST && out_idx <= DBG_LAST)
//                     $display("LEFT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
//                              out_idx, $unsigned(out_left), $unsigned(exp_left), diff_left);
//             end

//             if (diff_right == 0)
//                 match_right = match_right + 1;
//             else begin
//                 err_right = err_right + 1;
//                 if (out_idx >= DBG_FIRST && out_idx <= DBG_LAST)
//                     $display("RIGHT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
//                              out_idx, $unsigned(out_right), $unsigned(exp_right), diff_right);
//             end

//             if ((out_idx >= DBG_FIRST && out_idx <= DBG_LAST) &&
//                 ((diff_left != 0) || (diff_right != 0))) begin
//                 print_debug_window(out_idx);
//             end

//             out_idx = out_idx + 1;
//         end
//     end

// endmodule

`timescale 1ns/1ps
import fm_radio_pkg::*;

module fm_radio_top_tb;

    localparam int N_BYTES_MAX = 4000000;
    localparam int N_IQ_MAX    = N_BYTES_MAX / 4;   // 4 bytes per I/Q pair
    localparam int N_AUDIO_MAX = 2000000;

    logic        clock;
    logic        reset;

    // New FIFO-based DUT interface
    logic        in_full;
    logic        in_wr_en;
    logic [63:0] in_din;

    logic        out_left_empty;
    logic        out_left_rd_en;
    logic signed [31:0] out_left_dout;

    logic        out_right_empty;
    logic        out_right_rd_en;
    logic signed [31:0] out_right_dout;

    // Storage
    reg [7:0]          iq_mem [0:N_BYTES_MAX-1];
    reg [63:0]         iq_packed [0:N_IQ_MAX-1];
    reg signed [31:0]  left_gold_mem  [0:N_AUDIO_MAX-1];
    reg signed [31:0]  right_gold_mem [0:N_AUDIO_MAX-1];

    integer n_bytes, n_iq_words;
    integer n_left_gold, n_right_gold;
    integer r;
    reg [31:0] word_tmp;

    integer iq_idx;
    integer out_idx;
    integer err_left, err_right;
    integer match_left, match_right;

    reg signed [31:0] exp_left, exp_right;
    reg signed [31:0] diff_left, diff_right;

    integer fd_left_out, fd_right_out;

    // DUT
    fm_radio_top dut (
        .clock           (clock),
        .reset           (reset),
        .in_full         (in_full),
        .in_wr_en        (in_wr_en),
        .in_din          (in_din),
        .out_left_empty  (out_left_empty),
        .out_left_rd_en  (out_left_rd_en),
        .out_left_dout   (out_left_dout),
        .out_right_empty (out_right_empty),
        .out_right_rd_en (out_right_rd_en),
        .out_right_dout  (out_right_dout)
    );

    // Clock
    initial clock = 1'b0;
    always #5 clock = ~clock;

    // ================================================================
    // Load raw USRP bytes, then pack into pre-quantized 64-bit words
    // ================================================================
    task automatic load_usrp_bytes;
        integer fd_local, i;
        logic signed [15:0] i_short, q_short;
        logic signed [31:0] i_quant, q_quant;
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

            // Pack every 4 bytes into a 64-bit word:
            //   bytes: [i_lo, i_hi, q_lo, q_hi]
            //   i_short = {i_hi, i_lo}  (signed 16-bit)
            //   q_short = {q_hi, q_lo}  (signed 16-bit)
            //   i_quant = i_short <<< BITS   (QUANTIZE_I)
            //   q_quant = q_short <<< BITS
            //   packed  = {i_quant, q_quant}
            n_iq_words = n_bytes / 4;
            for (i = 0; i < n_iq_words; i = i + 1) begin
                i_short = $signed({iq_mem[i*4+1], iq_mem[i*4+0]});
                q_short = $signed({iq_mem[i*4+3], iq_mem[i*4+2]});
                i_quant = $signed(i_short) <<< BITS;
                q_quant = $signed(q_short) <<< BITS;
                iq_packed[i] = {i_quant, q_quant};
            end
        end
    endtask

    // ================================================================
    // Load golden files (unchanged)
    // ================================================================
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

    // ================================================================
    // Main stimulus
    // ================================================================
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

        reset    = 1'b1;
        in_wr_en = 1'b0;
        in_din   = '0;

        iq_idx      = 0;
        out_idx     = 0;
        err_left    = 0;
        err_right   = 0;
        match_left  = 0;
        match_right = 0;

        repeat (5) @(posedge clock);
        reset = 1'b0;
        repeat (2) @(posedge clock);

        // Feed pre-quantized I/Q words into the input FIFO
        while (iq_idx < n_iq_words) begin
            @(negedge clock);
            if (!in_full) begin
                in_din   = iq_packed[iq_idx];
                in_wr_en = 1'b1;
                iq_idx   = iq_idx + 1;
            end else begin
                in_wr_en = 1'b0;
                in_din   = '0;
            end
        end

        @(negedge clock);
        in_wr_en = 1'b0;
        in_din   = '0;

        // Wait for all outputs
        wait (out_idx >= n_left_gold);
        repeat (50) @(posedge clock);

        $fclose(fd_left_out);
        $fclose(fd_right_out);

        $display("====================================================");
        $display("FM RADIO TOP simulation done.");
        $display("Input IQ words fed   : %0d", n_iq_words);
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

    // ================================================================
    // Output consumer: read from left/right FIFOs, compare to golden
    // ================================================================
    assign out_left_rd_en  = !out_left_empty && !out_right_empty;
    assign out_right_rd_en = !out_left_empty && !out_right_empty;

    always @(posedge clock) begin
        if (!reset && !out_left_empty && !out_right_empty) begin
            $fwrite(fd_left_out,  "%08h\n", $unsigned(out_left_dout));
            $fwrite(fd_right_out, "%08h\n", $unsigned(out_right_dout));

            if (out_idx < n_left_gold) begin
                exp_left  = left_gold_mem[out_idx];
                diff_left = out_left_dout - exp_left;
                if (diff_left == 0)
                    match_left = match_left + 1;
                else begin
                    err_left = err_left + 1;
                    $display("LEFT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_idx, $unsigned(out_left_dout), $unsigned(exp_left), diff_left);
                end
            end

            if (out_idx < n_right_gold) begin
                exp_right  = right_gold_mem[out_idx];
                diff_right = out_right_dout - exp_right;
                if (diff_right == 0)
                    match_right = match_right + 1;
                else begin
                    err_right = err_right + 1;
                    $display("RIGHT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             out_idx, $unsigned(out_right_dout), $unsigned(exp_right), diff_right);
                end
            end

            out_idx = out_idx + 1;
        end
    end

endmodule