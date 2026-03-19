class my_uvm_sequence extends uvm_sequence #(my_uvm_transaction);
    `uvm_object_utils(my_uvm_sequence)

    my_uvm_config cfg;

    int fd;
    int r;
    int n_bytes;
    bit [31:0] word_tmp;
    bit [7:0]  byte_q[$];

    function new(string name = "my_uvm_sequence");
        super.new(name);
    endfunction

    virtual task body();
        my_uvm_transaction tr;
        bit [15:0] i16, q16;
        int sample_count;

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
                byte_q.push_back(word_tmp[7:0]);
                n_bytes++;
            end
        end
        $fclose(fd);

        if ((byte_q.size() % 4) != 0) begin
            `uvm_fatal("SEQ", $sformatf("usrp file byte count %0d is not a multiple of 4", byte_q.size()))
        end

        sample_count = 0;
        while (byte_q.size() >= 4) begin
            tr = my_uvm_transaction::type_id::create($sformatf("tr_%0d", sample_count));

            i16 = {byte_q[1], byte_q[0]};
            q16 = {byte_q[3], byte_q[2]};

            start_item(tr);
            tr.in_i = $signed({{16{i16[15]}}, i16}) <<< 10;
            tr.in_q = $signed({{16{q16[15]}}, q16}) <<< 10;
            finish_item(tr);

            byte_q.pop_front();
            byte_q.pop_front();
            byte_q.pop_front();
            byte_q.pop_front();

            sample_count++;
        end

        `uvm_info("SEQ", $sformatf("Sequence sent %0d IQ samples", sample_count), UVM_LOW)
    endtask
endclass