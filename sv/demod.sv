`timescale 1ns/1ps

// ============================================================================
// FM quadrature demodulator
// ============================================================================
// Recovers baseband audio from complex I/Q samples via:
//   phase_diff = atan2(imag, real)  of  sample[n] * conj(sample[n-1])
//   output     = gain * phase_diff
//
// Fixed-point Q10 arithmetic throughout. The atan2 approximation avoids
// a hardware divider IP by instantiating a bit-serial restoring divider.
// ============================================================================

module demod #(
    parameter int INPUT_W = 32,
    parameter int DATA_W  = 32,
    parameter int GAIN_W  = 16
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       valid_in,
    input  logic signed [INPUT_W-1:0]  i_in,
    input  logic signed [INPUT_W-1:0]  q_in,
    output logic signed [DATA_W-1:0]   demod_out,
    output logic                       demod_valid_out
);

    // ----------------------------------------------------------------
    // Fixed-point parameters
    // ----------------------------------------------------------------
    localparam int FXP_SHIFT = 10;
    localparam int FXP_SCALE = 1 << FXP_SHIFT;                    // 1024

    localparam logic signed [31:0] K_GAIN    = 32'sd758;           // demod sensitivity
    localparam logic signed [31:0] OCTANT_LO = 32'sd804;           // pi/4  in Q10
    localparam logic signed [31:0] OCTANT_HI = 32'sd2412;          // 3pi/4 in Q10

    // ----------------------------------------------------------------
    // Truncation toward zero  (matches C integer division semantics)
    // ----------------------------------------------------------------
    function automatic logic signed [31:0] trunc_q10(input logic signed [31:0] v);
        if (v >= 0)
            trunc_q10 = v >>> FXP_SHIFT;
        else
            trunc_q10 = (v + (32'sd1 <<< FXP_SHIFT) - 32'sd1) >>> FXP_SHIFT;
    endfunction

    // ----------------------------------------------------------------
    // Control FSM
    // ----------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE,
        CONJUGATE_PROD,
        SCALE_PROD,
        PHASE_SETUP,
        PHASE_LOAD,
        PHASE_DIVIDE,
        PHASE_WEIGHT,
        PHASE_RESOLVE,
        APPLY_GAIN,
        SCALE_OUTPUT,
        EMIT
    } phase_t;

    phase_t step, step_nxt;

    // ----------------------------------------------------------------
    // Datapath registers
    // ----------------------------------------------------------------

    // Delayed sample pair
    logic signed [31:0] re_z1,  re_z1_nxt;
    logic signed [31:0] im_z1,  im_z1_nxt;

    // Captured input
    logic signed [31:0] re_now, re_now_nxt;
    logic signed [31:0] im_now, im_now_nxt;

    // Conjugate-multiply partial products (32-bit wrapping, C-style)
    logic signed [31:0] pp_aa, pp_aa_nxt;       // re_z1 * re_now
    logic signed [31:0] pp_bb, pp_bb_nxt;       // −im_z1 * im_now
    logic signed [31:0] pp_ab, pp_ab_nxt;       // re_z1 * im_now
    logic signed [31:0] pp_ba, pp_ba_nxt;       // −im_z1 * re_now

    // Phase-difference components after dequant
    logic signed [31:0] phi_re, phi_re_nxt;
    logic signed [31:0] phi_im, phi_im_nxt;

    // atan2 working registers
    logic        neg_y,     neg_y_nxt;
    logic        pos_x,     pos_x_nxt;
    logic        q_sign,    q_sign_nxt;
    logic [31:0] mag_num,   mag_num_nxt;
    logic [31:0] mag_den,   mag_den_nxt;

    // Shared product register (reused for atan multiply + gain multiply)
    logic signed [31:0] prod_reg, prod_reg_nxt;

    // Angle accumulator
    logic signed [31:0] theta, theta_nxt;

    // Output holding register
    logic signed [31:0] result, result_nxt;

    // ----------------------------------------------------------------
    // Divider interface
    // ----------------------------------------------------------------
    logic        div_go;
    logic [31:0] div_quot;
    logic [31:0] div_rem;
    logic        div_rdy;

    seq_divider u_div (
        .clk         (clk),
        .rst         (rst),
        .start       (div_go),
        .numerator   (mag_num),
        .denominator (mag_den),
        .q_out       (div_quot),
        .r_out       (div_rem),
        .done        (div_rdy)
    );

    // ----------------------------------------------------------------
    // Combinational helpers for PHASE_SETUP
    // ----------------------------------------------------------------
    logic signed [31:0] y_mag;
    logic signed [31:0] setup_num, setup_den;

    always_comb begin
        y_mag = ((phi_im < 0) ? -phi_im : phi_im) + 32'sd1;

        if (phi_re >= 0) begin
            setup_num = (phi_re - y_mag) * 32'sd1024;
            setup_den = phi_re + y_mag;
        end else begin
            setup_num = (phi_re + y_mag) * 32'sd1024;
            setup_den = y_mag - phi_re;
        end
    end

    // Signed quotient + angle product (used in PHASE_WEIGHT / PHASE_RESOLVE)
    logic signed [31:0] signed_q;
    logic signed [31:0] angle_product;

    always_comb begin
        signed_q      = q_sign ? -$signed(div_quot) : $signed(div_quot);
        angle_product = OCTANT_LO * signed_q;
    end

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            step     <= IDLE;
            re_z1    <= '0;  im_z1    <= '0;
            re_now   <= '0;  im_now   <= '0;
            pp_aa    <= '0;  pp_bb    <= '0;
            pp_ab    <= '0;  pp_ba    <= '0;
            phi_re   <= '0;  phi_im   <= '0;
            neg_y    <= '0;  pos_x    <= '0;
            q_sign   <= '0;
            mag_num  <= '0;  mag_den  <= '0;
            prod_reg <= '0;  theta    <= '0;
            result   <= '0;
        end else begin
            step     <= step_nxt;
            re_z1    <= re_z1_nxt;    im_z1    <= im_z1_nxt;
            re_now   <= re_now_nxt;   im_now   <= im_now_nxt;
            pp_aa    <= pp_aa_nxt;    pp_bb    <= pp_bb_nxt;
            pp_ab    <= pp_ab_nxt;    pp_ba    <= pp_ba_nxt;
            phi_re   <= phi_re_nxt;   phi_im   <= phi_im_nxt;
            neg_y    <= neg_y_nxt;    pos_x    <= pos_x_nxt;
            q_sign   <= q_sign_nxt;
            mag_num  <= mag_num_nxt;  mag_den  <= mag_den_nxt;
            prod_reg <= prod_reg_nxt; theta    <= theta_nxt;
            result   <= result_nxt;
        end
    end

    // ----------------------------------------------------------------
    // Next-state + datapath logic
    // ----------------------------------------------------------------
    always_comb begin
        // Hold everything by default
        step_nxt     = step;
        re_z1_nxt    = re_z1;    im_z1_nxt    = im_z1;
        re_now_nxt   = re_now;   im_now_nxt   = im_now;
        pp_aa_nxt    = pp_aa;    pp_bb_nxt    = pp_bb;
        pp_ab_nxt    = pp_ab;    pp_ba_nxt    = pp_ba;
        phi_re_nxt   = phi_re;   phi_im_nxt   = phi_im;
        neg_y_nxt    = neg_y;    pos_x_nxt    = pos_x;
        q_sign_nxt   = q_sign;
        mag_num_nxt  = mag_num;  mag_den_nxt  = mag_den;
        prod_reg_nxt = prod_reg; theta_nxt    = theta;
        result_nxt   = result;

        demod_out       = '0;
        demod_valid_out = 1'b0;
        div_go          = 1'b0;

        case (step)

            // Capture new I/Q pair
            IDLE: begin
                if (valid_in) begin
                    re_now_nxt = i_in;
                    im_now_nxt = q_in;
                    step_nxt   = CONJUGATE_PROD;
                end
            end

            // 32-bit products: sample[n] * conj(sample[n-1])
            CONJUGATE_PROD: begin
                pp_aa_nxt = re_z1 * re_now;              // Re(z1) · Re(z0)
                pp_bb_nxt = (-im_z1) * im_now;           // −Im(z1) · Im(z0)
                pp_ab_nxt = re_z1 * im_now;              // Re(z1) · Im(z0)
                pp_ba_nxt = (-im_z1) * re_now;           // −Im(z1) · Re(z0)
                step_nxt  = SCALE_PROD;
            end

            // Dequantize each product, form real/imag phase diff, advance z-1
            SCALE_PROD: begin
                phi_re_nxt = trunc_q10(pp_aa) - trunc_q10(pp_bb);
                phi_im_nxt = trunc_q10(pp_ab) + trunc_q10(pp_ba);
                re_z1_nxt  = re_now;
                im_z1_nxt  = im_now;
                step_nxt   = PHASE_SETUP;
            end

            // Prepare the linear atan2 division
            PHASE_SETUP: begin
                neg_y_nxt = (phi_im < 0);
                pos_x_nxt = (phi_re >= 0);

                q_sign_nxt  = (setup_num < 0);
                mag_num_nxt = (setup_num < 0) ? -setup_num : setup_num;
                mag_den_nxt = setup_den;

                step_nxt = PHASE_LOAD;
            end

            // Kick off divider (mag_num / mag_den now registered)
            PHASE_LOAD: begin
                div_go   = 1'b1;
                step_nxt = PHASE_DIVIDE;
            end

            // Wait for divider
            PHASE_DIVIDE: begin
                if (div_rdy)
                    step_nxt = PHASE_WEIGHT;
            end

            // Latch OCTANT_LO * r
            PHASE_WEIGHT: begin
                prod_reg_nxt = angle_product;
                step_nxt     = PHASE_RESOLVE;
            end

            // Compute final angle with quadrant/sign correction
            PHASE_RESOLVE: begin
                if (pos_x)
                    theta_nxt = neg_y ? -(OCTANT_LO - trunc_q10(prod_reg))
                                      :  (OCTANT_LO - trunc_q10(prod_reg));
                else
                    theta_nxt = neg_y ? -(OCTANT_HI - trunc_q10(prod_reg))
                                      :  (OCTANT_HI - trunc_q10(prod_reg));
                step_nxt = APPLY_GAIN;
            end

            // Multiply angle by demod gain constant
            APPLY_GAIN: begin
                prod_reg_nxt = K_GAIN * theta;
                step_nxt     = SCALE_OUTPUT;
            end

            // Final dequantize
            SCALE_OUTPUT: begin
                result_nxt = trunc_q10(prod_reg);
                step_nxt   = EMIT;
            end

            // Drive output for one cycle
            EMIT: begin
                demod_out       = result;
                demod_valid_out = 1'b1;
                step_nxt        = IDLE;
            end

            default: step_nxt = IDLE;
        endcase
    end

endmodule