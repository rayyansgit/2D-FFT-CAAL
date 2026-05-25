# fft_2d.s — Milestone 4
# 2D Vectorized FFT in RISC-V Assembly
# M3 vector functions used verbatim, extended with 2D pipeline + IFFT
#
# Build:
#   riscv64-linux-gnu-gcc -march=rv64gcv -o fft_2d fft_2d.s -lm -static
# Run:
#   qemu-riscv64 -cpu max ./fft_2d          # uses img_input.bin or 8x8 fallback
#
# img_input.bin format (written by convert_image.py):
#   [4 bytes: int32 N][4 bytes: int32 N][N*N float32 pixels, row-major, [0,1]]

# ============================================================
# .data
# ============================================================
    .section .data
    .balign 4

# 8x8 fallback — same input as M3 for cross-checking
# pixel[r][c] = img_real_8 + (r*8 + c)*4  (row-major)
img_real_8:
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0
    .float 1.0, 2.0, 3.0, 4.0, 4.0, 3.0, 2.0, 1.0

img_imag_8:
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    .float 0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0

# 16x16 hardcoded test image (checkerboard pattern)
img_real_16:
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0
    .float 1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0
    .float 0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0,0.0,1.0

img_imag_16:
    .fill 256, 4, 0

# 32x32 hardcoded test image (gradient pattern)
img_real_32:
    .float 0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00
    .float 0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00
    .float 0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03
    .float 0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06
    .float 0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10
    .float 0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13
    .float 0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16
    .float 0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19
    .float 0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23
    .float 0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26
    .float 0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29
    .float 0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32
    .float 0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35
    .float 0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39
    .float 0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42
    .float 0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45
    .float 0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48
    .float 0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52
    .float 0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55
    .float 0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58
    .float 0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61
    .float 0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65
    .float 0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68
    .float 0.74,0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71
    .float 0.77,0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74
    .float 0.81,0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77
    .float 0.84,0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81
    .float 0.87,0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84
    .float 0.90,0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87
    .float 0.94,0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90
    .float 0.97,1.00,0.00,0.03,0.06,0.10,0.13,0.16,0.19,0.23,0.26,0.29,0.32,0.35,0.39,0.42,0.45,0.48,0.52,0.55,0.58,0.61,0.65,0.68,0.71,0.74,0.77,0.81,0.84,0.87,0.90,0.94

img_imag_32:
    .fill 1024, 4, 0

    .section .rodata
    .balign 4
const_2pi:       .float  6.28318530717959
const_1f:        .float  1.0
str_bench:       .string "bench"
str_input_bin:   .string "img_input.bin"
str_fft_bin:     .string "fft_result.bin"
str_no_input:    .string "No img_input.bin found — using hardcoded 8x8 fallback\n"
str_loaded:      .string "Loaded %dx%d image from img_input.bin\n"
str_wrote_bin:   .string "Wrote fft_result.bin (%d bytes)\n"
str_row0_fft:    .string "\n--- Row 0 after Row-FFT (bins 0-7) ---\n"
str_col0_fft:    .string "\n--- Col 0 after Col-FFT (rows 0-7) ---\n"
str_after_shift: .string "\n--- Row 0 after fftshift (bins 0-7) ---\n"
str_after_hp:    .string "\n--- Row 0 after highpass (center bins should be 0) ---\n"
str_after_ifft:  .string "\n--- Row 0 after IFFT (spatial domain, bins 0-7) ---\n"
fmt_bin:         .string "  [%2d]: %9.4f + %9.4fi\n"
fmt_sep:         .string "\n================================================\n"
fmt_size_hdr:    .string "2D FFT: %dx%d image\n"
fmt_cycles:      .string "Total cycles: %lu\n"
str_bench_hdr:   .string "\n+--------+------------------+\n| Size   | Total Cycles     |\n+--------+------------------+\n"
str_bench_size:  .string "\n================================================\nBENCHMARK: %dx%d (hardcoded test pattern)\n================================================\n"
str_bench_row:   .string "| %3dx%-3d | %-16lu |\n"
str_bench_sep:   .string "+--------+------------------+\n"

# ============================================================
# .bss — max 512x512 = 262144 floats = 1 048 576 bytes each
# ============================================================
    .section .bss
    .balign 16

silent_mode: .space 4         # 1 = suppress debug prints, 0 = normal
work_real:   .space 1048576   # working buffer real (forward FFT)
work_imag:   .space 1048576   # working buffer imag (forward FFT)
work2_real:  .space 1048576   # edge path buffer real
work2_imag:  .space 1048576   # edge path buffer imag
fft_mag:     .space 1048576   # log-scaled FFT magnitude output
edge_mag:    .space 1048576   # spatial edge magnitude output
col_buf_r:   .space 2048      # column gather/scatter (max 512 floats)
col_buf_i:   .space 2048
tw_real:     .space 1024      # forward twiddle factors (max N/2=256)
tw_imag:     .space 1024
tw2_real:    .space 1024      # inverse twiddle factors
tw2_imag:    .space 1024
buf_r:       .space 2048      # M3 bit-reverse temp buffer
buf_i:       .space 2048

# ============================================================
# .text
# ============================================================
    .section .text
    .globl main

# ------------------------------------------------------------
# log2_int — identical to M3
# in: a0=n   out: a0=floor(log2(n))
# ------------------------------------------------------------
log2_int:
        li      a1, 0
.Ll2_lp:
        li      t0, 1
        ble     a0, t0, .Ll2_dn
        srli    a0, a0, 1
        addi    a1, a1, 1
        j       .Ll2_lp
.Ll2_dn:
        mv      a0, a1
        ret

# ------------------------------------------------------------
# vec_generate_twiddle_factors — verbatim from M3
# Forward: W[k] = e^{-j2πk/N}
# in: a0=real*, a1=imag*, a2=n
# ------------------------------------------------------------
vec_generate_twiddle_factors:
        addi    sp, sp, -112
        sd      ra,  104(sp)
        sd      s0,   96(sp); sd      s1,   88(sp); sd      s2,   80(sp)
        sd      s3,   72(sp); sd      s4,   64(sp); sd      s5,   56(sp)
        fsd     fs0,  48(sp); fsd     fs1,  40(sp); fsd     fs2,  32(sp)
        fsd     fs3,  24(sp); fsd     fs4,  16(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2
        srli    s3, s2, 1
        la      t0, const_2pi; flw ft0, 0(t0)
        fneg.s  ft0, ft0                     # angle = -2pi/N
        fcvt.s.w ft1, s2
        fdiv.s  fs0, ft0, ft1
        fmv.s   fa0, fs0; call cosf; fmv.s fs1, fa0
        fmv.s   fa0, fs0; call sinf; fmv.s fs2, fa0
        vsetvli s4, s3, e32, m1, ta, ma
        fcvt.s.w ft0, s4
        fmul.s  fa0, fs0, ft0; fmv.s fs0, fa0
        call    cosf; fmv.s fs3, fa0
        fmv.s   fa0, fs0; call sinf; fmv.s fs4, fa0
        la      t0, const_1f; flw fa1, 0(t0)
        fcvt.s.w fa2, zero
        li      t1, 0
.Lgtv_first_chunk:
        bge     t1, s4, .Lgtv_first_done
        slli    t2, t1, 2
        add     t3, s0, t2; fsw fa1, 0(t3)
        add     t3, s1, t2; fsw fa2, 0(t3)
        fmul.s  ft0, fa1, fs1; fmul.s ft1, fa2, fs2; fsub.s ft2, ft0, ft1
        fmul.s  ft0, fa1, fs2; fmul.s ft1, fa2, fs1; fadd.s fa2, ft0, ft1
        fmv.s   fa1, ft2
        addi    t1, t1, 1; j .Lgtv_first_chunk
.Lgtv_first_done:
        vsetvli zero, s4, e32, m1, ta, ma
        vle32.v v1, (s0); vle32.v v2, (s1)
        mv      s5, s4
.Lgtv_chunk_loop:
        sub     t0, s3, s5; blez t0, .Lgtv_end
        vsetvli t1, t0, e32, m1, ta, ma
        vfmul.vf v3, v1, fs3; vfmul.vf v4, v2, fs4; vfsub.vv v5, v3, v4
        vfmul.vf v3, v1, fs4; vfmul.vf v4, v2, fs3; vfadd.vv v6, v3, v4
        slli    t2, s5, 2
        add     t3, s0, t2; vse32.v v5, (t3)
        add     t3, s1, t2; vse32.v v6, (t3)
        vmv.v.v v1, v5; vmv.v.v v2, v6
        add     s5, s5, t1; j .Lgtv_chunk_loop
.Lgtv_end:
        ld      ra,  104(sp)
        ld      s0,   96(sp); ld      s1,   88(sp); ld      s2,   80(sp)
        ld      s3,   72(sp); ld      s4,   64(sp); ld      s5,   56(sp)
        fld     fs0,  48(sp); fld     fs1,  40(sp); fld     fs2,  32(sp)
        fld     fs3,  24(sp); fld     fs4,  16(sp)
        addi    sp, sp, 112
        ret

# ------------------------------------------------------------
# negate_array
# Negate all floats — used to make inverse twiddles from forward twiddles
# in: a0=ptr*, a1=count
# ------------------------------------------------------------
negate_array:
        li      t0, 0
.Lna_loop:
        bge     t0, a1, .Lna_done
        slli    t1, t0, 2; add t2, a0, t1
        flw     ft0, 0(t2); fneg.s ft0, ft0; fsw ft0, 0(t2)
        addi    t0, t0, 1; j .Lna_loop
.Lna_done:
        ret

# ------------------------------------------------------------
# vec_bit_reverse_array — verbatim from M3
# in: a0=xr*, a1=xi*, a2=n
# ------------------------------------------------------------
vec_bit_reverse_array:
        addi    sp, sp, -64
        sd      ra,  56(sp); sd s0, 48(sp); sd s1, 40(sp)
        sd      s2,  32(sp); sd s3, 24(sp); sd s4, 16(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2
        mv      a0, s2; call log2_int; mv s3, a0
        li      s4, 0
.Lvbr_lp:
        sub     t0, s2, s4; blez t0, .Lvbr_copy
        vsetvli t1, t0, e32, m1, ta, ma
        vid.v   v1; vmv.v.x v2, s4; vadd.vv v1, v1, v2
        vmv.v.i v9, 0; li t3, 0
.Lvbr_bits:
        bge     t3, s3, .Lvbr_bits_dn
        vsrl.vx v10, v1, t3; vand.vi v10, v10, 1
        sub     t5, s3, t3; addi t5, t5, -1
        vsll.vx v10, v10, t5; vor.vv v9, v9, v10
        addi    t3, t3, 1; j .Lvbr_bits
.Lvbr_bits_dn:
        vsll.vi v10, v9, 2
        slli    t2, s4, 2
        la      t3, buf_r; add t3, t3, t2
        vluxei32.v v11, (s0), v10; vse32.v v11, (t3)
        la      t3, buf_i; add t3, t3, t2
        vluxei32.v v11, (s1), v10; vse32.v v11, (t3)
        add     s4, s4, t1; j .Lvbr_lp
.Lvbr_copy:
        li      s4, 0
.Lvbr_cp_lp:
        sub     t0, s2, s4; blez t0, .Lvbr_dn
        vsetvli t1, t0, e32, m1, ta, ma
        slli    t2, s4, 2
        la      t3, buf_r; add t3, t3, t2
        vle32.v v1, (t3); add t4, s0, t2; vse32.v v1, (t4)
        la      t3, buf_i; add t3, t3, t2
        vle32.v v1, (t3); add t4, s1, t2; vse32.v v1, (t4)
        add     s4, s4, t1; j .Lvbr_cp_lp
.Lvbr_dn:
        ld      s4, 16(sp); ld s3, 24(sp); ld s2, 32(sp)
        ld      s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# vec_butterfly_iterative — verbatim from M3
# in: a0=xr*, a1=xi*, a2=tw_r*, a3=tw_i*, a4=n
# ------------------------------------------------------------
vec_butterfly_iterative:
        addi    sp, sp, -96
        sd      ra,  88(sp); sd s0, 80(sp); sd s1, 72(sp); sd s2, 64(sp)
        sd      s3,  56(sp); sd s4, 48(sp); sd s5, 40(sp); sd s6, 32(sp)
        sd      s7,  24(sp); sd s8, 16(sp); sd s9, 8(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2; mv s3, a3; mv s4, a4
        li      s5, 2
.Lvi_outer:
        bgt     s5, s4, .Lvi_done
        srli    s6, s5, 1
        div     t0, s4, s5; slli s7, t0, 2
        li      s8, 0
.Lvi_jlp:
        bge     s8, s4, .Lvi_jnx
        li      s9, 0
.Lvi_klp:
        sub     t0, s6, s9; blez t0, .Lvi_knx
        vsetvli t1, t0, e32, m1, ta, ma
        mul     t2, s9, s7
        add     t3, s2, t2; vlse32.v v1, (t3), s7
        add     t3, s3, t2; vlse32.v v2, (t3), s7
        add     t2, s8, s9; slli t2, t2, 2
        add     t3, s0, t2; vle32.v v3, (t3)
        add     t3, s1, t2; vle32.v v4, (t3)
        add     t2, s8, s9; add t2, t2, s6; slli t2, t2, 2
        add     t3, s0, t2; vle32.v v5, (t3)
        add     t3, s1, t2; vle32.v v6, (t3)
        vfmul.vv v7, v1, v5; vfmul.vv v8, v2, v6; vfsub.vv v7, v7, v8
        vfmul.vv v8, v1, v6; vfmul.vv v9, v2, v5; vfadd.vv v8, v8, v9
        vfadd.vv v10, v3, v7; vfadd.vv v11, v4, v8
        add     t2, s8, s9; slli t2, t2, 2
        add     t3, s0, t2; vse32.v v10, (t3)
        add     t3, s1, t2; vse32.v v11, (t3)
        vfsub.vv v10, v3, v7; vfsub.vv v11, v4, v8
        add     t2, s8, s9; add t2, t2, s6; slli t2, t2, 2
        add     t3, s0, t2; vse32.v v10, (t3)
        add     t3, s1, t2; vse32.v v11, (t3)
        add     s9, s9, t1; j .Lvi_klp
.Lvi_knx:
        add     s8, s8, s5; j .Lvi_jlp
.Lvi_jnx:
        slli    s5, s5, 1; j .Lvi_outer
.Lvi_done:
        ld      s9, 8(sp);  ld s8, 16(sp); ld s7, 24(sp); ld s6, 32(sp)
        ld      s5, 40(sp); ld s4, 48(sp); ld s3, 56(sp); ld s2, 64(sp)
        ld      s1, 72(sp); ld s0, 80(sp); ld ra, 88(sp)
        addi    sp, sp, 96; ret

# ------------------------------------------------------------
# fft_1d_vec — verbatim from M3
# in: a0=xr*, a1=xi*, a2=tw_r*, a3=tw_i*, a4=n
# ------------------------------------------------------------
fft_1d_vec:
        addi    sp, sp, -64
        sd      ra,  56(sp); sd s0, 48(sp); sd s1, 40(sp)
        sd      s2,  32(sp); sd s3, 24(sp); sd s4, 16(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2; mv s3, a3; mv s4, a4
        mv      a0, s0; mv a1, s1; mv a2, s4; call vec_bit_reverse_array
        mv      a0, s0; mv a1, s1; mv a2, s2; mv a3, s3; mv a4, s4
        call    vec_butterfly_iterative
        ld      s4, 16(sp); ld s3, 24(sp); ld s2, 32(sp)
        ld      s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# fft_rows
# Apply fft_1d_vec to every row of NxN image
# Row i starts at offset i*N*4 bytes from base pointer
# in: a0=real*, a1=imag*, a2=tw_r*, a3=tw_i*, a4=N
# ------------------------------------------------------------
fft_rows:
        addi    sp, sp, -64
        sd      ra, 56(sp); sd s0, 48(sp); sd s1, 40(sp)
        sd      s2, 32(sp); sd s3, 24(sp); sd s4, 16(sp); sd s5, 8(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2; mv s3, a3; mv s4, a4
        li      s5, 0
.Lfr_loop:
        bge     s5, s4, .Lfr_done
        mul     t0, s5, s4; slli t0, t0, 2
        add     a0, s0, t0; add a1, s1, t0
        mv      a2, s2; mv a3, s3; mv a4, s4
        call    fft_1d_vec
        addi    s5, s5, 1; j .Lfr_loop
.Lfr_done:
        ld      s5, 8(sp); ld s4, 16(sp); ld s3, 24(sp)
        ld      s2, 32(sp); ld s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# col_gather
# Gather column j from NxN image into contiguous buffer
# Address of pixel[i][j] = base + (i*N + j)*4
# in: a0=real*, a1=imag*, a2=col_buf_r*, a3=col_buf_i*, a4=col_j, a5=N
# ------------------------------------------------------------
col_gather:
        li      t0, 0; slli t3, a5, 2
.Lcg_loop:
        bge     t0, a5, .Lcg_done
        mul     t1, t0, t3; slli t2, a4, 2; add t1, t1, t2
        add     t4, a0, t1; flw ft0, 0(t4)
        slli    t5, t0, 2
        add     t4, a2, t5; fsw ft0, 0(t4)
        add     t4, a1, t1; flw ft0, 0(t4)
        add     t4, a3, t5; fsw ft0, 0(t4)
        addi    t0, t0, 1; j .Lcg_loop
.Lcg_done:
        ret

# ------------------------------------------------------------
# col_scatter
# Scatter buffer back into column j of NxN image
# in: a0=real*, a1=imag*, a2=col_buf_r*, a3=col_buf_i*, a4=col_j, a5=N
# ------------------------------------------------------------
col_scatter:
        li      t0, 0; slli t3, a5, 2
.Lcs_loop:
        bge     t0, a5, .Lcs_done
        mul     t1, t0, t3; slli t2, a4, 2; add t1, t1, t2
        slli    t5, t0, 2
        add     t4, a2, t5; flw ft0, 0(t4)
        add     t4, a0, t1; fsw ft0, 0(t4)
        add     t4, a3, t5; flw ft0, 0(t4)
        add     t4, a1, t1; fsw ft0, 0(t4)
        addi    t0, t0, 1; j .Lcs_loop
.Lcs_done:
        ret

# ------------------------------------------------------------
# fft_cols
# Gather each column, FFT it, scatter back — for all N columns
# Column elements are N floats apart in row-major layout,
# so we use col_buf to make each column contiguous for fft_1d_vec
# in: a0=real*, a1=imag*, a2=tw_r*, a3=tw_i*, a4=N
# ------------------------------------------------------------
fft_cols:
        addi    sp, sp, -80
        sd      ra, 72(sp); sd s0, 64(sp); sd s1, 56(sp); sd s2, 48(sp)
        sd      s3, 40(sp); sd s4, 32(sp); sd s5, 24(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2; mv s3, a3; mv s4, a4
        li      s5, 0
.Lfc_loop:
        bge     s5, s4, .Lfc_done
        mv      a0, s0; mv a1, s1
        la      a2, col_buf_r; la a3, col_buf_i
        mv      a4, s5; mv a5, s4; call col_gather
        la      a0, col_buf_r; la a1, col_buf_i
        mv      a2, s2; mv a3, s3; mv a4, s4; call fft_1d_vec
        mv      a0, s0; mv a1, s1
        la      a2, col_buf_r; la a3, col_buf_i
        mv      a4, s5; mv a5, s4; call col_scatter
        addi    s5, s5, 1; j .Lfc_loop
.Lfc_done:
        ld      s5, 24(sp); ld s4, 32(sp); ld s3, 40(sp)
        ld      s2, 48(sp); ld s1, 56(sp); ld s0, 64(sp); ld ra, 72(sp)
        addi    sp, sp, 80; ret

# ------------------------------------------------------------
# fftshift_2d
# Swap quadrants to move DC to center (even N)
# in: a0=real*, a1=imag*, a2=N
# ------------------------------------------------------------
fftshift_2d:
        addi    sp, sp, -48
        sd      ra, 40(sp); sd s0, 32(sp); sd s1, 24(sp)
        sd      s2, 16(sp); sd s3, 8(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2
        srli    s3, s2, 1
        li      t6, 0
.Lfs_iloop:
        bge     t6, s3, .Lfs_done
        li      t5, 0
.Lfs_jloop:
        bge     t5, s3, .Lfs_jnx
        mul     t0, t6, s2; add t0, t0, t5; slli t0, t0, 2
        add     t1, t6, s3; mul t1, t1, s2; add t2, t5, s3
        add     t1, t1, t2; slli t1, t1, 2
        add     t2, s0, t0; flw ft0, 0(t2)
        add     t3, s0, t1; flw ft1, 0(t3)
        fsw     ft1, 0(t2); fsw ft0, 0(t3)
        add     t2, s1, t0; flw ft0, 0(t2)
        add     t3, s1, t1; flw ft1, 0(t3)
        fsw     ft1, 0(t2); fsw ft0, 0(t3)
        mul     t0, t6, s2; add t2, t5, s3; add t0, t0, t2; slli t0, t0, 2
        add     t1, t6, s3; mul t1, t1, s2; add t1, t1, t5; slli t1, t1, 2
        add     t2, s0, t0; flw ft0, 0(t2)
        add     t3, s0, t1; flw ft1, 0(t3)
        fsw     ft1, 0(t2); fsw ft0, 0(t3)
        add     t2, s1, t0; flw ft0, 0(t2)
        add     t3, s1, t1; flw ft1, 0(t3)
        fsw     ft1, 0(t2); fsw ft0, 0(t3)
        addi    t5, t5, 1; j .Lfs_jloop
.Lfs_jnx:
        addi    t6, t6, 1; j .Lfs_iloop
.Lfs_done:
        ld      s3, 8(sp); ld s2, 16(sp); ld s1, 24(sp)
        ld      s0, 32(sp); ld ra, 40(sp)
        addi    sp, sp, 48; ret

# ------------------------------------------------------------
# apply_highpass (Updated to Gaussian Filter)
# After fftshift, DC is at center (N/2, N/2).
# Applies a smooth Gaussian curve: 1.0 - exp(-(du^2+dv^2)/(2*thresh^2))
# in: a0=real*, a1=imag*, a2=N
# ------------------------------------------------------------
apply_highpass:
        addi    sp, sp, -64
        sd      ra, 56(sp); sd s0, 48(sp); sd s1, 40(sp)
        sd      s2, 32(sp); sd s3, 24(sp); sd s4, 16(sp)
        fsd     fs0, 8(sp)               # Save float register

        mv      s0, a0; mv s1, a1; mv s2, a2

        # 1. Calculate threshold squared base (N / 6)
        li      t0, 6
        divu    t6, s2, t0               # thresh = N / 6
        mul     t6, t6, t6               # thresh^2
        slli    t6, t6, 1                # 2 * thresh^2
        fcvt.s.w fs0, t6                 # fs0 = 2.0 * thresh^2 (float)

        srli    s6, s2, 1                # center = N / 2
        
        li      s3, 0                    # loop counter i = 0
.Lhp_iloop:
        bge     s3, s2, .Lhp_done
        li      s4, 0                    # loop counter j = 0
.Lhp_jloop:
        bge     s4, s2, .Lhp_jnx

        # 2. Calculate Distance Squared: D^2 = du^2 + dv^2
        sub     t2, s3, s6               # du = i - N/2
        mul     t2, t2, t2               # du^2
        
        sub     t3, s4, s6               # dv = j - N/2
        mul     t3, t3, t3               # dv^2

        add     t2, t2, t3               # D^2 = du^2 + dv^2
        fcvt.s.w ft0, t2                 # ft0 = D^2 (converted to float)

        # 3. Calculate Exponent: -D^2 / (2 * thresh^2)
        fneg.s  ft0, ft0                 # ft0 = -D^2
        fdiv.s  fa0, ft0, fs0            # fa0 = -D^2 / (2 * thresh^2)

        # 4. Call math library expf
        call    expf                     # returns result in fa0

        # 5. Calculate Filter Multiplier: 1.0 - expf(...)
        la      t0, const_1f
        flw     ft1, 0(t0)               # ft1 = 1.0
        fsub.s  ft2, ft1, fa0            # ft2 = 1.0 - expf(...)

        # 6. Apply multiplier to real and imaginary bins
        mul     t2, s3, s2               # i * N
        add     t2, t2, s4               # i * N + j
        slli    t2, t2, 2                # offset in bytes

        add     t3, s0, t2               # real[i][j] address
        flw     ft0, 0(t3)
        fmul.s  ft0, ft0, ft2            # real *= filter_val
        fsw     ft0, 0(t3)

        add     t3, s1, t2               # imag[i][j] address
        flw     ft0, 0(t3)
        fmul.s  ft0, ft0, ft2            # imag *= filter_val
        fsw     ft0, 0(t3)

        addi    s4, s4, 1
        j       .Lhp_jloop
.Lhp_jnx:
        addi    s3, s3, 1
        j       .Lhp_iloop

.Lhp_done:
        fld     fs0, 8(sp)               # Restore float register
        ld      s4, 16(sp); ld s3, 24(sp); ld s2, 32(sp)
        ld      s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64
        ret
# ------------------------------------------------------------
# normalize_by_n2
# Divide all N*N complex values by N*N (IFFT normalization)
# in: a0=real*, a1=imag*, a2=N
# ------------------------------------------------------------
normalize_by_n2:
        addi    sp, sp, -16
        sd      ra, 8(sp)
        mv      t4, a0; mv t5, a1
        mul     t6, a2, a2       # count = N*N
        # scale = 1.0 / (N*N)
        fcvt.s.w ft3, t6
        la      t0, const_1f; flw ft4, 0(t0)
        fdiv.s  ft3, ft4, ft3    # ft3 = 1/N²
        li      t0, 0
.Lnn_loop:
        bge     t0, t6, .Lnn_done
        slli    t1, t0, 2
        add     t2, t4, t1; flw ft0, 0(t2); fmul.s ft0, ft0, ft3; fsw ft0, 0(t2)
        add     t2, t5, t1; flw ft0, 0(t2); fmul.s ft0, ft0, ft3; fsw ft0, 0(t2)
        addi    t0, t0, 1; j .Lnn_loop
.Lnn_done:
        ld      ra, 8(sp); addi sp, sp, 16; ret

# ------------------------------------------------------------
# compute_log_magnitude
# mag = sqrt(r^2+i^2),  out = log(1+mag)
# in: a0=real*, a1=imag*, a2=out*, a3=count
# ------------------------------------------------------------
compute_log_magnitude:
        addi    sp, sp, -64
        sd      ra, 56(sp); sd s0, 48(sp); sd s1, 40(sp)
        sd      s2, 32(sp); sd s3, 24(sp); sd s4, 16(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2; mv s3, a3
        li      s4, 0            # s4 = loop counter (callee-saved, survives logf)
.Lclm_loop:
        bge     s4, s3, .Lclm_done
        slli    t0, s4, 2
        add     t1, s0, t0; flw ft0, 0(t1)
        add     t1, s1, t0; flw ft1, 0(t1)
        fmul.s  ft2, ft0, ft0; fmul.s ft3, ft1, ft1
        fadd.s  ft2, ft2, ft3; fsqrt.s ft2, ft2
        la      t0, const_1f; flw ft3, 0(t0)
        fadd.s  fa0, ft3, ft2; call logf
        slli    t0, s4, 2; add t1, s2, t0; fsw fa0, 0(t1)
        addi    s4, s4, 1; j .Lclm_loop
.Lclm_done:
        ld      s4, 16(sp); ld s3, 24(sp); ld s2, 32(sp)
        ld      s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# compute_magnitude  (no log — for spatial edge output)
# mag = sqrt(r^2+i^2),  out = mag
# in: a0=real*, a1=imag*, a2=out*, a3=count
# ------------------------------------------------------------
compute_magnitude:
        addi    sp, sp, -48
        sd      ra, 40(sp); sd s0, 32(sp); sd s1, 24(sp)
        sd      s2, 16(sp); sd s3, 8(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2; mv s3, a3
        li      s4, 0            # can't use s4 — use t as loop counter (no calls)
        addi    sp, sp, -8; sd s4, 0(sp)  # save s4 manually
        li      s4, 0
.Lcm_loop:
        bge     s4, s3, .Lcm_done
        slli    t0, s4, 2
        add     t1, s0, t0; flw ft0, 0(t1)
        add     t1, s1, t0; flw ft1, 0(t1)
        fmul.s  ft2, ft0, ft0; fmul.s ft3, ft1, ft1
        fadd.s  ft2, ft2, ft3; fsqrt.s ft2, ft2
        add     t1, s2, t0; fsw ft2, 0(t1)
        addi    s4, s4, 1; j .Lcm_loop
.Lcm_done:
        ld      s4, 0(sp); addi sp, sp, 8
        ld      s3, 8(sp); ld s2, 16(sp); ld s1, 24(sp)
        ld      s0, 32(sp); ld ra, 40(sp)
        addi    sp, sp, 48; ret

# ------------------------------------------------------------
# copy_floats
# in: a0=dst*, a1=src*, a2=count
# ------------------------------------------------------------
copy_floats:
        li      t0, 0
.Lcf_loop:
        bge     t0, a2, .Lcf_done
        slli    t1, t0, 2
        add     t2, a1, t1; flw ft0, 0(t2)
        add     t3, a0, t1; fsw ft0, 0(t3)
        addi    t0, t0, 1; j .Lcf_loop
.Lcf_done:
        ret

# ------------------------------------------------------------
# zero_floats
# in: a0=dst*, a1=count
# ------------------------------------------------------------
zero_floats:
        fmv.w.x ft0, zero
        li      t0, 0
.Lzf_loop:
        bge     t0, a1, .Lzf_done
        slli    t1, t0, 2; add t2, a0, t1; fsw ft0, 0(t2)
        addi    t0, t0, 1; j .Lzf_loop
.Lzf_done:
        ret

# ------------------------------------------------------------
# print_8bins
# Print first 8 bins of a complex array with a header
# in: a0=real*, a1=imag*, a2=header_string*
# ------------------------------------------------------------
print_8bins:
        addi    sp, sp, -64
        sd      ra, 56(sp); sd s0, 48(sp); sd s1, 40(sp); sd s2, 32(sp); sd s3, 24(sp)
        mv      s0, a0; mv s1, a1
        mv      a0, a2; call printf
        li      s3, 0              # s3 = loop counter (callee-saved)
.Lpb_loop:
        li      t0, 8; bge s3, t0, .Lpb_done
        slli    t0, s3, 2
        add     t1, s0, t0; flw ft0, 0(t1)
        add     t1, s1, t0; flw ft1, 0(t1)
        fcvt.d.s ft0, ft0; fcvt.d.s ft1, ft1
        fmv.x.d  a2, ft0; fmv.x.d a3, ft1
        la      a0, fmt_bin; mv a1, s3; call printf
        addi    s3, s3, 1; j .Lpb_loop
.Lpb_done:
        ld      s3, 24(sp); ld s2, 32(sp); ld s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# print_col0_8
# Print first 8 elements of column 0 (stride = N*4)
# in: a0=real*, a1=imag*, a2=N, a3=header_string*
# ------------------------------------------------------------
print_col0_8:
        addi    sp, sp, -64
        sd      ra, 56(sp); sd s0, 48(sp); sd s1, 40(sp); sd s2, 32(sp); sd s3, 24(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2
        mv      a0, a3; call printf
        li      s3, 0              # s3 = loop counter (callee-saved, survives printf)
.Lpc_loop:
        li      t0, 8; bge s3, t0, .Lpc_done
        mul     t0, s3, s2; slli t0, t0, 2   # offset = i*N*4 (col 0, j=0)
        add     t1, s0, t0; flw ft0, 0(t1)
        add     t1, s1, t0; flw ft1, 0(t1)
        fcvt.d.s ft0, ft0; fcvt.d.s ft1, ft1
        fmv.x.d  a2, ft0; fmv.x.d a3, ft1
        la      a0, fmt_bin; mv a1, s3; call printf
        addi    s3, s3, 1; j .Lpc_loop
.Lpc_done:
        ld      s3, 24(sp); ld s2, 32(sp); ld s1, 40(sp); ld s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# write_chunked
# Write nbytes from buf to fd in chunks of max 65536
# in: a0=fd, a1=buf*, a2=nbytes
# ------------------------------------------------------------
write_chunked:
        addi    sp, sp, -32
        sd      ra, 24(sp); sd s0, 16(sp); sd s1, 8(sp)
        mv      s0, a0; mv s1, a1; mv t5, a2; li t4, 0
.Lwc_loop:
        blez    t5, .Lwc_done
        li      t3, 65536
        bge     t5, t3, .Lwc_use_chunk; mv t3, t5
.Lwc_use_chunk:
        mv      a0, s0; mv a1, s1; mv a2, t3; li a7, 64; ecall
        blez    a0, .Lwc_done
        add     t4, t4, a0; add s1, s1, a0; sub t5, t5, a0; j .Lwc_loop
.Lwc_done:
        mv      a0, t4
        ld      s1, 8(sp); ld s0, 16(sp); ld ra, 24(sp)
        addi    sp, sp, 32; ret

# ------------------------------------------------------------
# load_image_from_file
# Opens img_input.bin, reads [int32 N][int32 N][N*N float32]
# Pixels into work_real, work_imag zeroed.
# out: a0 = N on success, 0 on failure
# ------------------------------------------------------------
load_image_from_file:
        addi    sp, sp, -48
        sd      ra, 40(sp); sd s0, 32(sp); sd s1, 24(sp); sd s2, 16(sp)
        li      a0, -100; la a1, str_input_bin; li a2, 0; li a3, 0
        li      a7, 56; ecall
        mv      s0, a0; bltz s0, .Llif_fail
        addi    sp, sp, -8; mv a0, s0; mv a1, sp; li a2, 4; li a7, 63; ecall
        lw      s1, 0(sp); addi sp, sp, 8
        addi    sp, sp, -8; mv a0, s0; mv a1, sp; li a2, 4; li a7, 63; ecall
        addi    sp, sp, 8
        mul     t0, s1, s1; slli t0, t0, 2; mv s2, t0
        la      a1, work_real
.Llif_read_loop:
        blez    s2, .Llif_read_done
        li      t1, 65536; bge s2, t1, .Llif_use_chunk; mv t1, s2
.Llif_use_chunk:
        mv      a0, s0; mv a2, t1; li a7, 63; ecall
        blez    a0, .Llif_read_done
        add     a1, a1, a0; sub s2, s2, a0; j .Llif_read_loop
.Llif_read_done:
        mv      a0, s0; li a7, 57; ecall
        la      a0, work_imag; mul a1, s1, s1; call zero_floats
        la      a0, str_loaded; mv a1, s1; mv a2, s1; call printf
        mv      a0, s1
        ld      s2, 16(sp); ld s1, 24(sp); ld s0, 32(sp); ld ra, 40(sp)
        addi    sp, sp, 48; ret
.Llif_fail:
        li      a0, 0
        ld      s2, 16(sp); ld s1, 24(sp); ld s0, 32(sp); ld ra, 40(sp)
        addi    sp, sp, 48; ret

# ------------------------------------------------------------
# write_bin_output
# Write fft_result.bin: [N][N][fft_mag][edge_mag]
# in: a0 = N
# ------------------------------------------------------------
write_bin_output:
        addi    sp, sp, -64
        sd      ra, 56(sp); sd s0, 48(sp); sd s1, 40(sp)
        sd      s2, 32(sp); sd s3, 24(sp)
        mv      s0, a0; mul s1, s0, s0; slli s2, s1, 2
        li      a0, -100; la a1, str_fft_bin; li a2, 0x241; li a3, 0644
        li      a7, 56; ecall; mv s3, a0
        addi    sp, sp, -8; sw s0, 0(sp)
        mv      a0, s3; mv a1, sp; li a2, 4; li a7, 64; ecall
        addi    sp, sp, 8
        addi    sp, sp, -8; sw s0, 0(sp)
        mv      a0, s3; mv a1, sp; li a2, 4; li a7, 64; ecall
        addi    sp, sp, 8
        mv      a0, s3; la a1, fft_mag;  mv a2, s2; call write_chunked
        mv      a0, s3; la a1, edge_mag; mv a2, s2; call write_chunked
        mv      a0, s3; li a7, 57; ecall
        li      t0, 8; add t0, t0, s2; add t0, t0, s2
        la      a0, str_wrote_bin; mv a1, t0; call printf
        ld      s3, 24(sp); ld s2, 32(sp); ld s1, 40(sp)
        ld      s0, 48(sp); ld ra, 56(sp)
        addi    sp, sp, 64; ret

# ------------------------------------------------------------
# fft_2d_pipeline
# Full pipeline with accurate cycle counting.
# rdcycle wraps ONLY computation steps — prints are excluded.
# Cycle accumulator kept in s3 throughout.
#
# in:  a0=src_real*, a1=src_imag*, a2=N
# out: a0=total compute cycles, fft_mag[] and edge_mag[] filled
# ------------------------------------------------------------
fft_2d_pipeline:
        addi    sp, sp, -96
        sd      ra, 88(sp); sd s0, 80(sp); sd s1, 72(sp)
        sd      s2, 64(sp); sd s3, 56(sp); sd s4, 48(sp)
        mv      s0, a0; mv s1, a1; mv s2, a2
        li      s3, 0            # s3 = accumulated compute cycles
        # s4 = start cycle for each timed block (callee-saved, survives calls)

        # copy input into work buffers if not already there
        la      t0, work_real; beq s0, t0, .Lfp_skip_copy
        mul     a2, s2, s2
        la      a0, work_real; mv a1, s0; call copy_floats
        mul     a2, s2, s2
        la      a0, work_imag; mv a1, s1; call copy_floats
.Lfp_skip_copy:

        # --- FORWARD FFT ---
        # twiddle generation
        rdcycle s4
        la      a0, tw_real; la a1, tw_imag; mv a2, s2
        call    vec_generate_twiddle_factors
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # row FFTs
        rdcycle s4
        la      a0, work_real; la a1, work_imag
        la      a2, tw_real; la a3, tw_imag; mv a4, s2
        call    fft_rows
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # [PRINT 1] row 0 after row FFT — not counted
        la      t0, silent_mode; lw t0, 0(t0); bnez t0, .Lskip_p1
        la      a0, work_real; la a1, work_imag
        la      a2, str_row0_fft; call print_8bins
.Lskip_p1:

        # col FFTs
        rdcycle s4
        la      a0, work_real; la a1, work_imag
        la      a2, tw_real; la a3, tw_imag; mv a4, s2
        call    fft_cols
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # [PRINT 2] col 0 after col FFT — not counted
        la      t0, silent_mode; lw t0, 0(t0); bnez t0, .Lskip_p2
        la      a0, work_real; la a1, work_imag
        mv      a2, s2; la a3, str_col0_fft; call print_col0_8
.Lskip_p2:

        # copy work -> work2 for edge path
        rdcycle s4
        mul     a2, s2, s2
        la      a0, work2_real; la a1, work_real; call copy_floats
        mul     a2, s2, s2
        la      a0, work2_imag; la a1, work_imag; call copy_floats
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # fftshift + log magnitude
        rdcycle s4
        la      a0, work_real; la a1, work_imag; mv a2, s2
        call    fftshift_2d
        la      a0, work_real; la a1, work_imag
        la      a2, fft_mag; mul a3, s2, s2
        call    compute_log_magnitude
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # --- EDGE PATH ---
        # fftshift work2
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag; mv a2, s2
        call    fftshift_2d
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # [PRINT 3] center row after fftshift — not counted
        la      t0, silent_mode; lw t0, 0(t0); bnez t0, .Lskip_p3
        srli    t0, s2, 1
        mul     t0, t0, s2; slli t0, t0, 2
        la      t1, work2_real; add a0, t1, t0
        la      t1, work2_imag; add a1, t1, t0
        la      a2, str_after_shift; call print_8bins
.Lskip_p3:

        # highpass filter
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag; mv a2, s2
        call    apply_highpass
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # [PRINT 4] center row after highpass — not counted
        la      t0, silent_mode; lw t0, 0(t0); bnez t0, .Lskip_p4
        srli    t0, s2, 1
        mul     t0, t0, s2; slli t0, t0, 2
        la      t1, work2_real; add a0, t1, t0
        la      t1, work2_imag; add a1, t1, t0
        la      a2, str_after_hp; call print_8bins
.Lskip_p4:
        # ifftshift
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag; mv a2, s2
        call    fftshift_2d
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # --- IFFT ---
        # inverse twiddle generation
        rdcycle s4
        la      a0, tw2_real; la a1, tw2_imag; mv a2, s2
        call    vec_generate_twiddle_factors
        la      a0, tw2_imag; srli a1, s2, 1
        call    negate_array
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # IFFT rows
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag
        la      a2, tw2_real; la a3, tw2_imag; mv a4, s2
        call    fft_rows
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # IFFT cols
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag
        la      a2, tw2_real; la a3, tw2_imag; mv a4, s2
        call    fft_cols
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # normalize by 1/N²
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag; mv a2, s2
        call    normalize_by_n2
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        # [PRINT 5] row 0 after IFFT — not counted
        la      t0, silent_mode; lw t0, 0(t0); bnez t0, .Lskip_p5
        la      a0, work2_real; la a1, work2_imag
        la      a2, str_after_ifft; call print_8bins
.Lskip_p5:

        # spatial magnitude (log-scaled for better dynamic range)
        rdcycle s4
        la      a0, work2_real; la a1, work2_imag
        la      a2, edge_mag; mul a3, s2, s2
        call    compute_log_magnitude
        rdcycle t1; sub t1, t1, s4; add s3, s3, t1

        mv      a0, s3           # return total compute cycles
        ld      s4, 48(sp); ld s3, 56(sp); ld s2, 64(sp)
        ld      s1, 72(sp); ld s0, 80(sp); ld ra, 88(sp)
        addi    sp, sp, 96; ret

# ------------------------------------------------------------
# strcmp_bench
# ------------------------------------------------------------
strcmp_bench:
        la      t0, str_bench
.Lscb_loop:
        lbu     t2, 0(a0); lbu t3, 0(t0)
        bne     t2, t3, .Lscb_no
        beqz    t2, .Lscb_yes
        addi    a0, a0, 1; addi t0, t0, 1; j .Lscb_loop
.Lscb_yes:
        li      a0, 1; ret
.Lscb_no:
        li      a0, 0; ret

# ------------------------------------------------------------
# bench_one_size
# Run pipeline on hardcoded NxN test pattern, print cross-checks
# and store cycle count in s0 for table printing
# in:  a0 = N
# out: a0 = cycle count
# ------------------------------------------------------------
bench_one_size:
        addi    sp, sp, -48
        sd      ra, 40(sp); sd s0, 32(sp); sd s1, 24(sp)
        sd      s2, 16(sp); sd s3, 8(sp)
        mv      s1, a0           # s1 = N

        # print benchmark heading
        la      a0, str_bench_size; mv a1, s1; mv a2, s1; call printf

        # load hardcoded test data based on N
        li      t0, 8; beq s1, t0, .Lbo_8
        li      t0, 16; beq s1, t0, .Lbo_16
        # default 32x32
        mul     a2, s1, s1
        la      a0, work_real; la a1, img_real_32; call copy_floats
        mul     a2, s1, s1
        la      a0, work_imag; la a1, img_imag_32; call copy_floats
        j       .Lbo_run
.Lbo_8:
        mul     a2, s1, s1
        la      a0, work_real; la a1, img_real_8; call copy_floats
        mul     a2, s1, s1
        la      a0, work_imag; la a1, img_imag_8; call copy_floats
        j       .Lbo_run
.Lbo_16:
        mul     a2, s1, s1
        la      a0, work_real; la a1, img_real_16; call copy_floats
        mul     a2, s1, s1
        la      a0, work_imag; la a1, img_imag_16; call copy_floats

.Lbo_run:
        # first run pipeline with prints ON (for debug output, untimed)
        la      t0, silent_mode; sw zero, 0(t0)      # silent OFF
        la      a0, work_real; la a1, work_imag; mv a2, s1
        call    fft_2d_pipeline

        # reload data (pipeline modifies work buffers)
        li      t0, 8;  beq s1, t0, .Lbo_reload8
        li      t0, 16; beq s1, t0, .Lbo_reload16
        mul     a2, s1, s1
        la      a0, work_real; la a1, img_real_32; call copy_floats
        mul     a2, s1, s1
        la      a0, work_imag; la a1, img_imag_32; call copy_floats
        j       .Lbo_time
.Lbo_reload8:
        li      a2, 64
        la      a0, work_real; la a1, img_real_8; call copy_floats
        li      a2, 64
        la      a0, work_imag; la a1, img_imag_8; call copy_floats
        j       .Lbo_time
.Lbo_reload16:
        li      a2, 256
        la      a0, work_real; la a1, img_real_16; call copy_floats
        li      a2, 256
        la      a0, work_imag; la a1, img_imag_16; call copy_floats

.Lbo_time:
        # now time the pipeline with prints OFF
        la      t0, silent_mode; li t1, 1; sw t1, 0(t0)  # silent ON
        rdcycle s0                        # start cycle
        la      a0, work_real; la a1, work_imag; mv a2, s1
        call    fft_2d_pipeline
        rdcycle t0                        # end cycle
        sub     s0, t0, s0                # elapsed cycles
        la      t0, silent_mode; sw zero, 0(t0)           # silent OFF

        # print cycle count for this size
        la      a0, fmt_cycles; mv a1, s0; call printf

        mv      a0, s0           # return cycles
        ld      s3, 8(sp); ld s2, 16(sp); ld s1, 24(sp)
        ld      s0, 32(sp); ld ra, 40(sp)
        addi    sp, sp, 48; ret

# ------------------------------------------------------------
# main
# ------------------------------------------------------------
main:
        addi    sp, sp, -48
        sd      ra, 40(sp); sd s0, 32(sp); sd s1, 24(sp); sd s2, 16(sp)
        mv      s0, a0; mv s1, a1

        call    load_image_from_file
        mv      s2, a0

        bnez    s2, .Lmain_have_image

        # no input file — run performance benchmark on 8x8, 16x16, 32x32
        la      a0, str_no_input; call printf

        # warmup pass — untimed, primes QEMU JIT so 8x8 isn't penalized
        la      t0, silent_mode; li t1, 1; sw t1, 0(t0)   # silent ON
        li      a2, 64
        la      a0, work_real; la a1, img_real_8; call copy_floats
        li      a2, 64
        la      a0, work_imag; la a1, img_imag_8; call copy_floats
        la      a0, work_real; la a1, work_imag; li a2, 8
        call    fft_2d_pipeline
        la      t0, silent_mode; sw zero, 0(t0)            # silent OFF

        li      a0, 8;  call bench_one_size; mv s2, a0
        li      a0, 16; call bench_one_size; mv s1, a0
        li      a0, 32; call bench_one_size; mv s0, a0

        # print performance table
        la      a0, str_bench_hdr; call printf
        la      a0, str_bench_row; li a1, 8;  li a2, 8;  mv a3, s2; call printf
        la      a0, str_bench_row; li a1, 16; li a2, 16; mv a3, s1; call printf
        la      a0, str_bench_row; li a1, 32; li a2, 32; mv a3, s0; call printf
        la      a0, str_bench_sep; call printf
        j       .Lmain_exit

.Lmain_have_image:
        la      a0, fmt_sep; call printf
        la      a0, fmt_size_hdr; mv a1, s2; mv a2, s2; call printf

        la      a0, work_real; la a1, work_imag; mv a2, s2
        call    fft_2d_pipeline
        mv      t0, a0
        la      a0, fmt_cycles; mv a1, t0; call printf

        mv      a0, s2; call write_bin_output

.Lmain_exit:
        li      a0, 0
        ld      s2, 16(sp); ld s1, 24(sp); ld s0, 32(sp); ld ra, 40(sp)
        addi    sp, sp, 48; ret
