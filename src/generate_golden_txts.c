#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "fm_radio.h"

/*
    generate_golden_txts.c

    Purpose:
      Generate intermediate golden text files for each major stage in the
      FM stereo pipeline so each SV module can be tested independently.

    Expected input:
      usrp.txt  -> one hex byte per line

    Output files:
      gold_00_read_i.txt
      gold_00_read_q.txt

      gold_01_channel_i_fir.txt
      gold_01_channel_q_fir.txt

      gold_02_demod.txt

      gold_03_audio_lpr.txt
      gold_04_bp_lmr.txt
      gold_05_bp_pilot.txt
      gold_06_square.txt
      gold_07_hp_pilot.txt
      gold_08_multiply.txt
      gold_09_audio_lmr.txt

      gold_10_left_add.txt
      gold_10_right_sub.txt

      gold_11_left_deemph.txt
      gold_11_right_deemph.txt

      gold_12_left_gain.txt
      gold_12_right_gain.txt

    Notes:
      - This mirrors the same ordering as fm_radio_stereo().
      - State arrays are preserved across blocks, just like the software flow.
      - Files are overwritten on each run.
*/

#define BLOCK_BYTES (SAMPLES * 4)

static void dump_int_array_hex_write(const char *filename, const int *x, int n)
{
    FILE *f = fopen(filename, "w");
    if (!f) {
        fprintf(stderr, "ERROR: could not open %s for writing\n", filename);
        exit(1);
    }

    for (int i = 0; i < n; i++) {
        fprintf(f, "%08x\n", (uint32_t)x[i]);
    }

    fclose(f);
}

static void dump_int_array_hex_append(const char *filename, const int *x, int n)
{
    FILE *f = fopen(filename, "a");
    if (!f) {
        fprintf(stderr, "ERROR: could not open %s for appending\n", filename);
        exit(1);
    }

    for (int i = 0; i < n; i++) {
        fprintf(f, "%08x\n", (uint32_t)x[i]);
    }

    fclose(f);
}

static void init_output_files(void)
{
    const char *files[] = {
        "gold_00_read_i.txt",
        "gold_00_read_q.txt",

        "gold_01_channel_i_fir.txt",
        "gold_01_channel_q_fir.txt",

        "gold_02_demod.txt",

        "gold_03_audio_lpr.txt",
        "gold_04_bp_lmr.txt",
        "gold_05_bp_pilot.txt",
        "gold_06_square.txt",
        "gold_07_hp_pilot.txt",
        "gold_08_multiply.txt",
        "gold_09_audio_lmr.txt",

        "gold_10_left_add.txt",
        "gold_10_right_sub.txt",

        "gold_11_left_deemph.txt",
        "gold_11_right_deemph.txt",

        "gold_12_left_gain.txt",
        "gold_12_right_gain.txt"
    };

    const int nfiles = (int)(sizeof(files) / sizeof(files[0]));
    for (int i = 0; i < nfiles; i++) {
        FILE *f = fopen(files[i], "w");
        if (!f) {
            fprintf(stderr, "ERROR: could not initialize %s\n", files[i]);
            exit(1);
        }
        fclose(f);
    }
}

static int load_usrp_text_block(FILE *f, unsigned char *buf, int max_bytes)
{
    unsigned int word;
    int count = 0;

    while (count < max_bytes) {
        int rc = fscanf(f, "%x", &word);
        if (rc != 1) {
            break;
        }
        buf[count++] = (unsigned char)(word & 0xFF);
    }

    return count;
}

int main(int argc, char **argv)
{
    const char *input_name = "usrp.txt";
    if (argc >= 2) {
        input_name = argv[1];
    }

    FILE *usrp_file = fopen(input_name, "r");
    if (!usrp_file) {
        fprintf(stderr, "ERROR: could not open %s\n", input_name);
        return 1;
    }

    init_output_files();

    /* block input */
    static unsigned char IQ[BLOCK_BYTES];

    /* stage arrays */
    static int I[SAMPLES];
    static int Q[SAMPLES];
    static int I_fir[SAMPLES];
    static int Q_fir[SAMPLES];
    static int demod[SAMPLES];
    static int bp_pilot_filter[SAMPLES];
    static int bp_lmr_filter[SAMPLES];
    static int hp_pilot_filter[SAMPLES];
    static int audio_lpr_filter[AUDIO_SAMPLES];
    static int audio_lmr_filter[AUDIO_SAMPLES];
    static int square[SAMPLES];
    static int multiply[SAMPLES];
    static int left[AUDIO_SAMPLES];
    static int right[AUDIO_SAMPLES];
    static int left_deemph[AUDIO_SAMPLES];
    static int right_deemph[AUDIO_SAMPLES];

    /* persistent internal state arrays, mirroring fm_radio_stereo() */
    static int fir_cmplx_x_real[MAX_TAPS];
    static int fir_cmplx_x_imag[MAX_TAPS];
    static int demod_real[] = {0};
    static int demod_imag[] = {0};
    static int fir_lpr_x[MAX_TAPS];
    static int fir_lmr_x[MAX_TAPS];
    static int fir_bp_x[MAX_TAPS];
    static int fir_pilot_x[MAX_TAPS];
    static int fir_hp_x[MAX_TAPS];
    static int deemph_l_x[MAX_TAPS];
    static int deemph_l_y[MAX_TAPS];
    static int deemph_r_x[MAX_TAPS];
    static int deemph_r_y[MAX_TAPS];

    int block_idx = 0;

    while (1) {
        int nbytes = load_usrp_text_block(usrp_file, IQ, BLOCK_BYTES);
        if (nbytes == 0) {
            break;
        }

        if (nbytes != BLOCK_BYTES) {
            fprintf(stderr,
                    "WARNING: partial block at end of file: got %d bytes, expected %d. Ignoring trailing partial block.\n",
                    nbytes, BLOCK_BYTES);
            break;
        }

        /* 0) Read / partition I/Q */
        read_IQ(IQ, I, Q, SAMPLES);
        dump_int_array_hex_append("gold_00_read_i.txt", I, SAMPLES);
        dump_int_array_hex_append("gold_00_read_q.txt", Q, SAMPLES);

        /* 1) Channel complex FIR */
        fir_cmplx_n(I, Q,
                    SAMPLES,
                    CHANNEL_COEFFS_REAL,
                    CHANNEL_COEFFS_IMAG,
                    fir_cmplx_x_real,
                    fir_cmplx_x_imag,
                    CHANNEL_COEFF_TAPS,
                    1,
                    I_fir,
                    Q_fir);

        dump_int_array_hex_append("gold_01_channel_i_fir.txt", I_fir, SAMPLES);
        dump_int_array_hex_append("gold_01_channel_q_fir.txt", Q_fir, SAMPLES);

        /* 2) Demod */
        demodulate_n(I_fir, Q_fir,
                     demod_real, demod_imag,
                     SAMPLES,
                     FM_DEMOD_GAIN,
                     demod);

        dump_int_array_hex_append("gold_02_demod.txt", demod, SAMPLES);

        /* 3) L+R LPF + decimate */
        fir_n(demod,
              SAMPLES,
              AUDIO_LPR_COEFFS,
              fir_lpr_x,
              AUDIO_LPR_COEFF_TAPS,
              AUDIO_DECIM,
              audio_lpr_filter);

        dump_int_array_hex_append("gold_03_audio_lpr.txt", audio_lpr_filter, AUDIO_SAMPLES);

        /* 4) L-R BPF */
        fir_n(demod,
              SAMPLES,
              BP_LMR_COEFFS,
              fir_bp_x,
              BP_LMR_COEFF_TAPS,
              1,
              bp_lmr_filter);

        dump_int_array_hex_append("gold_04_bp_lmr.txt", bp_lmr_filter, SAMPLES);

        /* 5) Pilot BPF */
        fir_n(demod,
              SAMPLES,
              BP_PILOT_COEFFS,
              fir_pilot_x,
              BP_PILOT_COEFF_TAPS,
              1,
              bp_pilot_filter);

        dump_int_array_hex_append("gold_05_bp_pilot.txt", bp_pilot_filter, SAMPLES);

        /* 6) Square pilot */
        multiply_n(bp_pilot_filter, bp_pilot_filter, SAMPLES, square);
        dump_int_array_hex_append("gold_06_square.txt", square, SAMPLES);

        /* 7) HPF after square */
        fir_n(square,
              SAMPLES,
              HP_COEFFS,
              fir_hp_x,
              HP_COEFF_TAPS,
              1,
              hp_pilot_filter);

        dump_int_array_hex_append("gold_07_hp_pilot.txt", hp_pilot_filter, SAMPLES);

        /* 8) Multiply recovered 38kHz with L-R branch */
        multiply_n(hp_pilot_filter, bp_lmr_filter, SAMPLES, multiply);
        dump_int_array_hex_append("gold_08_multiply.txt", multiply, SAMPLES);

        /* 9) L-R LPF + decimate */
        fir_n(multiply,
              SAMPLES,
              AUDIO_LMR_COEFFS,
              fir_lmr_x,
              AUDIO_LMR_COEFF_TAPS,
              AUDIO_DECIM,
              audio_lmr_filter);

        dump_int_array_hex_append("gold_09_audio_lmr.txt", audio_lmr_filter, AUDIO_SAMPLES);

        /* 10) Left / right reconstruction */
        add_n(audio_lpr_filter, audio_lmr_filter, AUDIO_SAMPLES, left);
        sub_n(audio_lpr_filter, audio_lmr_filter, AUDIO_SAMPLES, right);

        dump_int_array_hex_append("gold_10_left_add.txt", left, AUDIO_SAMPLES);
        dump_int_array_hex_append("gold_10_right_sub.txt", right, AUDIO_SAMPLES);

        /* 11) Deemphasis */
        deemphasis_n(left,  deemph_l_x, deemph_l_y, AUDIO_SAMPLES, left_deemph);
        deemphasis_n(right, deemph_r_x, deemph_r_y, AUDIO_SAMPLES, right_deemph);

        dump_int_array_hex_append("gold_11_left_deemph.txt", left_deemph, AUDIO_SAMPLES);
        dump_int_array_hex_append("gold_11_right_deemph.txt", right_deemph, AUDIO_SAMPLES);

        /* 12) Gain / volume */
        gain_n(left_deemph,  AUDIO_SAMPLES, VOLUME_LEVEL, left);
        gain_n(right_deemph, AUDIO_SAMPLES, VOLUME_LEVEL, right);

        dump_int_array_hex_append("gold_12_left_gain.txt", left, AUDIO_SAMPLES);
        dump_int_array_hex_append("gold_12_right_gain.txt", right, AUDIO_SAMPLES);

        block_idx++;
    }

    fclose(usrp_file);

    printf("Generated golden text files successfully.\n");
    printf("Processed %d block(s) of %d IQ samples each.\n", block_idx, SAMPLES);
    printf("Files written:\n");
    printf("  gold_00_read_i.txt\n");
    printf("  gold_00_read_q.txt\n");
    printf("  gold_01_channel_i_fir.txt\n");
    printf("  gold_01_channel_q_fir.txt\n");
    printf("  gold_02_demod.txt\n");
    printf("  gold_03_audio_lpr.txt\n");
    printf("  gold_04_bp_lmr.txt\n");
    printf("  gold_05_bp_pilot.txt\n");
    printf("  gold_06_square.txt\n");
    printf("  gold_07_hp_pilot.txt\n");
    printf("  gold_08_multiply.txt\n");
    printf("  gold_09_audio_lmr.txt\n");
    printf("  gold_10_left_add.txt\n");
    printf("  gold_10_right_sub.txt\n");
    printf("  gold_11_left_deemph.txt\n");
    printf("  gold_11_right_deemph.txt\n");
    printf("  gold_12_left_gain.txt\n");
    printf("  gold_12_right_gain.txt\n");

    return 0;
}