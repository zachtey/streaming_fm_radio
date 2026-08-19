`timescale 1ns/1ps

// ============================================================================
// Unsigned restoring divider — 32-bit, 1 bit per clock
// ============================================================================
// start: pulse high for one cycle with numerator/denominator loaded
// done:  pulses high when q_out/r_out are valid
// ============================================================================

module seq_divider (
    input  logic        clk,
    input  logic        rst,
    input  logic        start,
    input  logic [31:0] numerator,
    input  logic [31:0] denominator,
    output logic [31:0] q_out,
    output logic [31:0] r_out,
    output logic        done
);

    logic [31:0] numer_reg, denom_reg;
    logic [31:0] q_reg, r_reg;
    logic [5:0]  pos;
    logic        active;

    logic [31:0] r_next;
    logic [31:0] r_trial;
    logic        fits;

    always_comb begin
        r_next  = {r_reg[30:0], numer_reg[31 - pos]};
        r_trial = r_next - denom_reg;
        fits    = (r_next >= denom_reg);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            numer_reg <= '0;
            denom_reg <= '0;
            q_reg     <= '0;
            r_reg     <= '0;
            pos       <= '0;
            active    <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                numer_reg <= numerator;
                denom_reg <= denominator;
                q_reg     <= '0;
                r_reg     <= '0;
                pos       <= '0;
                active    <= 1'b1;
            end else if (active) begin
                q_reg <= {q_reg[30:0], fits};
                r_reg <= fits ? r_trial : r_next;

                if (pos == 6'd31) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                end else begin
                    pos <= pos + 6'd1;
                end
            end
        end
    end

    assign q_out = q_reg;
    assign r_out = r_reg;

endmodule