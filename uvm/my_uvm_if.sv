interface my_uvm_if(input logic clock);

    logic               reset;

    // DUT input FIFO write side
    logic               in_full;
    logic               in_wr_en;
    logic [63:0]        in_din;

    // DUT output FIFO read side
    logic               out_left_empty;
    logic               out_left_rd_en;
    logic signed [31:0] out_left_dout;

    logic               out_right_empty;
    logic               out_right_rd_en;
    logic signed [31:0] out_right_dout;

endinterface