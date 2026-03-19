`timescale 1ns/1ps
import fm_radio_pkg::*;

module fir_regression_tb;

    localparam int DATA_W        = 32;
    localparam int COEFF_W       = 32;
    localparam int ACC_W         = 48;
    localparam int N_SAMPLES_MAX = 2000000;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =========================================================
    // Shared helper task style via repeated code blocks
    // =========================================================

    // ---------------- AUDIO_LPR ----------------
    logic signed [DATA_W-1:0] lpr_s_tdata;
    logic                     lpr_s_tvalid;
    logic                     lpr_s_tready;
    logic                     lpr_s_tlast;
    logic signed [DATA_W-1:0] lpr_m_tdata;
    logic                     lpr_m_tvalid;
    logic                     lpr_m_tready;
    logic                     lpr_m_tlast;

    reg signed [DATA_W-1:0] lpr_in_mem   [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] lpr_gold_mem [0:N_SAMPLES_MAX-1];
    integer lpr_n_in, lpr_n_gold, lpr_idx, lpr_out_count, lpr_err, lpr_match;
    integer lpr_fd_in, lpr_fd_gold, lpr_fd_out, lpr_r;
    reg [31:0] lpr_word;
    reg signed [31:0] lpr_exp, lpr_diff;
    integer lpr_min_diff, lpr_max_diff, lpr_max_abs, lpr_abs;
    longint lpr_sum_diff, lpr_sum_abs;
    logic lpr_done;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(AUDIO_LPR_COEFF_TAPS),
        .DECIM(AUDIO_DECIM),
        .SCALE_SHIFT(BITS),
        .COEFFS(AUDIO_LPR_COEFFS)
    ) dut_lpr (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(lpr_s_tdata),
        .s_axis_tvalid(lpr_s_tvalid),
        .s_axis_tready(lpr_s_tready),
        .s_axis_tlast(lpr_s_tlast),
        .m_axis_tdata(lpr_m_tdata),
        .m_axis_tvalid(lpr_m_tvalid),
        .m_axis_tready(lpr_m_tready),
        .m_axis_tlast(lpr_m_tlast)
    );

    assign lpr_m_tready = 1'b1;

    // ---------------- BP_LMR ----------------
    logic signed [DATA_W-1:0] bplmr_s_tdata;
    logic                     bplmr_s_tvalid;
    logic                     bplmr_s_tready;
    logic                     bplmr_s_tlast;
    logic signed [DATA_W-1:0] bplmr_m_tdata;
    logic                     bplmr_m_tvalid;
    logic                     bplmr_m_tready;
    logic                     bplmr_m_tlast;

    reg signed [DATA_W-1:0] bplmr_in_mem   [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] bplmr_gold_mem [0:N_SAMPLES_MAX-1];
    integer bplmr_n_in, bplmr_n_gold, bplmr_idx, bplmr_out_count, bplmr_err, bplmr_match;
    integer bplmr_fd_in, bplmr_fd_gold, bplmr_fd_out, bplmr_r;
    reg [31:0] bplmr_word;
    reg signed [31:0] bplmr_exp, bplmr_diff;
    integer bplmr_min_diff, bplmr_max_diff, bplmr_max_abs, bplmr_abs;
    longint bplmr_sum_diff, bplmr_sum_abs;
    logic bplmr_done;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(BP_LMR_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(BP_LMR_COEFFS)
    ) dut_bplmr (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(bplmr_s_tdata),
        .s_axis_tvalid(bplmr_s_tvalid),
        .s_axis_tready(bplmr_s_tready),
        .s_axis_tlast(bplmr_s_tlast),
        .m_axis_tdata(bplmr_m_tdata),
        .m_axis_tvalid(bplmr_m_tvalid),
        .m_axis_tready(bplmr_m_tready),
        .m_axis_tlast(bplmr_m_tlast)
    );

    assign bplmr_m_tready = 1'b1;

    // ---------------- BP_PILOT ----------------
    logic signed [DATA_W-1:0] pilot_s_tdata;
    logic                     pilot_s_tvalid;
    logic                     pilot_s_tready;
    logic                     pilot_s_tlast;
    logic signed [DATA_W-1:0] pilot_m_tdata;
    logic                     pilot_m_tvalid;
    logic                     pilot_m_tready;
    logic                     pilot_m_tlast;

    reg signed [DATA_W-1:0] pilot_in_mem   [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] pilot_gold_mem [0:N_SAMPLES_MAX-1];
    integer pilot_n_in, pilot_n_gold, pilot_idx, pilot_out_count, pilot_err, pilot_match;
    integer pilot_fd_in, pilot_fd_gold, pilot_fd_out, pilot_r;
    reg [31:0] pilot_word;
    reg signed [31:0] pilot_exp, pilot_diff;
    integer pilot_min_diff, pilot_max_diff, pilot_max_abs, pilot_abs;
    longint pilot_sum_diff, pilot_sum_abs;
    logic pilot_done;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(BP_PILOT_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(BP_PILOT_COEFFS)
    ) dut_pilot (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(pilot_s_tdata),
        .s_axis_tvalid(pilot_s_tvalid),
        .s_axis_tready(pilot_s_tready),
        .s_axis_tlast(pilot_s_tlast),
        .m_axis_tdata(pilot_m_tdata),
        .m_axis_tvalid(pilot_m_tvalid),
        .m_axis_tready(pilot_m_tready),
        .m_axis_tlast(pilot_m_tlast)
    );

    assign pilot_m_tready = 1'b1;

    // ---------------- HP ----------------
    logic signed [DATA_W-1:0] hp_s_tdata;
    logic                     hp_s_tvalid;
    logic                     hp_s_tready;
    logic                     hp_s_tlast;
    logic signed [DATA_W-1:0] hp_m_tdata;
    logic                     hp_m_tvalid;
    logic                     hp_m_tready;
    logic                     hp_m_tlast;

    reg signed [DATA_W-1:0] hp_in_mem   [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] hp_gold_mem [0:N_SAMPLES_MAX-1];
    integer hp_n_in, hp_n_gold, hp_idx, hp_out_count, hp_err, hp_match;
    integer hp_fd_in, hp_fd_gold, hp_fd_out, hp_r;
    reg [31:0] hp_word;
    reg signed [31:0] hp_exp, hp_diff;
    integer hp_min_diff, hp_max_diff, hp_max_abs, hp_abs;
    longint hp_sum_diff, hp_sum_abs;
    logic hp_done;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(HP_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(HP_COEFFS)
    ) dut_hp (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(hp_s_tdata),
        .s_axis_tvalid(hp_s_tvalid),
        .s_axis_tready(hp_s_tready),
        .s_axis_tlast(hp_s_tlast),
        .m_axis_tdata(hp_m_tdata),
        .m_axis_tvalid(hp_m_tvalid),
        .m_axis_tready(hp_m_tready),
        .m_axis_tlast(hp_m_tlast)
    );

    assign hp_m_tready = 1'b1;

    // ---------------- AUDIO_LMR ----------------
    logic signed [DATA_W-1:0] lmr_s_tdata;
    logic                     lmr_s_tvalid;
    logic                     lmr_s_tready;
    logic                     lmr_s_tlast;
    logic signed [DATA_W-1:0] lmr_m_tdata;
    logic                     lmr_m_tvalid;
    logic                     lmr_m_tready;
    logic                     lmr_m_tlast;

    reg signed [DATA_W-1:0] lmr_in_mem   [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] lmr_gold_mem [0:N_SAMPLES_MAX-1];
    integer lmr_n_in, lmr_n_gold, lmr_idx, lmr_out_count, lmr_err, lmr_match;
    integer lmr_fd_in, lmr_fd_gold, lmr_fd_out, lmr_r;
    reg [31:0] lmr_word;
    reg signed [31:0] lmr_exp, lmr_diff;
    integer lmr_min_diff, lmr_max_diff, lmr_max_abs, lmr_abs;
    longint lmr_sum_diff, lmr_sum_abs;
    logic lmr_done;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(AUDIO_LMR_COEFF_TAPS),
        .DECIM(AUDIO_DECIM),
        .SCALE_SHIFT(BITS),
        .COEFFS(AUDIO_LMR_COEFFS)
    ) dut_lmr (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(lmr_s_tdata),
        .s_axis_tvalid(lmr_s_tvalid),
        .s_axis_tready(lmr_s_tready),
        .s_axis_tlast(lmr_s_tlast),
        .m_axis_tdata(lmr_m_tdata),
        .m_axis_tvalid(lmr_m_tvalid),
        .m_axis_tready(lmr_m_tready),
        .m_axis_tlast(lmr_m_tlast)
    );

    assign lmr_m_tready = 1'b1;

    // =========================================================
    // File loading
    // =========================================================
    initial begin
        // AUDIO_LPR
        lpr_n_in = 0;
        lpr_fd_in = $fopen("gold_02_demod.txt", "r");
        while ((!$feof(lpr_fd_in)) && (lpr_n_in < N_SAMPLES_MAX)) begin
            lpr_r = $fscanf(lpr_fd_in, "%h\n", lpr_word);
            if (lpr_r == 1) begin
                lpr_in_mem[lpr_n_in] = $signed(lpr_word);
                lpr_n_in = lpr_n_in + 1;
            end
        end
        $fclose(lpr_fd_in);

        lpr_n_gold = 0;
        lpr_fd_gold = $fopen("gold_03_audio_lpr.txt", "r");
        while ((!$feof(lpr_fd_gold)) && (lpr_n_gold < N_SAMPLES_MAX)) begin
            lpr_r = $fscanf(lpr_fd_gold, "%h\n", lpr_word);
            if (lpr_r == 1) begin
                lpr_gold_mem[lpr_n_gold] = $signed(lpr_word);
                lpr_n_gold = lpr_n_gold + 1;
            end
        end
        $fclose(lpr_fd_gold);

        // BP_LMR
        bplmr_n_in = 0;
        bplmr_fd_in = $fopen("gold_02_demod.txt", "r");
        while ((!$feof(bplmr_fd_in)) && (bplmr_n_in < N_SAMPLES_MAX)) begin
            bplmr_r = $fscanf(bplmr_fd_in, "%h\n", bplmr_word);
            if (bplmr_r == 1) begin
                bplmr_in_mem[bplmr_n_in] = $signed(bplmr_word);
                bplmr_n_in = bplmr_n_in + 1;
            end
        end
        $fclose(bplmr_fd_in);

        bplmr_n_gold = 0;
        bplmr_fd_gold = $fopen("gold_04_bp_lmr.txt", "r");
        while ((!$feof(bplmr_fd_gold)) && (bplmr_n_gold < N_SAMPLES_MAX)) begin
            bplmr_r = $fscanf(bplmr_fd_gold, "%h\n", bplmr_word);
            if (bplmr_r == 1) begin
                bplmr_gold_mem[bplmr_n_gold] = $signed(bplmr_word);
                bplmr_n_gold = bplmr_n_gold + 1;
            end
        end
        $fclose(bplmr_fd_gold);

        // BP_PILOT
        pilot_n_in = 0;
        pilot_fd_in = $fopen("gold_02_demod.txt", "r");
        while ((!$feof(pilot_fd_in)) && (pilot_n_in < N_SAMPLES_MAX)) begin
            pilot_r = $fscanf(pilot_fd_in, "%h\n", pilot_word);
            if (pilot_r == 1) begin
                pilot_in_mem[pilot_n_in] = $signed(pilot_word);
                pilot_n_in = pilot_n_in + 1;
            end
        end
        $fclose(pilot_fd_in);

        pilot_n_gold = 0;
        pilot_fd_gold = $fopen("gold_05_bp_pilot.txt", "r");
        while ((!$feof(pilot_fd_gold)) && (pilot_n_gold < N_SAMPLES_MAX)) begin
            pilot_r = $fscanf(pilot_fd_gold, "%h\n", pilot_word);
            if (pilot_r == 1) begin
                pilot_gold_mem[pilot_n_gold] = $signed(pilot_word);
                pilot_n_gold = pilot_n_gold + 1;
            end
        end
        $fclose(pilot_fd_gold);

        // HP
        hp_n_in = 0;
        hp_fd_in = $fopen("gold_06_square.txt", "r");
        while ((!$feof(hp_fd_in)) && (hp_n_in < N_SAMPLES_MAX)) begin
            hp_r = $fscanf(hp_fd_in, "%h\n", hp_word);
            if (hp_r == 1) begin
                hp_in_mem[hp_n_in] = $signed(hp_word);
                hp_n_in = hp_n_in + 1;
            end
        end
        $fclose(hp_fd_in);

        hp_n_gold = 0;
        hp_fd_gold = $fopen("gold_07_hp_pilot.txt", "r");
        while ((!$feof(hp_fd_gold)) && (hp_n_gold < N_SAMPLES_MAX)) begin
            hp_r = $fscanf(hp_fd_gold, "%h\n", hp_word);
            if (hp_r == 1) begin
                hp_gold_mem[hp_n_gold] = $signed(hp_word);
                hp_n_gold = hp_n_gold + 1;
            end
        end
        $fclose(hp_fd_gold);

        // AUDIO_LMR
        lmr_n_in = 0;
        lmr_fd_in = $fopen("gold_08_multiply.txt", "r");
        while ((!$feof(lmr_fd_in)) && (lmr_n_in < N_SAMPLES_MAX)) begin
            lmr_r = $fscanf(lmr_fd_in, "%h\n", lmr_word);
            if (lmr_r == 1) begin
                lmr_in_mem[lmr_n_in] = $signed(lmr_word);
                lmr_n_in = lmr_n_in + 1;
            end
        end
        $fclose(lmr_fd_in);

        lmr_n_gold = 0;
        lmr_fd_gold = $fopen("gold_09_audio_lmr.txt", "r");
        while ((!$feof(lmr_fd_gold)) && (lmr_n_gold < N_SAMPLES_MAX)) begin
            lmr_r = $fscanf(lmr_fd_gold, "%h\n", lmr_word);
            if (lmr_r == 1) begin
                lmr_gold_mem[lmr_n_gold] = $signed(lmr_word);
                lmr_n_gold = lmr_n_gold + 1;
            end
        end
        $fclose(lmr_fd_gold);
    end

    // =========================================================
    // Reset / init
    // =========================================================
    initial begin
        lpr_fd_out   = $fopen("sv_audio_lpr_out.txt", "w");
        bplmr_fd_out = $fopen("sv_bp_lmr_out.txt", "w");
        pilot_fd_out = $fopen("sv_bp_pilot_out.txt", "w");
        hp_fd_out    = $fopen("sv_hp_out.txt", "w");
        lmr_fd_out   = $fopen("sv_audio_lmr_out.txt", "w");

        rst_n = 1'b0;

        lpr_s_tdata = '0;   lpr_s_tvalid = 0;   lpr_s_tlast = 0;
        bplmr_s_tdata = '0; bplmr_s_tvalid = 0; bplmr_s_tlast = 0;
        pilot_s_tdata = '0; pilot_s_tvalid = 0; pilot_s_tlast = 0;
        hp_s_tdata = '0;    hp_s_tvalid = 0;    hp_s_tlast = 0;
        lmr_s_tdata = '0;   lmr_s_tvalid = 0;   lmr_s_tlast = 0;

        lpr_idx = 0; lpr_out_count = 0; lpr_err = 0; lpr_match = 0; lpr_done = 0;
        lpr_min_diff = 2147483647; lpr_max_diff = -2147483647; lpr_max_abs = 0; lpr_sum_diff = 0; lpr_sum_abs = 0;

        bplmr_idx = 0; bplmr_out_count = 0; bplmr_err = 0; bplmr_match = 0; bplmr_done = 0;
        bplmr_min_diff = 2147483647; bplmr_max_diff = -2147483647; bplmr_max_abs = 0; bplmr_sum_diff = 0; bplmr_sum_abs = 0;

        pilot_idx = 0; pilot_out_count = 0; pilot_err = 0; pilot_match = 0; pilot_done = 0;
        pilot_min_diff = 2147483647; pilot_max_diff = -2147483647; pilot_max_abs = 0; pilot_sum_diff = 0; pilot_sum_abs = 0;

        hp_idx = 0; hp_out_count = 0; hp_err = 0; hp_match = 0; hp_done = 0;
        hp_min_diff = 2147483647; hp_max_diff = -2147483647; hp_max_abs = 0; hp_sum_diff = 0; hp_sum_abs = 0;

        lmr_idx = 0; lmr_out_count = 0; lmr_err = 0; lmr_match = 0; lmr_done = 0;
        lmr_min_diff = 2147483647; lmr_max_diff = -2147483647; lmr_max_abs = 0; lmr_sum_diff = 0; lmr_sum_abs = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    // =========================================================
    // Drive all five inputs in parallel
    // =========================================================
    always @(negedge clk) begin
        if (rst_n) begin
            if (!lpr_done) begin
                if (lpr_idx < lpr_n_in && lpr_s_tready) begin
                    lpr_s_tdata  <= lpr_in_mem[lpr_idx];
                    lpr_s_tvalid <= 1'b1;
                    lpr_s_tlast  <= (lpr_idx == lpr_n_in - 1);
                    lpr_idx      <= lpr_idx + 1;
                end else begin
                    lpr_s_tvalid <= 1'b0;
                    lpr_s_tlast  <= 1'b0;
                end
            end

            if (!bplmr_done) begin
                if (bplmr_idx < bplmr_n_in && bplmr_s_tready) begin
                    bplmr_s_tdata  <= bplmr_in_mem[bplmr_idx];
                    bplmr_s_tvalid <= 1'b1;
                    bplmr_s_tlast  <= (bplmr_idx == bplmr_n_in - 1);
                    bplmr_idx      <= bplmr_idx + 1;
                end else begin
                    bplmr_s_tvalid <= 1'b0;
                    bplmr_s_tlast  <= 1'b0;
                end
            end

            if (!pilot_done) begin
                if (pilot_idx < pilot_n_in && pilot_s_tready) begin
                    pilot_s_tdata  <= pilot_in_mem[pilot_idx];
                    pilot_s_tvalid <= 1'b1;
                    pilot_s_tlast  <= (pilot_idx == pilot_n_in - 1);
                    pilot_idx      <= pilot_idx + 1;
                end else begin
                    pilot_s_tvalid <= 1'b0;
                    pilot_s_tlast  <= 1'b0;
                end
            end

            if (!hp_done) begin
                if (hp_idx < hp_n_in && hp_s_tready) begin
                    hp_s_tdata  <= hp_in_mem[hp_idx];
                    hp_s_tvalid <= 1'b1;
                    hp_s_tlast  <= (hp_idx == hp_n_in - 1);
                    hp_idx      <= hp_idx + 1;
                end else begin
                    hp_s_tvalid <= 1'b0;
                    hp_s_tlast  <= 1'b0;
                end
            end

            if (!lmr_done) begin
                if (lmr_idx < lmr_n_in && lmr_s_tready) begin
                    lmr_s_tdata  <= lmr_in_mem[lmr_idx];
                    lmr_s_tvalid <= 1'b1;
                    lmr_s_tlast  <= (lmr_idx == lmr_n_in - 1);
                    lmr_idx      <= lmr_idx + 1;
                end else begin
                    lmr_s_tvalid <= 1'b0;
                    lmr_s_tlast  <= 1'b0;
                end
            end
        end
    end

    // =========================================================
    // Check outputs
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && lpr_m_tvalid && lpr_m_tready) begin
            $fwrite(lpr_fd_out, "%08h\n", $unsigned(lpr_m_tdata));
            if (lpr_out_count < lpr_n_gold) begin
                lpr_exp  = lpr_gold_mem[lpr_out_count];
                lpr_diff = lpr_m_tdata - lpr_exp;
                if (lpr_diff < lpr_min_diff) lpr_min_diff = lpr_diff;
                if (lpr_diff > lpr_max_diff) lpr_max_diff = lpr_diff;
                lpr_abs = (lpr_diff < 0) ? -lpr_diff : lpr_diff;
                if (lpr_abs > lpr_max_abs) lpr_max_abs = lpr_abs;
                lpr_sum_diff = lpr_sum_diff + lpr_diff;
                lpr_sum_abs  = lpr_sum_abs + lpr_abs;
                if (lpr_diff == 0) lpr_match = lpr_match + 1;
                else begin
                    lpr_err = lpr_err + 1;
                    $display("[AUDIO_LPR] MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             lpr_out_count, $unsigned(lpr_m_tdata), $unsigned(lpr_exp), lpr_diff);
                end
            end
            lpr_out_count = lpr_out_count + 1;
            if (lpr_out_count >= lpr_n_gold) lpr_done = 1'b1;
        end

        if (rst_n && bplmr_m_tvalid && bplmr_m_tready) begin
            $fwrite(bplmr_fd_out, "%08h\n", $unsigned(bplmr_m_tdata));
            if (bplmr_out_count < bplmr_n_gold) begin
                bplmr_exp  = bplmr_gold_mem[bplmr_out_count];
                bplmr_diff = bplmr_m_tdata - bplmr_exp;
                if (bplmr_diff < bplmr_min_diff) bplmr_min_diff = bplmr_diff;
                if (bplmr_diff > bplmr_max_diff) bplmr_max_diff = bplmr_diff;
                bplmr_abs = (bplmr_diff < 0) ? -bplmr_diff : bplmr_diff;
                if (bplmr_abs > bplmr_max_abs) bplmr_max_abs = bplmr_abs;
                bplmr_sum_diff = bplmr_sum_diff + bplmr_diff;
                bplmr_sum_abs  = bplmr_sum_abs + bplmr_abs;
                if (bplmr_diff == 0) bplmr_match = bplmr_match + 1;
                else begin
                    bplmr_err = bplmr_err + 1;
                    $display("[BP_LMR] MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             bplmr_out_count, $unsigned(bplmr_m_tdata), $unsigned(bplmr_exp), bplmr_diff);
                end
            end
            bplmr_out_count = bplmr_out_count + 1;
            if (bplmr_out_count >= bplmr_n_gold) bplmr_done = 1'b1;
        end

        if (rst_n && pilot_m_tvalid && pilot_m_tready) begin
            $fwrite(pilot_fd_out, "%08h\n", $unsigned(pilot_m_tdata));
            if (pilot_out_count < pilot_n_gold) begin
                pilot_exp  = pilot_gold_mem[pilot_out_count];
                pilot_diff = pilot_m_tdata - pilot_exp;
                if (pilot_diff < pilot_min_diff) pilot_min_diff = pilot_diff;
                if (pilot_diff > pilot_max_diff) pilot_max_diff = pilot_diff;
                pilot_abs = (pilot_diff < 0) ? -pilot_diff : pilot_diff;
                if (pilot_abs > pilot_max_abs) pilot_max_abs = pilot_abs;
                pilot_sum_diff = pilot_sum_diff + pilot_diff;
                pilot_sum_abs  = pilot_sum_abs + pilot_abs;
                if (pilot_diff == 0) pilot_match = pilot_match + 1;
                else begin
                    pilot_err = pilot_err + 1;
                    $display("[BP_PILOT] MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             pilot_out_count, $unsigned(pilot_m_tdata), $unsigned(pilot_exp), pilot_diff);
                end
            end
            pilot_out_count = pilot_out_count + 1;
            if (pilot_out_count >= pilot_n_gold) pilot_done = 1'b1;
        end

        if (rst_n && hp_m_tvalid && hp_m_tready) begin
            $fwrite(hp_fd_out, "%08h\n", $unsigned(hp_m_tdata));
            if (hp_out_count < hp_n_gold) begin
                hp_exp  = hp_gold_mem[hp_out_count];
                hp_diff = hp_m_tdata - hp_exp;
                if (hp_diff < hp_min_diff) hp_min_diff = hp_diff;
                if (hp_diff > hp_max_diff) hp_max_diff = hp_diff;
                hp_abs = (hp_diff < 0) ? -hp_diff : hp_diff;
                if (hp_abs > hp_max_abs) hp_max_abs = hp_abs;
                hp_sum_diff = hp_sum_diff + hp_diff;
                hp_sum_abs  = hp_sum_abs + hp_abs;
                if (hp_diff == 0) hp_match = hp_match + 1;
                else begin
                    hp_err = hp_err + 1;
                    $display("[HP] MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             hp_out_count, $unsigned(hp_m_tdata), $unsigned(hp_exp), hp_diff);
                end
            end
            hp_out_count = hp_out_count + 1;
            if (hp_out_count >= hp_n_gold) hp_done = 1'b1;
        end

        if (rst_n && lmr_m_tvalid && lmr_m_tready) begin
            $fwrite(lmr_fd_out, "%08h\n", $unsigned(lmr_m_tdata));
            if (lmr_out_count < lmr_n_gold) begin
                lmr_exp  = lmr_gold_mem[lmr_out_count];
                lmr_diff = lmr_m_tdata - lmr_exp;
                if (lmr_diff < lmr_min_diff) lmr_min_diff = lmr_diff;
                if (lmr_diff > lmr_max_diff) lmr_max_diff = lmr_diff;
                lmr_abs = (lmr_diff < 0) ? -lmr_diff : lmr_diff;
                if (lmr_abs > lmr_max_abs) lmr_max_abs = lmr_abs;
                lmr_sum_diff = lmr_sum_diff + lmr_diff;
                lmr_sum_abs  = lmr_sum_abs + lmr_abs;
                if (lmr_diff == 0) lmr_match = lmr_match + 1;
                else begin
                    lmr_err = lmr_err + 1;
                    $display("[AUDIO_LMR] MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             lmr_out_count, $unsigned(lmr_m_tdata), $unsigned(lmr_exp), lmr_diff);
                end
            end
            lmr_out_count = lmr_out_count + 1;
            if (lmr_out_count >= lmr_n_gold) lmr_done = 1'b1;
        end
    end

    // =========================================================
    // Finish when all done
    // =========================================================
    initial begin
        wait (lpr_done && bplmr_done && pilot_done && hp_done && lmr_done);
        repeat (20) @(posedge clk);

        $fclose(lpr_fd_out);
        $fclose(bplmr_fd_out);
        $fclose(pilot_fd_out);
        $fclose(hp_fd_out);
        $fclose(lmr_fd_out);

        $display("====================================================");
        $display("ALL FIR REGRESSIONS DONE");

        $display("AUDIO_LPR  mismatches=%0d matches=%0d max_abs=%0d avg_abs=%0f",
                 lpr_err, lpr_match, lpr_max_abs,
                 (lpr_out_count > 0) ? ($itor(lpr_sum_abs) / lpr_out_count) : 0.0);

        $display("BP_LMR     mismatches=%0d matches=%0d max_abs=%0d avg_abs=%0f",
                 bplmr_err, bplmr_match, bplmr_max_abs,
                 (bplmr_out_count > 0) ? ($itor(bplmr_sum_abs) / bplmr_out_count) : 0.0);

        $display("BP_PILOT   mismatches=%0d matches=%0d max_abs=%0d avg_abs=%0f",
                 pilot_err, pilot_match, pilot_max_abs,
                 (pilot_out_count > 0) ? ($itor(pilot_sum_abs) / pilot_out_count) : 0.0);

        $display("HP         mismatches=%0d matches=%0d max_abs=%0d avg_abs=%0f",
                 hp_err, hp_match, hp_max_abs,
                 (hp_out_count > 0) ? ($itor(hp_sum_abs) / hp_out_count) : 0.0);

        $display("AUDIO_LMR  mismatches=%0d matches=%0d max_abs=%0d avg_abs=%0f",
                 lmr_err, lmr_match, lmr_max_abs,
                 (lmr_out_count > 0) ? ($itor(lmr_sum_abs) / lmr_out_count) : 0.0);

        if ((lpr_err == 0) && (bplmr_err == 0) && (pilot_err == 0) && (hp_err == 0) && (lmr_err == 0))
            $display("PASS");
        else
            $display("FAIL");

        $display("====================================================");
        $finish;
    end

endmodule