`timescale 1ns/1ps

module post_demod_fir_tb;

    localparam int DATA_W      = 32;
    localparam int COEFF_W     = 16;
    localparam int ACC_W       = 56;
    localparam int TAPS        = 32;
    localparam int SCALE_SHIFT = 10;

    localparam int N_SAMPLES_MAX = 1000000;

    logic clk;
    logic rst_n;

    logic signed [DATA_W-1:0] demod_data;
    logic                     demod_valid;
    logic                     demod_ready;
    logic                     demod_last;

    logic signed [DATA_W-1:0] audio_lpr_data;
    logic                     audio_lpr_valid;
    logic                     audio_lpr_ready;
    logic                     audio_lpr_last;

    logic signed [DATA_W-1:0] bp_pilot_data;
    logic                     bp_pilot_valid;
    logic                     bp_pilot_ready;
    logic                     bp_pilot_last;

    logic signed [DATA_W-1:0] bp_lmr_data;
    logic                     bp_lmr_valid;
    logic                     bp_lmr_ready;
    logic                     bp_lmr_last;

    reg [31:0] demod_mem [0:N_SAMPLES_MAX-1];

    integer n_samples;
    integer fd_in;
    integer fd_lpr;
    integer fd_pilot;
    integer fd_lmr;
    integer r;

    integer idx;
    integer lpr_count;
    integer pilot_count;
    integer lmr_count;

    reg [31:0] word_tmp;

    post_demod_fir_top #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .SCALE_SHIFT(SCALE_SHIFT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .demod_data(demod_data),
        .demod_valid(demod_valid),
        .demod_ready(demod_ready),
        .demod_last(demod_last),

        .audio_lpr_data(audio_lpr_data),
        .audio_lpr_valid(audio_lpr_valid),
        .audio_lpr_ready(audio_lpr_ready),
        .audio_lpr_last(audio_lpr_last),

        .bp_pilot_data(bp_pilot_data),
        .bp_pilot_valid(bp_pilot_valid),
        .bp_pilot_ready(bp_pilot_ready),
        .bp_pilot_last(bp_pilot_last),

        .bp_lmr_data(bp_lmr_data),
        .bp_lmr_valid(bp_lmr_valid),
        .bp_lmr_ready(bp_lmr_ready),
        .bp_lmr_last(bp_lmr_last)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic load_demod_file;
        begin
            n_samples = 0;
            fd_in = $fopen("stage_demod.txt", "r");
            if (fd_in == 0) begin
                $display("ERROR: could not open stage_demod.txt");
                $finish;
            end

            while (!$feof(fd_in) && n_samples < N_SAMPLES_MAX) begin
                r = $fscanf(fd_in, "%h\n", word_tmp);
                if (r == 1) begin
                    demod_mem[n_samples] = word_tmp;
                    n_samples = n_samples + 1;
                end
            end

            $fclose(fd_in);
            $display("Loaded %0d demod samples from stage_demod.txt", n_samples);

            if (n_samples == 0) begin
                $display("ERROR: no samples loaded from stage_demod.txt");
                $finish;
            end
        end
    endtask

    initial begin
        load_demod_file();

        fd_lpr   = $fopen("sv_audio_lpr.txt", "w");
        fd_pilot = $fopen("sv_bp_pilot.txt", "w");
        fd_lmr   = $fopen("sv_bp_lmr.txt", "w");

        if (fd_lpr == 0 || fd_pilot == 0 || fd_lmr == 0) begin
            $display("ERROR: could not open one or more output files");
            $finish;
        end

        rst_n          = 1'b0;
        demod_data     = '0;
        demod_valid    = 1'b0;
        demod_last     = 1'b0;

        audio_lpr_ready = 1'b1;
        bp_pilot_ready  = 1'b1;
        bp_lmr_ready    = 1'b1;

        lpr_count   = 0;
        pilot_count = 0;
        lmr_count   = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (idx = 0; idx < n_samples; idx = idx + 1) begin
            @(posedge clk);

            demod_data  <= $signed(demod_mem[idx]);
            demod_valid <= 1'b1;
            demod_last  <= (idx == n_samples-1);

            while (!demod_ready) begin
                @(posedge clk);
            end
        end

        @(posedge clk);
        demod_valid <= 1'b0;
        demod_last  <= 1'b0;
        demod_data  <= '0;

        repeat (300) @(posedge clk);

        $fclose(fd_lpr);
        $fclose(fd_pilot);
        $fclose(fd_lmr);

        $display("Done.");
        $display("  audio_lpr outputs : %0d", lpr_count);
        $display("  bp_pilot outputs  : %0d", pilot_count);
        $display("  bp_lmr outputs    : %0d", lmr_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && audio_lpr_valid && audio_lpr_ready) begin
            $fwrite(fd_lpr, "%08h\n", $unsigned(audio_lpr_data));
            lpr_count <= lpr_count + 1;
        end

        if (rst_n && bp_pilot_valid && bp_pilot_ready) begin
            $fwrite(fd_pilot, "%08h\n", $unsigned(bp_pilot_data));
            pilot_count <= pilot_count + 1;
        end

        if (rst_n && bp_lmr_valid && bp_lmr_ready) begin
            $fwrite(fd_lmr, "%08h\n", $unsigned(bp_lmr_data));
            lmr_count <= lmr_count + 1;
        end
    end

endmodule