`timescale 1ns/1ps

module channel_fir_tb;

    localparam int DATA_W      = 16;
    localparam int COEFF_W     = 16;
    localparam int ACC_W       = 48;
    localparam int TAPS        = 20;
    localparam int DECIM       = 1;
    localparam int SCALE_SHIFT = 15;

    localparam int N_BYTES_MAX   = 4000000;
    localparam int N_SAMPLES_MAX = N_BYTES_MAX / 4;

    logic clk;
    logic rst_n;

    logic signed [DATA_W-1:0] in_i;
    logic signed [DATA_W-1:0] in_q;
    logic                     in_valid;
    logic                     in_ready;
    logic                     in_last;

    logic signed [DATA_W-1:0] out_i;
    logic signed [DATA_W-1:0] out_q;
    logic                     out_valid;
    logic                     out_ready;
    logic                     out_last;

    reg [7:0] usrp_bytes [0:N_BYTES_MAX-1];

    integer n_bytes;
    integer n_samples;

    integer fd_in;
    integer fd_i;
    integer fd_q;
    integer r;

    integer out_count;
    integer sample_idx;

    reg [31:0] word_tmp;

    channel_fir_top #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(DECIM),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE("channel_lpf_20tap.mem")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_i(in_i),
        .in_q(in_q),
        .in_valid(in_valid),
        .in_ready(in_ready),     
        .in_last(in_last),
        .out_i(out_i),
        .out_q(out_q),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_last(out_last)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic load_usrp_file;
        begin
            n_bytes = 0;
            fd_in = $fopen("usrp.txt", "r");
            if (fd_in == 0) begin
                $display("ERROR: could not open usrp.txt");
                $finish;
            end

            while (!$feof(fd_in) && n_bytes < N_BYTES_MAX) begin
                r = $fscanf(fd_in, "%h\n", word_tmp);
                if (r == 1) begin
                    usrp_bytes[n_bytes] = word_tmp[7:0];
                    n_bytes = n_bytes + 1;
                end
            end

            $fclose(fd_in);

            if ((n_bytes % 4) != 0) begin
                $display("ERROR: usrp.txt byte count (%0d) is not a multiple of 4", n_bytes);
                $finish;
            end

            n_samples = n_bytes / 4;
            $display("Loaded %0d bytes = %0d IQ samples from usrp.txt", n_bytes, n_samples);
        end
    endtask

    initial begin
        load_usrp_file();

        fd_i = $fopen("sv_channel_i.txt", "w");
        fd_q = $fopen("sv_channel_q.txt", "w");

        if (fd_i == 0 || fd_q == 0) begin
            $display("ERROR: could not open output files");
            $finish;
        end

        rst_n      = 1'b0;
        in_i       = '0;
        in_q       = '0;
        in_valid   = 1'b0;
        in_last    = 1'b0;
        out_ready  = 1'b1;
        out_count  = 0;
        sample_idx = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (sample_idx = 0; sample_idx < n_samples; sample_idx = sample_idx + 1) begin
            @(posedge clk);

            in_i <= $signed({usrp_bytes[4*sample_idx + 1], usrp_bytes[4*sample_idx + 0]});
            in_q <= $signed({usrp_bytes[4*sample_idx + 3], usrp_bytes[4*sample_idx + 2]});
            in_valid <= 1'b1;
            in_last  <= (sample_idx == n_samples-1);

            while (!in_ready) begin
                @(posedge clk);
            end
        end

        @(posedge clk);
        in_valid <= 1'b0;
        in_last  <= 1'b0;
        in_i     <= '0;
        in_q     <= '0;

        repeat (200) @(posedge clk);

        $fclose(fd_i);
        $fclose(fd_q);

        $display("Done. Wrote %0d output samples.", out_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            $fwrite(fd_i, "%04h\n", $unsigned(out_i));
            $fwrite(fd_q, "%04h\n", $unsigned(out_q));
            out_count <= out_count + 1;
        end
    end

endmodule