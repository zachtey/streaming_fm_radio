/*
atan module
*/

module atan #(
    //params
    parameter int INPUT_W = 33,
    parameter int ANG_W   = 32
) (
    //ports
    //admin
    input  logic clk,
    input  logic rst,
    //input
    input  logic valid_in,
    input  logic signed [INPUT_W-1:0]  x_in,   // r
    input  logic signed [INPUT_W-1:0]  y_in,   // i
    //output
    output logic valid_out,
    output logic signed [ANG_W-1:0] angle_out
);

    // Placeholder only
    // Replace this with real atan / CORDIC implementation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            angle_out  <= '0;
        end else begin
            valid_out  <= valid_in;
            angle_out  <= '0;
        end
    end

endmodule