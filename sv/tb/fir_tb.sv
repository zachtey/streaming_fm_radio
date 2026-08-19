`timescale 1ns/1ps

// ============================================================
// Generic reusable FIR testbench
// ============================================================
module fir_tb #(
    parameter int DATA_W        = 32,
    parameter int COEFF_W       = 32,
    parameter int ACC_W         = 48,
    parameter int TAPS          = 32,
    parameter int DECIM         = 1,
    parameter int SCALE_SHIFT   = 10,
    parameter int N_SAMPLES_MAX = 2000000,

    parameter string COEFF_FILE  = "fir.mem",
    parameter string INPUT_FILE  = "gold_input.txt",
    parameter string GOLDEN_FILE = "gold_output.txt",
    parameter string OUTPUT_FILE = "sv_fir_out.txt",
    parameter string TEST_NAME   = "fir_test"
)(
);

    logic                     clk;
    logic                     rst_n;

    logic signed [DATA_W-1:0] s_axis_tdata;
    logic                     s_axis_tvalid;
    logic                     s_axis_tready;
    logic                     s_axis_tlast;

    logic signed [DATA_W-1:0] m_axis_tdata;
    logic                     m_axis_tvalid;
    logic                     m_axis_tready;
    logic                     m_axis_tlast;

    reg signed [DATA_W-1:0] input_mem [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] gold_mem  [0:N_SAMPLES_MAX-1];

    integer n_input, n_golden;
    integer fd_in, fd_gold, fd_out;
    integer r, idx;
    reg [31:0] word_tmp;

    integer out_count;
    integer err_count;
    integer match_count;

    integer min_diff;
    integer max_diff;
    integer max_abs_diff;
    integer abs_diff_int;

    longint sum_signed_diff;
    longint sum_abs_diff;

    reg signed [31:0] expected_word;
    reg signed [31:0] diff;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(DECIM),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE(COEFF_FILE)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    assign m_axis_tready = 1'b1;

    task automatic load_input_file;
        begin
            n_input = 0;
            fd_in = $fopen(INPUT_FILE, "r");
            if (fd_in == 0) begin
                $display("ERROR [%s]: could not open input file %s", TEST_NAME, INPUT_FILE);
                $finish;
            end

            while ((!$feof(fd_in)) && (n_input < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_in, "%h\n", word_tmp);
                if (r == 1) begin
                    input_mem[n_input] = $signed(word_tmp[DATA_W-1:0]);
                    n_input = n_input + 1;
                end
            end
            $fclose(fd_in);
        end
    endtask

    task automatic load_golden_file;
        begin
            n_golden = 0;
            fd_gold = $fopen(GOLDEN_FILE, "r");
            if (fd_gold == 0) begin
                $display("ERROR [%s]: could not open golden file %s", TEST_NAME, GOLDEN_FILE);
                $finish;
            end

            while ((!$feof(fd_gold)) && (n_golden < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_gold, "%h\n", word_tmp);
                if (r == 1) begin
                    gold_mem[n_golden] = $signed(word_tmp[DATA_W-1:0]);
                    n_golden = n_golden + 1;
                end
            end
            $fclose(fd_gold);
        end
    endtask

    initial begin
        load_input_file();
        load_golden_file();

        fd_out = $fopen(OUTPUT_FILE, "w");
        if (fd_out == 0) begin
            $display("ERROR [%s]: could not open output file %s", TEST_NAME, OUTPUT_FILE);
            $finish;
        end

        rst_n         = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        out_count      = 0;
        err_count      = 0;
        match_count    = 0;
        min_diff       = 2147483647;
        max_diff       = -2147483647;
        max_abs_diff   = 0;
        sum_signed_diff = 0;
        sum_abs_diff    = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        idx = 0;
        while (idx < n_input) begin
            @(negedge clk);
            if (s_axis_tready) begin
                s_axis_tdata  = input_mem[idx];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (idx == (n_input - 1));
                idx           = idx + 1;
            end else begin
                s_axis_tdata  = '0;
                s_axis_tvalid = 1'b0;
                s_axis_tlast  = 1'b0;
            end
        end

        @(negedge clk);
        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        wait (out_count >= n_golden);
        repeat (20) @(posedge clk);

        $fclose(fd_out);

        $display("====================================================");
        $display("FIR TB done: %s", TEST_NAME);
        $display("Input samples fed    : %0d", n_input);
        $display("Golden outputs read  : %0d", n_golden);
        $display("DUT outputs seen     : %0d", out_count);
        $display("Mismatches           : %0d", err_count);
        $display("Exact matches        : %0d", match_count);
        if (out_count > 0) begin
            $display("Min signed diff      : %0d", min_diff);
            $display("Max signed diff      : %0d", max_diff);
            $display("Max abs diff         : %0d", max_abs_diff);
            $display("Avg signed diff      : %0f", $itor(sum_signed_diff) / out_count);
            $display("Avg abs diff         : %0f", $itor(sum_abs_diff) / out_count);
        end
        $display("====================================================");

        if (err_count == 0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && m_axis_tvalid && m_axis_tready) begin
            $fwrite(fd_out, "%08h\n", $unsigned(m_axis_tdata));

            if (out_count >= n_golden) begin
                $display("ERROR [%s]: extra output at index %0d: got %08h",
                         TEST_NAME, out_count, $unsigned(m_axis_tdata));
                err_count = err_count + 1;
            end else begin
                expected_word = gold_mem[out_count];
                diff          = m_axis_tdata - expected_word;

                if (diff < min_diff) min_diff = diff;
                if (diff > max_diff) max_diff = diff;

                abs_diff_int = (diff < 0) ? -diff : diff;
                if (abs_diff_int > max_abs_diff) max_abs_diff = abs_diff_int;

                sum_signed_diff = sum_signed_diff + diff;
                sum_abs_diff    = sum_abs_diff + abs_diff_int;

                if (diff == 0) begin
                    match_count = match_count + 1;
                end else begin
                    err_count = err_count + 1;
                    $display("[%s] MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             TEST_NAME,
                             out_count,
                             $unsigned(m_axis_tdata),
                             $unsigned(expected_word),
                             diff);
                end
            end

            out_count = out_count + 1;
        end
    end

endmodule


// ============================================================
// Wrapper: AUDIO_LPR FIR
// input  = gold_02_demod.txt
// output = gold_03_audio_lpr.txt
// ============================================================
module fir_tb_audio_lpr;
    fir_tb #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(32),
        .DECIM(8),
        .SCALE_SHIFT(10),
        .COEFF_FILE("audio_lpr.mem"),
        .INPUT_FILE("gold_02_demod.txt"),
        .GOLDEN_FILE("gold_03_audio_lpr.txt"),
        .OUTPUT_FILE("sv_audio_lpr_out.txt"),
        .TEST_NAME("AUDIO_LPR")
    ) tb();
endmodule


// ============================================================
// Wrapper: BP_LMR FIR
// input  = gold_02_demod.txt
// output = gold_04_bp_lmr.txt
// ============================================================
module fir_tb_bp_lmr;
    fir_tb #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(32),
        .DECIM(1),
        .SCALE_SHIFT(10),
        .COEFF_FILE("bp_lmr.mem"),
        .INPUT_FILE("gold_02_demod.txt"),
        .GOLDEN_FILE("gold_04_bp_lmr.txt"),
        .OUTPUT_FILE("sv_bp_lmr_out.txt"),
        .TEST_NAME("BP_LMR")
    ) tb();
endmodule


// ============================================================
// Wrapper: BP_PILOT FIR
// input  = gold_02_demod.txt
// output = gold_05_bp_pilot.txt
// ============================================================
module fir_tb_bp_pilot;
    fir_tb #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(32),
        .DECIM(1),
        .SCALE_SHIFT(10),
        .COEFF_FILE("bp_pilot.mem"),
        .INPUT_FILE("gold_02_demod.txt"),
        .GOLDEN_FILE("gold_05_bp_pilot.txt"),
        .OUTPUT_FILE("sv_bp_pilot_out.txt"),
        .TEST_NAME("BP_PILOT")
    ) tb();
endmodule


// ============================================================
// Wrapper: HP FIR
// input  = gold_06_square.txt
// output = gold_07_hp_pilot.txt
// ============================================================
module fir_tb_hp;
    fir_tb #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(32),
        .DECIM(1),
        .SCALE_SHIFT(10),
        .COEFF_FILE("hp.mem"),
        .INPUT_FILE("gold_06_square.txt"),
        .GOLDEN_FILE("gold_07_hp_pilot.txt"),
        .OUTPUT_FILE("sv_hp_out.txt"),
        .TEST_NAME("HP")
    ) tb();
endmodule


// ============================================================
// Wrapper: AUDIO_LMR FIR
// input  = gold_08_multiply.txt
// output = gold_09_audio_lmr.txt
// ============================================================
module fir_tb_audio_lmr;
    fir_tb #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(32),
        .DECIM(8),
        .SCALE_SHIFT(10),
        .COEFF_FILE("audio_lmr.mem"),
        .INPUT_FILE("gold_08_multiply.txt"),
        .GOLDEN_FILE("gold_09_audio_lmr.txt"),
        .OUTPUT_FILE("sv_audio_lmr_out.txt"),
        .TEST_NAME("AUDIO_LMR")
    ) tb();
endmodule