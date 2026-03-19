class my_uvm_scoreboard extends uvm_component;
    `uvm_component_utils(my_uvm_scoreboard)

    my_uvm_config cfg;

    uvm_analysis_imp #(my_uvm_transaction, my_uvm_scoreboard) analysis_export;

    bit signed [31:0] left_gold_mem[$];
    bit signed [31:0] right_gold_mem[$];

    int out_idx;
    int err_left, err_right;
    int match_left, match_right;

    int fd_left_out, fd_right_out;
    bit done;

    function new(string name = "my_uvm_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        int fd_local;
        int r;
        bit [31:0] word_tmp;

        super.build_phase(phase);

        if (!uvm_config_db#(my_uvm_config)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("SCB", "Could not get my_uvm_config")
        end

        fd_local = $fopen(cfg.left_gold_file, "r");
        if (fd_local == 0) begin
            `uvm_fatal("SCB", $sformatf("Could not open %s", cfg.left_gold_file))
        end
        while (!$feof(fd_local)) begin
            r = $fscanf(fd_local, "%h\n", word_tmp);
            if (r == 1) left_gold_mem.push_back($signed(word_tmp));
        end
        $fclose(fd_local);

        fd_local = $fopen(cfg.right_gold_file, "r");
        if (fd_local == 0) begin
            `uvm_fatal("SCB", $sformatf("Could not open %s", cfg.right_gold_file))
        end
        while (!$feof(fd_local)) begin
            r = $fscanf(fd_local, "%h\n", word_tmp);
            if (r == 1) right_gold_mem.push_back($signed(word_tmp));
        end
        $fclose(fd_local);

        if (left_gold_mem.size() != right_gold_mem.size()) begin
            `uvm_fatal("SCB", "Left/right golden counts do not match")
        end

        fd_left_out = $fopen(cfg.left_out_file, "w");
        fd_right_out = $fopen(cfg.right_out_file, "w");

        if ((fd_left_out == 0) || (fd_right_out == 0)) begin
            `uvm_fatal("SCB", "Could not open output dump files")
        end

        out_idx      = 0;
        err_left     = 0;
        err_right    = 0;
        match_left   = 0;
        match_right  = 0;
        done         = 0;
    endfunction

    virtual function void write(my_uvm_transaction tr);
        bit signed [31:0] exp_left, exp_right;
        bit signed [31:0] diff_left, diff_right;

        $fwrite(fd_left_out,  "%08h\n", $unsigned(tr.out_left));
        $fwrite(fd_right_out, "%08h\n", $unsigned(tr.out_right));

        if (out_idx < left_gold_mem.size()) begin
            exp_left  = left_gold_mem[out_idx];
            diff_left = tr.out_left - exp_left;
            if (diff_left == 0)
                match_left++;
            else begin
                err_left++;
                `uvm_info("SCB",
                    $sformatf("LEFT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                              out_idx, $unsigned(tr.out_left), $unsigned(exp_left), diff_left),
                    UVM_LOW)
            end
        end

        if (out_idx < right_gold_mem.size()) begin
            exp_right  = right_gold_mem[out_idx];
            diff_right = tr.out_right - exp_right;
            if (diff_right == 0)
                match_right++;
            else begin
                err_right++;
                `uvm_info("SCB",
                    $sformatf("RIGHT MISMATCH @ %0d: got %08h expected %08h diff=%0d",
                              out_idx, $unsigned(tr.out_right), $unsigned(exp_right), diff_right),
                    UVM_LOW)
            end
        end

        out_idx++;

        if (out_idx >= left_gold_mem.size()) begin
            done = 1;
        end
    endfunction

    function bit is_done();
        return done;
    endfunction

    function int expected_count();
        return left_gold_mem.size();
    endfunction

    virtual function void report_phase(uvm_phase phase);
        $fclose(fd_left_out);
        $fclose(fd_right_out);

        `uvm_info("SCB", "====================================================", UVM_NONE)
        `uvm_info("SCB", "FM RADIO TOP UVM simulation done.", UVM_NONE)
        `uvm_info("SCB", $sformatf("Audio outputs seen   : %0d", out_idx), UVM_NONE)
        `uvm_info("SCB", $sformatf("Left mismatches      : %0d", err_left), UVM_NONE)
        `uvm_info("SCB", $sformatf("Right mismatches     : %0d", err_right), UVM_NONE)
        `uvm_info("SCB", $sformatf("Left exact matches   : %0d", match_left), UVM_NONE)
        `uvm_info("SCB", $sformatf("Right exact matches  : %0d", match_right), UVM_NONE)

        if ((err_left == 0) && (err_right == 0))
            `uvm_info("SCB", "PASS", UVM_NONE)
        else
            `uvm_error("SCB", "FAIL")

        `uvm_info("SCB", "====================================================", UVM_NONE)
    endfunction
endclass