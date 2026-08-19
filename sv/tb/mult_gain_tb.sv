`timescale 1ns/1ps
import fm_radio_pkg::*;

module mult_gain_tb;

    localparam int DATA_W        = 32;
    localparam int N_SAMPLES_MAX = 2000000;

    logic clock;
    logic reset;

    // ---------------- multiply DUT ----------------
    logic                      mul_in_a_rd_en;
    logic                      mul_in_a_empty;
    logic signed [DATA_W-1:0]  mul_in_a_dout;

    logic                      mul_in_b_rd_en;
    logic                      mul_in_b_empty;
    logic signed [DATA_W-1:0]  mul_in_b_dout;

    logic                      mul_out_wr_en;
    logic                      mul_out_full;
    logic signed [DATA_W-1:0]  mul_out_din;

    // ---------------- gain DUT ----------------
    logic                      gain_in_a_rd_en;
    logic                      gain_in_a_empty;
    logic signed [DATA_W-1:0]  gain_in_a_dout;

    logic                      gain_in_b_rd_en;
    logic                      gain_in_b_empty;
    logic signed [DATA_W-1:0]  gain_in_b_dout;

    logic                      gain_out_wr_en;
    logic                      gain_out_full;
    logic signed [DATA_W-1:0]  gain_out_din;

    reg signed [DATA_W-1:0] mul_a_mem      [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] mul_b_mem      [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] mul_golden_mem [0:N_SAMPLES_MAX-1];

    reg signed [DATA_W-1:0] gain_a_mem      [0:N_SAMPLES_MAX-1];
    reg signed [DATA_W-1:0] gain_golden_mem [0:N_SAMPLES_MAX-1];

    integer n_mul_a, n_mul_b, n_mul_golden;
    integer n_gain_a, n_gain_golden;

    integer mul_a_idx, mul_b_idx, mul_out_idx;
    integer gain_a_idx, gain_out_idx;

    integer mul_err_count, gain_err_count;

    integer fd_mul_a, fd_mul_b, fd_mul_g, fd_gain_a, fd_gain_g;
    integer fd_mul_out, fd_gain_out;
    integer r;
    reg [31:0] word_tmp;

    reg signed [31:0] expected_word;
    reg signed [31:0] diff;

    mult_gain #(
        .DATA_W(DATA_W),
        .BITS(BITS),
        .POST_SHIFT(0)
    ) dut_mult (
        .clock(clock),
        .reset(reset),

        .in_a_rd_en(mul_in_a_rd_en),
        .in_a_empty(mul_in_a_empty),
        .in_a_dout(mul_in_a_dout),

        .in_b_rd_en(mul_in_b_rd_en),
        .in_b_empty(mul_in_b_empty),
        .in_b_dout(mul_in_b_dout),

        .out_wr_en(mul_out_wr_en),
        .out_full(mul_out_full),
        .out_din(mul_out_din)
    );

    mult_gain #(
        .DATA_W(DATA_W),
        .BITS(BITS),
        .POST_SHIFT(14-BITS)
    ) dut_gain (
        .clock(clock),
        .reset(reset),

        .in_a_rd_en(gain_in_a_rd_en),
        .in_a_empty(gain_in_a_empty),
        .in_a_dout(gain_in_a_dout),

        .in_b_rd_en(gain_in_b_rd_en),
        .in_b_empty(gain_in_b_empty),
        .in_b_dout(gain_in_b_dout),

        .out_wr_en(gain_out_wr_en),
        .out_full(gain_out_full),
        .out_din(gain_out_din)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    task automatic load_file(
        input string fname,
        output integer count,
        output reg signed [DATA_W-1:0] mem [0:N_SAMPLES_MAX-1]
    );
        integer fd_local;
        begin
            count = 0;
            fd_local = $fopen(fname, "r");
            if (fd_local == 0) begin
                $display("ERROR: could not open %s", fname);
                $finish;
            end
            while ((!$feof(fd_local)) && (count < N_SAMPLES_MAX)) begin
                r = $fscanf(fd_local, "%h\n", word_tmp);
                if (r == 1) begin
                    mem[count] = $signed(word_tmp);
                    count = count + 1;
                end
            end
            $fclose(fd_local);
        end
    endtask

    // ---------------- source models ----------------
    always_comb begin
        mul_in_a_empty = (mul_a_idx >= n_mul_a);
        mul_in_b_empty = (mul_b_idx >= n_mul_b);

        mul_in_a_dout  = mul_in_a_empty ? '0 : mul_a_mem[mul_a_idx];
        mul_in_b_dout  = mul_in_b_empty ? '0 : mul_b_mem[mul_b_idx];

        gain_in_a_empty = (gain_a_idx >= n_gain_a);
        gain_in_b_empty = 1'b0;

        gain_in_a_dout  = gain_in_a_empty ? '0 : gain_a_mem[gain_a_idx];
        gain_in_b_dout  = VOLUME_LEVEL;

        mul_out_full  = 1'b0;
        gain_out_full = 1'b0;
    end

    always @(posedge clock) begin
        if (!reset) begin
            if (mul_in_a_rd_en && !mul_in_a_empty) mul_a_idx <= mul_a_idx + 1;
            if (mul_in_b_rd_en && !mul_in_b_empty) mul_b_idx <= mul_b_idx + 1;

            if (gain_in_a_rd_en && !gain_in_a_empty) gain_a_idx <= gain_a_idx + 1;
        end
    end

    // ---------------- multiply checker ----------------
    always @(posedge clock) begin
        if (!reset && mul_out_wr_en) begin
            $fwrite(fd_mul_out, "%08h\n", $unsigned(mul_out_din));

            if (mul_out_idx >= n_mul_golden) begin
                $display("MULT ERROR: extra output @ %0d got %08h",
                         mul_out_idx, $unsigned(mul_out_din));
                mul_err_count <= mul_err_count + 1;
            end else begin
                expected_word = mul_golden_mem[mul_out_idx];
                diff = mul_out_din - expected_word;
                if (diff != 0) begin
                    mul_err_count = mul_err_count + 1;
                    $display("MULT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             mul_out_idx,
                             $unsigned(mul_out_din),
                             $unsigned(expected_word),
                             diff);
                end
            end

            mul_out_idx <= mul_out_idx + 1;
        end
    end

    // ---------------- gain checker ----------------
    always @(posedge clock) begin
        if (!reset && gain_out_wr_en) begin
            $fwrite(fd_gain_out, "%08h\n", $unsigned(gain_out_din));

            if (gain_out_idx >= n_gain_golden) begin
                $display("GAIN ERROR: extra output @ %0d got %08h",
                         gain_out_idx, $unsigned(gain_out_din));
                gain_err_count <= gain_err_count + 1;
            end else begin
                expected_word = gain_golden_mem[gain_out_idx];
                diff = gain_out_din - expected_word;
                if (diff != 0) begin
                    gain_err_count = gain_err_count + 1;
                    $display("GAIN MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                             gain_out_idx,
                             $unsigned(gain_out_din),
                             $unsigned(expected_word),
                             diff);
                end
            end

            gain_out_idx <= gain_out_idx + 1;
        end
    end

    initial begin
        load_file("gold_07_hp_pilot.txt",    n_mul_a,      mul_a_mem);
        load_file("gold_04_bp_lmr.txt",      n_mul_b,      mul_b_mem);
        load_file("gold_08_multiply.txt",    n_mul_golden, mul_golden_mem);

        load_file("gold_11_left_deemph.txt", n_gain_a,      gain_a_mem);
        load_file("gold_12_left_gain.txt",   n_gain_golden, gain_golden_mem);

        fd_mul_out  = $fopen("sv_mult_out.txt", "w");
        fd_gain_out = $fopen("sv_gain_out.txt", "w");

        if ((fd_mul_out == 0) || (fd_gain_out == 0)) begin
            $display("ERROR: could not open output files");
            $finish;
        end

        reset = 1'b1;

        mul_a_idx     = 0;
        mul_b_idx     = 0;
        mul_out_idx   = 0;
        gain_a_idx    = 0;
        gain_out_idx  = 0;

        mul_err_count  = 0;
        gain_err_count = 0;

        repeat (5) @(posedge clock);
        reset = 1'b0;

        wait ((mul_out_idx >= n_mul_golden) && (gain_out_idx >= n_gain_golden));

        repeat (10) @(posedge clock);

        $fclose(fd_mul_out);
        $fclose(fd_gain_out);

        $display("====================================================");
        $display("MULT path:");
        $display("  input count   : %0d", n_mul_a);
        $display("  output count  : %0d", mul_out_idx);
        $display("  mismatches    : %0d", mul_err_count);

        $display("GAIN path:");
        $display("  input count   : %0d", n_gain_a);
        $display("  output count  : %0d", gain_out_idx);
        $display("  mismatches    : %0d", gain_err_count);
        $display("====================================================");

        if ((mul_err_count == 0) && (gain_err_count == 0))
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

endmodule