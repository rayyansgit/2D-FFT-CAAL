
# Build:
#   riscv64-linux-gnu-gcc -march=rv64gcv -O2 -o fft_live fft_live.s -lm -static
# Run:
#   qemu-riscv64 -cpu max ./fft_live

    .section .data
    .balign 4

    .section .rodata
    .balign 4
const_2pi:      .float  6.28318530717959
const_1f:       .float  1.0
const_255:      .float  255.0

str_frame_in:   .string "/dev/shm/fft_frame.bin"
str_edges_out:  .string "/dev/shm/fft_edges.bin"
str_ready_flag: .string "/dev/shm/fft_ready"
str_ready_tmp:  .string "/dev/shm/fft_ready.tmp"
str_startup:    .string "FFT Live Server started. N=256. Waiting for frames...\n"
str_processed:  .string "Frame processed. N=%d cycles=%lu\n"
fmt_uint:       .string "%lu\n"

# ============================================================
# .bss — 256x256 = 65536 floats = 262144 bytes per buffer
# ============================================================
    .section .bss
    .balign 16

# Main working buffers
work_real:      .space 1048576  # 512*512 floats (max)
work_imag:      .space 1048576
# Transpose buffer for column FFT
trans_real:     .space 1048576
trans_imag:     .space 1048576
# Output
edge_mag:       .space 1048576

# Twiddle factors — precomputed once at startup
# Max N/2 = 128 floats per twiddle array
tw_real:        .space 1024     # 256 floats (N=512, N/2=256)
tw_imag:        .space 1024

# Bit reversal temp (for vec_bit_reverse_array)
buf_r:          .space 2048     # 512 floats (N=512)
buf_i:          .space 2048

# Column gather buffer (single column)
col_buf_r:      .space 2048
col_buf_i:      .space 2048

# Stored N (read from input file)
current_N:      .space 8

# Place this in the .bss section
# Precomputed column distance tracking: 512 floats (N=512 max)
coord_buf:      .space 2048

# ============================================================
    .section .text
    .globl main

# ============================================================
# log2_int — floor(log2(n))
# ============================================================
log2_int:
    li   a1, 0
.Ll2_lp:
    li   t0, 1; ble a0, t0, .Ll2_dn
    srli a0, a0, 1; addi a1, a1, 1; j .Ll2_lp
.Ll2_dn:
    mv   a0, a1; ret

# ============================================================
# vec_generate_twiddle_factors — M3 verbatim
# in: a0=real*, a1=imag*, a2=n
# ============================================================
vec_generate_twiddle_factors:
    addi sp, sp, -112
    sd ra,104(sp); sd s0,96(sp); sd s1,88(sp); sd s2,80(sp)
    sd s3,72(sp);  sd s4,64(sp); sd s5,56(sp)
    fsd fs0,48(sp); fsd fs1,40(sp); fsd fs2,32(sp)
    fsd fs3,24(sp); fsd fs4,16(sp)
    mv s0,a0; mv s1,a1; mv s2,a2; srli s3,s2,1
    la t0,const_2pi; flw ft0,0(t0); fneg.s ft0,ft0
    fcvt.s.w ft1,s2; fdiv.s fs0,ft0,ft1
    fmv.s fa0,fs0; call cosf; fmv.s fs1,fa0
    fmv.s fa0,fs0; call sinf; fmv.s fs2,fa0
    vsetvli s4,s3,e32,m1,ta,ma
    fcvt.s.w ft0,s4; fmul.s fa0,fs0,ft0; fmv.s fs0,fa0
    call cosf; fmv.s fs3,fa0
    fmv.s fa0,fs0; call sinf; fmv.s fs4,fa0
    la t0,const_1f; flw fa1,0(t0); fcvt.s.w fa2,zero
    li t1,0
.Lgtv_fc:
    bge t1,s4,.Lgtv_fd
    slli t2,t1,2
    add t3,s0,t2; fsw fa1,0(t3)
    add t3,s1,t2; fsw fa2,0(t3)
    fmul.s ft0,fa1,fs1; fmul.s ft1,fa2,fs2; fsub.s ft2,ft0,ft1
    fmul.s ft0,fa1,fs2; fmul.s ft1,fa2,fs1; fadd.s fa2,ft0,ft1
    fmv.s fa1,ft2; addi t1,t1,1; j .Lgtv_fc
.Lgtv_fd:
    vsetvli zero,s4,e32,m1,ta,ma
    vle32.v v1,(s0); vle32.v v2,(s1); mv s5,s4
.Lgtv_cl:
    sub t0,s3,s5; blez t0,.Lgtv_end
    vsetvli t1,t0,e32,m1,ta,ma
    vfmul.vf v3,v1,fs3; vfmul.vf v4,v2,fs4; vfsub.vv v5,v3,v4
    vfmul.vf v3,v1,fs4; vfmul.vf v4,v2,fs3; vfadd.vv v6,v3,v4
    slli t2,s5,2
    add t3,s0,t2; vse32.v v5,(t3)
    add t3,s1,t2; vse32.v v6,(t3)
    vmv.v.v v1,v5; vmv.v.v v2,v6; add s5,s5,t1; j .Lgtv_cl
.Lgtv_end:
    ld ra,104(sp); ld s0,96(sp); ld s1,88(sp); ld s2,80(sp)
    ld s3,72(sp);  ld s4,64(sp); ld s5,56(sp)
    fld fs0,48(sp); fld fs1,40(sp); fld fs2,32(sp)
    fld fs3,24(sp); fld fs4,16(sp)
    addi sp,sp,112; ret


# ============================================================
# precompute_coords_vec
# Vectorized precomputation of (j - N/2)^2 for the filter grid
# in: a0 = N
# ============================================================
precompute_coords_vec:
    srli t0, a0, 1           # t0 = N/2
    fcvt.s.w ft0, t0         # ft0 = (float)(N/2)
    la t1, coord_buf
    li t2, 0                 # j = 0
.Lpc_loop:
    sub t3, a0, t2           # Remaining elements
    blez t3, .Lpc_done
    vsetvli t4, t3, e32, m1, ta, ma
    
    vid.v v1                 # v1 = [0, 1, 2, ...] Indices
    vadd.vx v1, v1, t2       # v1 = current column elements j
    vfcvt.f.xu.v v2, v1      # Convert indices to float
    vfsub.vf v2, v2, ft0     # v2 = j - N/2
    vfmul.vv v3, v2, v2      # v3 = (j - N/2)^2
    
    slli t5, t2, 2
    add t6, t1, t5
    vse32.v v3, (t6)         # Store chunks to coord_buf
    
    add t2, t2, t4
    j .Lpc_loop
.Lpc_done:
    ret


# ============================================================
# vec_bit_reverse_array — M3 verbatim
# ============================================================
vec_bit_reverse_array:
    addi sp,sp,-64
    sd ra,56(sp); sd s0,48(sp); sd s1,40(sp)
    sd s2,32(sp); sd s3,24(sp); sd s4,16(sp)
    mv s0,a0; mv s1,a1; mv s2,a2
    mv a0,s2; call log2_int; mv s3,a0
    li s4,0
.Lvbr_lp:
    sub t0,s2,s4; blez t0,.Lvbr_copy
    vsetvli t1,t0,e32,m1,ta,ma
    vid.v v1; vmv.v.x v2,s4; vadd.vv v1,v1,v2
    vmv.v.i v9,0; li t3,0
.Lvbr_bits:
    bge t3,s3,.Lvbr_bd
    vsrl.vx v10,v1,t3; vand.vi v10,v10,1
    sub t5,s3,t3; addi t5,t5,-1
    vsll.vx v10,v10,t5; vor.vv v9,v9,v10
    addi t3,t3,1; j .Lvbr_bits
.Lvbr_bd:
    vsll.vi v10,v9,2; slli t2,s4,2
    la t3,buf_r; add t3,t3,t2
    vluxei32.v v11,(s0),v10; vse32.v v11,(t3)
    la t3,buf_i; add t3,t3,t2
    vluxei32.v v11,(s1),v10; vse32.v v11,(t3)
    add s4,s4,t1; j .Lvbr_lp
.Lvbr_copy:
    li s4,0
.Lvbr_cp:
    sub t0,s2,s4; blez t0,.Lvbr_dn
    vsetvli t1,t0,e32,m1,ta,ma; slli t2,s4,2
    la t3,buf_r; add t3,t3,t2
    vle32.v v1,(t3); add t4,s0,t2; vse32.v v1,(t4)
    la t3,buf_i; add t3,t3,t2
    vle32.v v1,(t3); add t4,s1,t2; vse32.v v1,(t4)
    add s4,s4,t1; j .Lvbr_cp
.Lvbr_dn:
    ld s4,16(sp); ld s3,24(sp); ld s2,32(sp)
    ld s1,40(sp); ld s0,48(sp); ld ra,56(sp)
    addi sp,sp,64; ret

# ============================================================
# vec_butterfly_iterative — M3 verbatim
# ============================================================
vec_butterfly_iterative:
    addi sp,sp,-96
    sd ra,88(sp); sd s0,80(sp); sd s1,72(sp); sd s2,64(sp)
    sd s3,56(sp); sd s4,48(sp); sd s5,40(sp); sd s6,32(sp)
    sd s7,24(sp); sd s8,16(sp); sd s9,8(sp)
    mv s0,a0; mv s1,a1; mv s2,a2; mv s3,a3; mv s4,a4
    li s5,2
.Lvi_outer:
    bgt s5,s4,.Lvi_done
    srli s6,s5,1; div t0,s4,s5; slli s7,t0,2; li s8,0
.Lvi_jlp:
    bge s8,s4,.Lvi_jnx; li s9,0
.Lvi_klp:
    sub t0,s6,s9; blez t0,.Lvi_knx
    vsetvli t1,t0,e32,m1,ta,ma
    mul t2,s9,s7; add t3,s2,t2; vlse32.v v1,(t3), s7
    add t3,s3,t2; vlse32.v v2,(t3), s7
    add t2,s8,s9; slli t2,t2,2
    add t3,s0,t2; vle32.v v3,(t3)
    add t3,s1,t2; vle32.v v4,(t3)
    add t2,s8,s9; add t2,t2,s6; slli t2,t2,2
    add t3,s0,t2; vle32.v v5,(t3)
    add t3,s1,t2; vle32.v v6,(t3)

# --- FMA Optimized Complex Multiplication ---
    vfmul.vv v7, v1, v5       # v7 = (v1 * v5)
    vfnmsac.vv v7, v2, v6     # v7 = -(v2 * v6) + v7
    
    vfmul.vv v8, v1, v6       # v8 = (v1 * v6)
    vfmacc.vv v8, v2, v5      # v8 = +(v2 * v5) + v8
    
    # --- Butterfly Adds ----
    vfadd.vv v10, v3, v7; 
    vfadd.vv v11, v4, v8

    add t2,s8,s9; slli t2,t2,2
    add t3,s0,t2; vse32.v v10,(t3)
    add t3,s1,t2; vse32.v v11,(t3)
    vfsub.vv v10,v3,v7; vfsub.vv v11,v4,v8
    add t2,s8,s9; add t2,t2,s6; slli t2,t2,2
    add t3,s0,t2; vse32.v v10,(t3)
    add t3,s1,t2; vse32.v v11,(t3)
    add s9,s9,t1; j .Lvi_klp
.Lvi_knx: add s8,s8,s5; j .Lvi_jlp
.Lvi_jnx: slli s5,s5,1; j .Lvi_outer
.Lvi_done:
    ld s9,8(sp);  ld s8,16(sp); ld s7,24(sp); ld s6,32(sp)
    ld s5,40(sp); ld s4,48(sp); ld s3,56(sp); ld s2,64(sp)
    ld s1,72(sp); ld s0,80(sp); ld ra,88(sp)
    addi sp,sp,96; ret

# ============================================================
# fft_1d_vec — M3 verbatim
# ============================================================
fft_1d_vec:
    addi sp,sp,-64
    sd ra,56(sp); sd s0,48(sp); sd s1,40(sp)
    sd s2,32(sp); sd s3,24(sp); sd s4,16(sp)
    mv s0,a0; mv s1,a1; mv s2,a2; mv s3,a3; mv s4,a4
    mv a0,s0; mv a1,s1; mv a2,s4; call vec_bit_reverse_array
    mv a0,s0; mv a1,s1; mv a2,s2; mv a3,s3; mv a4,s4
    call vec_butterfly_iterative
    ld s4,16(sp); ld s3,24(sp); ld s2,32(sp)
    ld s1,40(sp); ld s0,48(sp); ld ra,56(sp)
    addi sp,sp,64; ret

# ============================================================
# fft_rows_fast
# Run FFT on every row using precomputed twiddles
# in: a0=real*, a1=imag*, a2=tw_r*, a3=tw_i*, a4=N
# ============================================================
fft_rows_fast:
    addi sp,sp,-64
    sd ra,56(sp); sd s0,48(sp); sd s1,40(sp)
    sd s2,32(sp); sd s3,24(sp); sd s4,16(sp); sd s5,8(sp)
    mv s0,a0; mv s1,a1; mv s2,a2; mv s3,a3; mv s4,a4; li s5,0
.Lfrf_loop:
    bge s5,s4,.Lfrf_done
    mul t0,s5,s4; slli t0,t0,2
    add a0,s0,t0; add a1,s1,t0
    mv a2,s2; mv a3,s3; mv a4,s4
    call fft_1d_vec
    addi s5,s5,1; j .Lfrf_loop
.Lfrf_done:
    ld s5,8(sp); ld s4,16(sp); ld s3,24(sp)
    ld s2,32(sp); ld s1,40(sp); ld s0,48(sp); ld ra,56(sp)
    addi sp,sp,64; ret

# ============================================================
# transpose_NxN
# Transpose square matrix in-place using temp buffer
# in: a0=src_real*, a1=src_imag*, a2=dst_real*, a3=dst_imag*, a4=N
# Copies src[i][j] -> dst[j][i]
# This makes columns of src contiguous in dst rows,
# so we can run row FFTs on dst to get column FFTs of src
# ============================================================
transpose_NxN:
    addi sp,sp,-64
    sd ra,56(sp); sd s0,48(sp); sd s1,40(sp)
    sd s2,32(sp); sd s3,24(sp); sd s4,16(sp)
    mv s0,a0; mv s1,a1; mv s2,a2; mv s3,a3; mv s4,a4

    li t4,0          # i = 0
.Ltr_iloop:
    bge t4,s4,.Ltr_done
    li t5,0          # j = 0
.Ltr_jloop:
    bge t5,s4,.Ltr_jnx
    # src[i][j] offset = (i*N+j)*4
    mul t0,t4,s4; add t0,t0,t5; slli t0,t0,2
    # dst[j][i] offset = (j*N+i)*4
    mul t1,t5,s4; add t1,t1,t4; slli t1,t1,2
    add t2,s0,t0; flw ft0,0(t2)   # src_real[i][j]
    add t3,s2,t1; fsw ft0,0(t3)   # dst_real[j][i]
    add t2,s1,t0; flw ft0,0(t2)   # src_imag[i][j]
    add t3,s3,t1; fsw ft0,0(t3)   # dst_imag[j][i]
    addi t5,t5,1; j .Ltr_jloop
.Ltr_jnx:
    addi t4,t4,1; j .Ltr_iloop
.Ltr_done:
    ld s4,16(sp); ld s3,24(sp); ld s2,32(sp)
    ld s1,40(sp); ld s0,48(sp); ld ra,56(sp)
    addi sp,sp,64; ret

# ============================================================
# apply_butterworth_highpass
# Fully vectorized 1st-order Butterworth High-Pass Filter
# Formula: H(u,v) = D^2 / (D^2 + D0^2)
# in: a0=real*, a1=imag*, a2=N
# ============================================================
apply_butterworth_highpass:
    addi sp, sp, -80
    sd ra, 72(sp)
    sd s0, 64(sp)
    sd s1, 56(sp)
    sd s2, 48(sp)
    sd s3, 40(sp)
    fsd fs0, 32(sp)
    fsd fs1, 24(sp)
    fsd fs2, 16(sp)

    mv s0, a0              # real*
    mv s1, a1              # imag*
    mv s2, a2              # N

    # Calculate Cutoff Frequency D0^2 = (N/6)^2
    li t0, 6
    divu t1, s2, t0        # t1 = N/6
    fcvt.s.w ft0, t1       # ft0 = D0
    fmul.s fs0, ft0, ft0   # fs0 = D0^2

    # Calculate Center tracking variable (N/2)
    srli t0, s2, 1         
    fcvt.s.w fs1, t0       # fs1 = N/2

    li s3, 0               # i = 0 (row loop iterator)
.Lbw_row_loop:
    bge s3, s2, .Lbw_done

    # Calculate du^2 = (i - N/2)^2 for this row
    fcvt.s.w ft1, s3       
    fsub.s ft1, ft1, fs1   # ft1 = i - N/2
    fmul.s fs2, ft1, ft1   # fs2 = du^2

    # Base memory offsets for current row (i * N * 4)
    mul t0, s3, s2
    slli t0, t0, 2
    add t2, s0, t0         # current row real* pointer
    add t3, s1, t0         # current row imag* pointer

    li t4, 0               # j_offset = 0 (column loop)
.Lbw_col_loop:
    sub t0, s2, t4         # Remaining columns in row segment
    blez t0, .Lbw_col_next
    vsetvli t1, t0, e32, m1, ta, ma

    # Stream precomputed dv^2 from coord_buf
    la t0, coord_buf
    slli t5, t4, 2
    add t0, t0, t5
    vle32.v v1, (t0)       # v1 = dv^2

    # Compute Total Frequency Distance Squared: D^2 = du^2 + dv^2
    vfadd.vf v2, v1, fs2   # v2 = D^2

    # Compute Denominator: D^2 + D0^2
    vfadd.vf v3, v2, fs0   # v3 = D^2 + D0^2

    # Compute Filter Coefficient Matrix: H = D^2 / (D^2 + D0^2)
    vfdiv.vv v4, v2, v3    # v4 = H Matrix (Values scale smoothly between 0.0 and 1.0)

    # Load original complex values for the row segment
    add t0, t2, t5
    vle32.v v5, (t0)       # v5 = real component
    add t6, t3, t5
    vle32.v v6, (t6)       # v6 = imag component

    # Apply smooth attenuation: Real *= H, Imag *= H
    vfmul.vv v5, v5, v4
    vfmul.vv v6, v6, v4

    # Write-back filtered elements to memory
    vse32.v v5, (t0)
    vse32.v v6, (t6)

    add t4, t4, t1         # Advance column index by elements handled
    j .Lbw_col_loop

.Lbw_col_next:
    addi s3, s3, 1         # Step to next row index
    j .Lbw_row_loop

.Lbw_done:
    fld fs2, 16(sp)
    fld fs1, 24(sp)
    fld fs0, 32(sp)
    ld s3, 40(sp)
    ld s2, 48(sp)
    ld s1, 56(sp)
    ld s0, 64(sp)
    ld ra, 72(sp)
    addi sp, sp, 80
    ret

# ============================================================
# compute_magnitude_vec
# Vectorized: out[i] = sqrt(re[i]^2 + im[i]^2)
# in: a0=real*, a1=imag*, a2=out*, a3=count
# ============================================================
compute_magnitude_vec:
    addi sp,sp,-32
    sd ra,24(sp); sd s0,16(sp); sd s1,8(sp)
    mv s0,a0; mv s1,a1
    li t6,0
.Lcmv_loop:
    sub t0,a3,t6; blez t0,.Lcmv_done
    vsetvli t1,t0,e32,m1,ta,ma
    slli t2,t6,2
    add t3,s0,t2; vle32.v v1,(t3)   # load real chunk
    add t3,s1,t2; vle32.v v2,(t3)   # load imag chunk
    vfmul.vv v3,v1,v1               # re^2
    vfmul.vv v4,v2,v2               # im^2
    vfadd.vv v5,v3,v4               # re^2+im^2
    vfsqrt.v v6,v5                  # sqrt
    add t3,a2,t2; vse32.v v6,(t3)   # store magnitude
    add t6,t6,t1; j .Lcmv_loop
.Lcmv_done:
    ld s1,8(sp); ld s0,16(sp); ld ra,24(sp)
    addi sp,sp,32; ret

# ============================================================
# negate_array — negate tw2_imag to get inverse twiddles
# in: a0=ptr*, a1=count
# ============================================================
negate_array:
    li      t0, 0
.Lna_loop:
    bge     t0, a1, .Lna_done
    slli    t1, t0, 2; add t2, a0, t1
    flw     ft0, 0(t2); fneg.s ft0, ft0; fsw ft0, 0(t2)
    addi    t0, t0, 1; j .Lna_loop
.Lna_done:
    ret

# ============================================================
# normalize_by_n2 — divide all N*N complex values by N*N
# in: a0=real*, a1=imag*, a2=N
# ============================================================
normalize_by_n2:
    addi    sp, sp, -16; sd ra, 8(sp)
    mul     t6, a2, a2
    fcvt.s.w ft3, t6
    la      t0, const_1f; flw ft4, 0(t0)
    fdiv.s  ft3, ft4, ft3
    li      t0, 0
    mv      t4, a0; mv t5, a1
.Lnbn_loop:
    bge     t0, t6, .Lnbn_done
    slli    t1, t0, 2
    add     t2, t4, t1; flw ft0, 0(t2)
    fmul.s  ft0, ft0, ft3; fsw ft0, 0(t2)
    add     t2, t5, t1; flw ft0, 0(t2)
    fmul.s  ft0, ft0, ft3; fsw ft0, 0(t2)
    addi    t0, t0, 1; j .Lnbn_loop
.Lnbn_done:
    ld      ra, 8(sp); addi sp, sp, 16; ret

# ============================================================
# fftshift_2d — swap quadrants (DC to center for even N)
# in: a0=real*, a1=imag*, a2=N
# Two separate passes:
#   Pass 1: swap Q0[i][j]   <-> Q3[i+N/2][j+N/2]  (top-left  <-> bottom-right)
#   Pass 2: swap Q1[i][j+N/2] <-> Q2[i+N/2][j]    (top-right <-> bottom-left)
# ============================================================
fftshift_live:
    addi    sp, sp, -48
    sd      ra,40(sp); sd s0,32(sp); sd s1,24(sp)
    sd      s2,16(sp); sd s3,8(sp)
    mv      s0,a0; mv s1,a1; mv s2,a2
    srli    s3, s2, 1          # s3 = N/2

    # --- Pass 1: Q0 <-> Q3 (top-left <-> bottom-right) ---
    li      t6, 0
.Lfsl_p1_iloop:
    bge     t6, s3, .Lfsl_p1_done
    li      t5, 0
.Lfsl_p1_jloop:
    bge     t5, s3, .Lfsl_p1_jnx
    # offset of [i][j]
    mul     t0,t6,s2; add t0,t0,t5; slli t0,t0,2
    # offset of [i+N/2][j+N/2]
    add     t1,t6,s3; mul t1,t1,s2; add t2,t5,s3; add t1,t1,t2; slli t1,t1,2
    # swap real
    add     t2,s0,t0; flw ft0,0(t2)
    add     t3,s0,t1; flw ft1,0(t3)
    fsw     ft1,0(t2); fsw ft0,0(t3)
    # swap imag
    add     t2,s1,t0; flw ft0,0(t2)
    add     t3,s1,t1; flw ft1,0(t3)
    fsw     ft1,0(t2); fsw ft0,0(t3)
    addi    t5,t5,1; j .Lfsl_p1_jloop
.Lfsl_p1_jnx:
    addi    t6,t6,1; j .Lfsl_p1_iloop
.Lfsl_p1_done:

    # --- Pass 2: Q1 <-> Q2 (top-right <-> bottom-left) ---
    li      t6, 0
.Lfsl_p2_iloop:
    bge     t6, s3, .Lfsl_done
    li      t5, 0
.Lfsl_p2_jloop:
    bge     t5, s3, .Lfsl_p2_jnx
    # offset of [i][j+N/2]
    mul     t0,t6,s2; add t2,t5,s3; add t0,t0,t2; slli t0,t0,2
    # offset of [i+N/2][j]
    add     t1,t6,s3; mul t1,t1,s2; add t1,t1,t5; slli t1,t1,2
    # swap real
    add     t2,s0,t0; flw ft0,0(t2)
    add     t3,s0,t1; flw ft1,0(t3)
    fsw     ft1,0(t2); fsw ft0,0(t3)
    # swap imag
    add     t2,s1,t0; flw ft0,0(t2)
    add     t3,s1,t1; flw ft1,0(t3)
    fsw     ft1,0(t2); fsw ft0,0(t3)
    addi    t5,t5,1; j .Lfsl_p2_jloop
.Lfsl_p2_jnx:
    addi    t6,t6,1; j .Lfsl_p2_iloop
.Lfsl_done:
    ld      s3,8(sp); ld s2,16(sp); ld s1,24(sp)
    ld      s0,32(sp); ld ra,40(sp)
    addi    sp, sp, 48; ret

# ============================================================
# write_chunked_raw
# Write count*4 bytes from buf to fd in chunks
# in: a0=fd, a1=buf*, a2=count (floats)
# ============================================================
write_chunked_raw:
    addi sp,sp,-32
    sd ra,24(sp); sd s0,16(sp); sd s1,8(sp)
    mv s0,a0; mv s1,a1
    slli t5,a2,2     # total bytes = count * 4
    li t4,0
.Lwcr_loop:
    blez t5,.Lwcr_done
    li t3,65536; bge t5,t3,.Lwcr_chunk; mv t3,t5
.Lwcr_chunk:
    mv a0,s0; mv a1,s1; mv a2,t3; li a7,64; ecall
    blez a0,.Lwcr_done
    add t4,t4,a0; add s1,s1,a0; sub t5,t5,a0; j .Lwcr_loop
.Lwcr_done:
    ld s1,8(sp); ld s0,16(sp); ld ra,24(sp)
    addi sp,sp,32; ret

# ============================================================
# read_chunked_raw
# Read exactly nbytes from fd into buf
# in: a0=fd, a1=buf*, a2=nbytes
# ============================================================
read_chunked_raw:
    addi sp,sp,-32
    sd ra,24(sp); sd s0,16(sp); sd s1,8(sp)
    mv s0,a0; mv s1,a1; mv t5,a2
.Lrcr_loop:
    blez t5,.Lrcr_done
    li t3,65536; bge t5,t3,.Lrcr_chunk; mv t3,t5
.Lrcr_chunk:
    mv a0,s0; mv a1,s1; mv a2,t3; li a7,63; ecall
    blez a0,.Lrcr_done
    add s1,s1,a0; sub t5,t5,a0; j .Lrcr_loop
.Lrcr_done:
    ld s1,8(sp); ld s0,16(sp); ld ra,24(sp)
    addi sp,sp,32; ret

# ============================================================
# zero_floats_vec — vectorized zero fill
# in: a0=dst*, a1=count
# ============================================================
zero_floats_vec:
    li t6,0
    vsetvli t0,a1,e32,m1,ta,ma
    vmv.v.i v0,0
    li t6,0
.Lzfv_loop:
    sub t1,a1,t6; blez t1,.Lzfv_done
    vsetvli t2,t1,e32,m1,ta,ma
    slli t3,t6,2; add t4,a0,t3
    vse32.v v0,(t4)
    add t6,t6,t2; j .Lzfv_loop
.Lzfv_done:
    ret

# ============================================================
# print_str — write string to stdout
# in: a0=str*
# ============================================================
print_str:
    mv t0,a0
.Lps_len:
    lbu t1,0(t0); beqz t1,.Lps_write; addi t0,t0,1; j .Lps_len
.Lps_write:
    sub a2,t0,a0
    mv a1,a0; li a0,1; li a7,64; ecall; ret

# ============================================================
# open_file
# in: a0=path*, a1=flags, a2=mode
# out: a0=fd
# ============================================================
open_file:
    mv a3,a2; mv a2,a1; mv a1,a0; li a0,-100; li a7,56; ecall; ret

# ============================================================
# unlink_file — delete file
# in: a0=path*
# ============================================================
unlink_file:
    mv a1,a0; li a0,-100; li a7,35; ecall; ret

# ============================================================
# rename_file — atomic rename (for ready flag)
# in: a0=oldpath*, a1=newpath*
# ============================================================
rename_file:
    mv a2,a1; mv a1,a0; li a0,-100; li a7,38; ecall; ret

# ============================================================
# nanosleep — sleep nanoseconds
# in: a0=sec, a1=nsec
# ============================================================
nanosleep_ms:
    # sleep ~1ms
    addi sp,sp,-16
    sd zero,0(sp); li t0,1000000; sd t0,8(sp)
    mv a0,sp; li a1,0; li a7,101; ecall
    addi sp,sp,16; ret

# ============================================================
# process_frame
# Full pipeline: read frame -> FFT -> highpass -> magnitude -> write
# Uses precomputed twiddles in tw_real/tw_imag
# Returns: a0 = N processed (0 on error)
# ============================================================
process_frame:
    addi sp,sp,-64
    sd ra,56(sp); sd s0,48(sp); sd s1,40(sp)
    sd s2,32(sp); sd s3,24(sp); sd s4,16(sp)

    # Open input frame file
    la a0,str_frame_in; li a1,0; li a2,0   # O_RDONLY
    call open_file; mv s0,a0
    bltz s0,.Lpf_fail

    # Read N (int32)
    addi sp,sp,-8
    mv a0,s0; mv a1,sp; li a2,4; li a7,63; ecall
    lw s2,0(sp); addi sp,sp,8   # s2 = N

    # Read N*N floats into work_real
    mul s3,s2,s2   # s3 = N*N
    slli t0,s3,2   # bytes
    mv a0,s0
    la a1,work_real
    mv a2,t0
    call read_chunked_raw

    # Close input
    mv a0,s0; li a7,57; ecall

    # Zero work_imag (vectorized)
    la a0,work_imag; mv a1,s3
    call zero_floats_vec

    # Check if twiddles need regeneration (N changed)
    la t0,current_N; lw t1,0(t0)
    beq t1,s2,.Lpf_twiddles_ok
    # Generate twiddles for new N
    la a0,tw_real; la a1,tw_imag; mv a2,s2
    call vec_generate_twiddle_factors

    mv a0, s2
    call precompute_coords_vec

    la t0,current_N; sw s2,0(t0)
.Lpf_twiddles_ok:

    # === FORWARD FFT: ROW-WISE ===
    la a0,work_real; la a1,work_imag
    la a2,tw_real;   la a3,tw_imag; mv a4,s2
    call fft_rows_fast

    # === COLUMN FFT via TRANSPOSE ===
    # Transpose work -> trans
    la a0,work_real; la a1,work_imag
    la a2,trans_real; la a3,trans_imag; mv a4,s2
    call transpose_NxN

    # Row FFTs on transposed data (= column FFTs on original)
    la a0,trans_real; la a1,trans_imag
    la a2,tw_real;    la a3,tw_imag; mv a4,s2
    call fft_rows_fast

    # Transpose back: trans -> work
    la a0,trans_real; la a1,trans_imag
    la a2,work_real;  la a3,work_imag; mv a4,s2
    call transpose_NxN

    # === FFTSHIFT (move DC to center before highpass) ===
    la a0,work_real; la a1,work_imag; mv a2,s2
    call fftshift_live

    # === GAUSSIAN HIGH-PASS (center-based, after fftshift) ===
    la a0,work_real; la a1,work_imag; mv a2,s2
    call apply_butterworth_highpass

    # === IFFTSHIFT (move DC back to corner before IFFT) ===
    la a0,work_real; la a1,work_imag; mv a2,s2
    call fftshift_live

    # === GENERATE INVERSE TWIDDLES ===
    # Reuse tw_real/tw_imag: generate forward then negate imag
    la a0,tw_real; la a1,tw_imag; mv a2,s2
    call vec_generate_twiddle_factors
    la a0,tw_imag; srli a1,s2,1
    call negate_array

    # === IFFT ROWS ===
    la a0,work_real; la a1,work_imag
    la a2,tw_real;   la a3,tw_imag; mv a4,s2
    call fft_rows_fast

    # === IFFT COLS via TRANSPOSE ===
    la a0,work_real; la a1,work_imag
    la a2,trans_real; la a3,trans_imag; mv a4,s2
    call transpose_NxN
    la a0,trans_real; la a1,trans_imag
    la a2,tw_real;    la a3,tw_imag; mv a4,s2
    call fft_rows_fast
    la a0,trans_real; la a1,trans_imag
    la a2,work_real;  la a3,work_imag; mv a4,s2
    call transpose_NxN

    # === NORMALIZE BY 1/N^2 ===
    la a0,work_real; la a1,work_imag; mv a2,s2
    call normalize_by_n2

    # === RESTORE FORWARD TWIDDLES FOR NEXT FRAME ===
    la a0,tw_imag; srli a1,s2,1
    call negate_array  # Negating the inverse twiddles turns them back to forward twiddles

    # === SPATIAL MAGNITUDE (no log for live feed) ===
    la a0,work_real; la a1,work_imag
    la a2,edge_mag; mv a3,s3
    call compute_magnitude_vec

    # === WRITE RESULT ===
    # Open output file
    la a0,str_edges_out; li a1,0x241; li a2,0644
    call open_file; mv s4,a0
    bltz s4,.Lpf_write_fail

    # Write N (int32)
    addi sp,sp,-8; sw s2,0(sp)
    mv a0,s4; mv a1,sp; li a2,4; li a7,64; ecall
    addi sp,sp,8

    # Write edge_mag floats
    mv a0,s4; la a1,edge_mag; mv a2,s3
    call write_chunked_raw

    mv a0,s4; li a7,57; ecall   # close

    # Atomic ready flag: write to tmp then rename
    la a0,str_ready_tmp; li a1,0x241; li a2,0644
    call open_file; mv t0,a0
    bgez t0,.Lpf_flag_ok
.Lpf_flag_ok:
    mv a0,t0; li a7,57; ecall  # close tmp
    la a0,str_ready_tmp; la a1,str_ready_flag
    call rename_file            # atomic rename

    mv a0,s2   # return N
    ld s4,16(sp); ld s3,24(sp); ld s2,32(sp)
    ld s1,40(sp); ld s0,48(sp); ld ra,56(sp)
    addi sp,sp,64; ret

.Lpf_write_fail:
.Lpf_fail:
    li a0,0
    ld s4,16(sp); ld s3,24(sp); ld s2,32(sp)
    ld s1,40(sp); ld s0,48(sp); ld ra,56(sp)
    addi sp,sp,64; ret

# ============================================================
# main — server loop
# Continuously polls for /dev/shm/fft_frame.bin
# When found: processes it, deletes it, writes result
# ============================================================
main:
    addi sp,sp,-32
    sd ra,24(sp); sd s0,16(sp); sd s1,8(sp)

    # Print startup message
    la a0,str_startup; call print_str

    # Initialise current_N to 0 (force twiddle gen on first frame)
    la t0,current_N; sw zero,0(t0)

    # Delete any stale files from previous runs
    la a0,str_frame_in;   call unlink_file
    la a0,str_edges_out;  call unlink_file
    la a0,str_ready_flag; call unlink_file

.Lmain_loop:
    # Try to open frame input
    la a0,str_frame_in; li a1,0; li a2,0
    call open_file
    bltz a0,.Lmain_no_frame

    # Frame file exists — close (process_frame will reopen)
    mv t0,a0; mv a0,t0; li a7,57; ecall

    # Process the frame
    call process_frame

    # Delete processed input frame
    la a0,str_frame_in; call unlink_file

    j .Lmain_loop

.Lmain_no_frame:
    # No frame yet — sleep 1ms and retry
    call nanosleep_ms
    j .Lmain_loop

    # Never reached
    li a0,0
    ld s1,8(sp); ld s0,16(sp); ld ra,24(sp)
    addi sp,sp,32; ret
