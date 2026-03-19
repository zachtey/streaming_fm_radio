interface my_uvm_if(input logic clock);

    logic               reset;

    logic [7:0]         iq_byte;
    logic               iq_valid;
    logic               iq_ready;

    logic signed [31:0] out_left;
    logic signed [31:0] out_right;
    logic               out_valid;
    logic               out_ready;

endinterface