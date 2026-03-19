package fm_radio_pkg;

    // =========================================================
    // Quantization / system constants
    // =========================================================
    localparam int BITS          = 10;
    localparam int QUANT_VAL     = (1 << BITS);

    localparam int ADC_RATE      = 64000000;
    localparam int USRP_DECIM    = 250;
    localparam int QUAD_RATE     = ADC_RATE / USRP_DECIM;     // 256000
    localparam int AUDIO_DECIM   = 8;
    localparam int AUDIO_RATE    = QUAD_RATE / AUDIO_DECIM;   // 32000
    localparam int SAMPLES       = 65536 * 4;
    localparam int AUDIO_SAMPLES = SAMPLES / AUDIO_DECIM;
    localparam int MAX_TAPS      = 32;

    localparam logic signed [31:0] FM_DEMOD_GAIN = 32'sd758;
    localparam logic signed [31:0] VOLUME_LEVEL  = 32'sd1024;

    // qarctan constants
    localparam logic signed [31:0] QUAD1 = 32'sd804;
    localparam logic signed [31:0] QUAD3 = 32'sd2412;

    // =========================================================
    // Inline quantization helpers
    // =========================================================
    function automatic logic signed [31:0] quantize_i(input logic signed [31:0] val);
        quantize_i = val * 32'sd1024;
    endfunction

    function automatic logic signed [31:0] dequantize(input logic signed [31:0] val);
        begin
            if (val >= 0)
                dequantize = val >>> 10;
            else
                dequantize = (val + 32'sd1023) >>> 10;
        end
    endfunction

    function automatic logic signed [31:0] deq_product(
        input logic signed [31:0] a,
        input logic signed [31:0] b
    );
        logic signed [31:0] prod;
        begin
            prod = a * b; // preserve 32-bit wrap behavior
            if (prod >= 0)
                deq_product = prod >>> 10;
            else
                deq_product = (prod + 32'sd1023) >>> 10;
        end
    endfunction

    // =========================================================
    // Channel complex FIR coefficients
    // =========================================================
    localparam int CHANNEL_COEFF_TAPS = 20;

    localparam logic signed [31:0] CHANNEL_COEFFS_REAL [0:CHANNEL_COEFF_TAPS-1] = '{
        32'h00000001, 32'h00000008, 32'hfffffff3, 32'h00000009,
        32'h0000000b, 32'hffffffd3, 32'h00000045, 32'hffffffd3,
        32'hffffffb1, 32'h00000257, 32'h00000257, 32'hffffffb1,
        32'hffffffd3, 32'h00000045, 32'hffffffd3, 32'h0000000b,
        32'h00000009, 32'hfffffff3, 32'h00000008, 32'h00000001
    };

    localparam logic signed [31:0] CHANNEL_COEFFS_IMAG [0:CHANNEL_COEFF_TAPS-1] = '{
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
        32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
    };

    // =========================================================
    // L+R low-pass FIR
    // =========================================================
    localparam int AUDIO_LPR_COEFF_TAPS = 32;

    localparam logic signed [31:0] AUDIO_LPR_COEFFS [0:AUDIO_LPR_COEFF_TAPS-1] = '{
        32'hfffffffd, 32'hfffffffa, 32'hfffffff4, 32'hffffffed,
        32'hffffffe5, 32'hffffffdf, 32'hffffffe2, 32'hfffffff3,
        32'h00000015, 32'h0000004e, 32'h0000009b, 32'h000000f9,
        32'h0000015d, 32'h000001be, 32'h0000020e, 32'h00000243,
        32'h00000243, 32'h0000020e, 32'h000001be, 32'h0000015d,
        32'h000000f9, 32'h0000009b, 32'h0000004e, 32'h00000015,
        32'hfffffff3, 32'hffffffe2, 32'hffffffdf, 32'hffffffe5,
        32'hffffffed, 32'hfffffff4, 32'hfffffffa, 32'hfffffffd
    };

    // =========================================================
    // L-R low-pass FIR
    // =========================================================
    localparam int AUDIO_LMR_COEFF_TAPS = 32;

    localparam logic signed [31:0] AUDIO_LMR_COEFFS [0:AUDIO_LMR_COEFF_TAPS-1] = '{
        32'hfffffffd, 32'hfffffffa, 32'hfffffff4, 32'hffffffed,
        32'hffffffe5, 32'hffffffdf, 32'hffffffe2, 32'hfffffff3,
        32'h00000015, 32'h0000004e, 32'h0000009b, 32'h000000f9,
        32'h0000015d, 32'h000001be, 32'h0000020e, 32'h00000243,
        32'h00000243, 32'h0000020e, 32'h000001be, 32'h0000015d,
        32'h000000f9, 32'h0000009b, 32'h0000004e, 32'h00000015,
        32'hfffffff3, 32'hffffffe2, 32'hffffffdf, 32'hffffffe5,
        32'hffffffed, 32'hfffffff4, 32'hfffffffa, 32'hfffffffd
    };

    // =========================================================
    // Pilot band-pass FIR
    // =========================================================
    localparam int BP_PILOT_COEFF_TAPS = 32;

    localparam logic signed [31:0] BP_PILOT_COEFFS [0:BP_PILOT_COEFF_TAPS-1] = '{
        32'h0000000e, 32'h0000001f, 32'h00000034, 32'h00000048,
        32'h0000004e, 32'h00000036, 32'hfffffff8, 32'hffffff98,
        32'hffffff2d, 32'hfffffeda, 32'hfffffec3, 32'hfffffefe,
        32'hffffff8a, 32'h0000004a, 32'h0000010f, 32'h000001a1,
        32'h000001a1, 32'h0000010f, 32'h0000004a, 32'hffffff8a,
        32'hfffffefe, 32'hfffffec3, 32'hfffffeda, 32'hffffff2d,
        32'hffffff98, 32'hfffffff8, 32'h00000036, 32'h0000004e,
        32'h00000048, 32'h00000034, 32'h0000001f, 32'h0000000e
    };

    // =========================================================
    // L-R band-pass FIR
    // =========================================================
    localparam int BP_LMR_COEFF_TAPS = 32;

    localparam logic signed [31:0] BP_LMR_COEFFS [0:BP_LMR_COEFF_TAPS-1] = '{
        32'h00000000, 32'h00000000, 32'hfffffffc, 32'hfffffff9,
        32'hfffffffe, 32'h00000008, 32'h0000000c, 32'h00000002,
        32'h00000003, 32'h0000001e, 32'h00000030, 32'hfffffffc,
        32'hffffff8c, 32'hffffff58, 32'hffffffc3, 32'h0000008a,
        32'h0000008a, 32'hffffffc3, 32'hffffff58, 32'hffffff8c,
        32'hfffffffc, 32'h00000030, 32'h0000001e, 32'h00000003,
        32'h00000002, 32'h0000000c, 32'h00000008, 32'hfffffffe,
        32'hfffffff9, 32'hfffffffc, 32'h00000000, 32'h00000000
    };

    // =========================================================
    // High-pass FIR
    // =========================================================
    localparam int HP_COEFF_TAPS = 32;

    localparam logic signed [31:0] HP_COEFFS [0:HP_COEFF_TAPS-1] = '{
        32'hffffffff, 32'h00000000, 32'h00000000, 32'h00000002,
        32'h00000004, 32'h00000008, 32'h0000000b, 32'h0000000c,
        32'h00000008, 32'hffffffff, 32'hffffffee, 32'hffffffd7,
        32'hffffffbb, 32'hffffff9f, 32'hffffff87, 32'hffffff76,
        32'hffffff76, 32'hffffff87, 32'hffffff9f, 32'hffffffbb,
        32'hffffffd7, 32'hffffffee, 32'hffffffff, 32'h00000008,
        32'h0000000c, 32'h0000000b, 32'h00000008, 32'h00000004,
        32'h00000002, 32'h00000000, 32'h00000000, 32'hffffffff
    };

    // =========================================================
    // De-emphasis IIR
    // =========================================================
    localparam int IIR_COEFF_TAPS  = 2;
    localparam int IIR_SCALE_SHIFT = BITS;

    
    localparam logic signed [31:0] IIR_X_COEFFS [0:IIR_COEFF_TAPS-1] = '{
    32'sd178, 32'sd178
};

localparam logic signed [31:0] IIR_Y_COEFFS [0:IIR_COEFF_TAPS-1] = '{
    32'sd0, -32'sd666
};

endpackage