`timescale 1ns/1ps

module mult_pilot_squared_tb;

    localparam int DATA_W      = 32;
    localparam int OUT_W       = 32;
    localparam int PROD_W      = 64;
    localparam int SCALE_SHIFT = 10;
    localparam int MAX_SAMPLES = 2000000;

    logic clk;
    logic rst_n;

    logic signed [DATA_W-1:0] s_axis_a_tdata;
    logic signed [DATA_W-1:0] s_axis_b_tdata;
    logic                     s_axis_tvalid;
    logic                     s_axis_tready;
    logic                     s_axis_tlast;

    logic signed [OUT_W-1:0]  m_axis_tdata;
    logic                     m_axis_tvalid;
    logic                     m_axis_tready;
    logic                     m_axis_tlast;

    logic signed [31:0] pilot_mem [0:MAX_SAMPLES-1];
    int num_samples;

    integer infile, outfile, rc;
    logic [31:0] raw_word;

    int send_idx;
    int recv_idx;

    mult #(
        .DATA_W(DATA_W),
        .OUT_W(OUT_W),
        .PROD_W(PROD_W),
        .SCALE_SHIFT(SCALE_SHIFT)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axis_a_tdata (s_axis_a_tdata),
        .s_axis_b_tdata (s_axis_b_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic load_input_file(input string fname);
        begin
            num_samples = 0;
            infile = $fopen(fname, "r");
            if (infile == 0) begin
                $error("Could not open input file: %s", fname);
                $finish;
            end

            while (!$feof(infile) && num_samples < MAX_SAMPLES) begin
                rc = $fscanf(infile, "%h\n", raw_word);
                if (rc == 1) begin
                    pilot_mem[num_samples] = $signed(raw_word);
                    num_samples++;
                end
            end

            $fclose(infile);

            if (num_samples == 0) begin
                $error("No samples read from %s", fname);
                $finish;
            end

            $display("Loaded %0d pilot samples from %s", num_samples, fname);
        end
    endtask

    initial begin
        rst_n          = 1'b0;
        s_axis_a_tdata = '0;
        s_axis_b_tdata = '0;
        s_axis_tvalid  = 1'b0;
        s_axis_tlast   = 1'b0;
        m_axis_tready  = 1'b1;

        send_idx = 0;

        load_input_file("stage_bp_pilot.txt");

        outfile = $fopen("sv_pilot_squared.txt", "w");
        if (outfile == 0) begin
            $error("Could not open output file sv_pilot_squared.txt");
            $finish;
        end

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // Hold valid high while sending stream.
        while (send_idx < num_samples) begin
            @(posedge clk);

            s_axis_tvalid = 1'b1;
            s_axis_a_tdata = pilot_mem[send_idx];
            s_axis_b_tdata = pilot_mem[send_idx];
            s_axis_tlast   = (send_idx == num_samples-1);

            if (s_axis_tvalid && s_axis_tready) begin
                send_idx = send_idx + 1;
            end
        end

        // After final handshake, deassert on next cycle.
        @(posedge clk);
        s_axis_tvalid  = 1'b0;
        s_axis_tlast   = 1'b0;
        s_axis_a_tdata = '0;
        s_axis_b_tdata = '0;

        wait (recv_idx == num_samples);

        repeat (5) @(posedge clk);
        $fclose(outfile);
        $display("Wrote %0d output samples to sv_pilot_squared.txt", recv_idx);
        $finish;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            recv_idx <= 0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                if ($isunknown(m_axis_tdata)) begin
                    $error("Output contains X/Z at time %0t, recv_idx=%0d, data=%h",
                           $time, recv_idx, m_axis_tdata);
                end else begin
                    $fwrite(outfile, "%08x\n", $unsigned(m_axis_tdata));
                end

                if ((recv_idx == num_samples-1) && !m_axis_tlast) begin
                    $error("Expected tlast on final output sample, but m_axis_tlast was low");
                end

                recv_idx <= recv_idx + 1;
            end
        end
    end

endmodule