class my_uvm_sequence extends uvm_sequence #(my_uvm_transaction);
    `uvm_object_utils(my_uvm_sequence)

    my_uvm_config cfg;

    int fd;
    int r;
    int n_bytes;
    bit [31:0] word_tmp;

    function new(string name = "my_uvm_sequence");
        super.new(name);
    endfunction

    virtual task body();
        my_uvm_transaction tr;

        if (!uvm_config_db#(my_uvm_config)::get(null, "*", "cfg", cfg)) begin
            `uvm_fatal("SEQ", "Could not get my_uvm_config from config DB")
        end

        fd = $fopen(cfg.usrp_file, "r");
        if (fd == 0) begin
            `uvm_fatal("SEQ", $sformatf("Could not open usrp file: %s", cfg.usrp_file))
        end

        n_bytes = 0;
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h\n", word_tmp);
            if (r == 1) begin
                tr = my_uvm_transaction::type_id::create($sformatf("tr_%0d", n_bytes));
                start_item(tr);
                tr.iq_byte = word_tmp[7:0];
                finish_item(tr);
                n_bytes++;
            end
        end

        $fclose(fd);
        `uvm_info("SEQ", $sformatf("Sequence sent %0d input bytes", n_bytes), UVM_LOW)
    endtask
endclass