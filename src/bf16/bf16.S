
# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)  a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b) a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)            a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, floating point,
# or compressed instructions.
# Tests: tests/tbf16.c.

    .text

    # --------------------------------------------------
    # bf16_from_f32: round to nearest, ties to even
    # --------------------------------------------------

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2

bf16_from_f32_asm:
    # Extract exponent.
    srli    t0, a0, 23
    andi    t0, t0, 255

    # Infinity and NaN: preserve upper 16 bits.
    addi    t1, zero, 255
    beq     t0, t1, f32_special

    # bias = 0x7FFF + bit16
    #0x8後面會自動補0變為0x00008000再-1
    lui     t1, 0x8
    addi    t1, t1, -1
    #nearest to even判斷邏輯
    srli    t2, a0, 16
    andi    t2, t2, 1
    add     t1, t1, t2

    # Apply rounding and keep upper 16 bits.
    add     a0, a0, t1

f32_special:
    srli    a0, a0, 16
    jalr    zero, 0(ra)

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    # --------------------------------------------------
    # bf16_mul: signed BF16 multiplication
    #
    # t0 = result sign
    # t1 = exponent a
    # t2 = exponent b
    # t3 = mantissa a
    # t4 = mantissa b
    # a2 = product
    # a3 = multiplier
    # a4 = shifted multiplicand
    # a5 = result exponent
    # t5, t6 = temporary registers
    # --------------------------------------------------

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2

bf16_mul_asm:
    # Compute the sign.
    xor     t0, a0, a1
    lui     t5, 0x8
    and     t0, t0, t5

    # Extract exponents.
    srli    t1, a0, 7
    andi    t1, t1, 255
    srli    t2, a1, 7
    andi    t2, t2, 255

    # Extract fractions.
    andi    t3, a0, 127
    andi    t4, a1, 127

    # Check operand a before operand b.
    addi    t5, zero, 255
    beq     t1, t5, mul_a_special
    beq     t2, t5, mul_b_special

    # Check whether either operand is zero.
    slli    t5, a0, 17
    beq     t5, zero, mul_zero
    slli    t5, a1, 17
    beq     t5, zero, mul_zero

    # Normalize operand a.
    bne     t1, zero, mul_a_normal
    addi    t1, zero, 1

mul_a_denorm:
    addi    t5, zero, 128
    bgeu    t3, t5, mul_a_ready
    slli    t3, t3, 1
    addi    t1, t1, -1
    jal     zero, mul_a_denorm

mul_a_normal:
    ori     t3, t3, 128

mul_a_ready:
    # Normalize operand b.
    bne     t2, zero, mul_b_normal
    addi    t2, zero, 1

mul_b_denorm:
    addi    t5, zero, 128
    bgeu    t4, t5, mul_b_ready
    slli    t4, t4, 1
    addi    t2, t2, -1
    jal     zero, mul_b_denorm

mul_b_normal:
    ori     t4, t4, 128

mul_b_ready:
    # Software 8-bit by 8-bit multiplication.
    addi    a2, zero, 0
    addi    a3, t4, 0
    addi    a4, t3, 0

mul_loop:
    andi    t5, a3, 1
    beq     t5, zero, mul_skip_add
    add     a2, a2, a4

mul_skip_add:
    slli    a4, a4, 1
    srli    a3, a3, 1
    bne     a3, zero, mul_loop

    # exp = exp_a + exp_b - 127
    add     a5, t1, t2
    addi    a5, a5, -127

    # Normalize the product.
    lui     t5, 0x8
    and     t6, a2, t5
    beq     t6, zero, mul_product_low

    srli    a2, a2, 8
    addi    a5, a5, 1
    jal     zero, mul_pack

mul_product_low:
    srli    a2, a2, 7

mul_pack:
    # Overflow: result becomes infinity.
    addi    t5, zero, 255
    bge     a5, t5, mul_inf

    # Underflow: handle the fraction separately.
    bge     zero, a5, mul_underflow

    # Normal result.
    slli    a5, a5, 7
    andi    a2, a2, 127
    or      a0, t0, a5
    or      a0, a0, a2
    jalr    zero, 0(ra)

mul_underflow:
    addi    t5, zero, -6
    blt     a5, t5, mul_zero

    # The assignment shifts only the fraction.
    andi    a2, a2, 127
    addi    t5, zero, 1
    sub     t5, t5, a5
    srl     a2, a2, t5

    or      a0, t0, a2
    jalr    zero, 0(ra)

    # Special operand a.
mul_a_special:
    # NaN a is returned unchanged.
    bne     t3, zero, mul_return

    # Inf * zero gives quiet NaN.
    slli    t5, a1, 17
    beq     t5, zero, mul_nan

    jal     zero, mul_inf

    # Special operand b.
mul_b_special:
    # NaN b is returned unchanged.
    beq     t4, zero, mul_b_inf
    addi    a0, a1, 0
    jalr    zero, 0(ra)

mul_b_inf:
    slli    t5, a0, 17
    beq     t5, zero, mul_nan

mul_inf:
    # 0x7F80 with the product sign.
    lui     t5, 0x8
    addi    t5, t5, -128
    or      a0, t0, t5
    jalr    zero, 0(ra)

mul_nan:
    # Canonical quiet NaN: 0x7FC0.
    lui     a0, 0x8
    addi    a0, a0, -64
    jalr    zero, 0(ra)

mul_zero:
    addi    a0, t0, 0

mul_return:
    jalr    zero, 0(ra)

    .size   bf16_mul_asm, .-bf16_mul_asm

    # --------------------------------------------------
    # bf16_sqrt: integer binary-search square root
    #
    # t0 = original exponent
    # t1 = normalized mantissa
    # t3 = new exponent
    # t4 = search low
    # t5 = search high
    # t6 = best result
    # a1 = search midpoint
    # a2 = squared value
    # a3 = shifted multiplicand
    # a4 = multiplier
    # a5 = temporary register
    # --------------------------------------------------

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

bf16_sqrt_asm:
    # Extract exponent and fraction.
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127

    # Handle NaN and infinity.
    addi    t2, zero, 255
    bne     t0, t2, sqrt_check_zero

    # A NaN is returned unchanged.
    bne     t1, zero, sqrt_return

    # +Infinity is returned unchanged.
    lui     t2, 0x8
    addi    t2, t2, -128
    beq     a0, t2, sqrt_return

    # -Infinity becomes NaN.
    jal     zero, sqrt_nan

sqrt_check_zero:
    # Both +0 and -0 become +0.
    slli    t2, a0, 17
    beq     t2, zero, sqrt_zero

    # Negative nonzero values become NaN.
    srli    t2, a0, 15
    bne     t2, zero, sqrt_nan

    # Denormal values become zero.
    beq     t0, zero, sqrt_zero

    # Restore the implicit leading one.
    ori     t1, t1, 128

    # e = exp - 127
    addi    t3, t0, -127

    # Make the exponent even.
    andi    t2, t3, 1
    beq     t2, zero, sqrt_exp_ready

    slli    t1, t1, 1
    addi    t3, t3, -1

sqrt_exp_ready:
    # new_exp = e / 2 + 127
    srai    t3, t3, 1
    addi    t3, t3, 127

    # Initialize binary search.
    addi    t4, zero, 90
    addi    t5, zero, 256
    addi    t6, zero, 128

sqrt_search:
    bltu    t5, t4, sqrt_finish

    # mid = (low + high) >> 1
    add     a1, t4, t5
    srli    a1, a1, 1

    # Compute mid * mid using shift-and-add.
    addi    a2, zero, 0
    addi    a3, a1, 0
    addi    a4, a1, 0

sqrt_square_loop:
    andi    a5, a4, 1
    beq     a5, zero, sqrt_skip_add
    add     a2, a2, a3

sqrt_skip_add:
    slli    a3, a3, 1
    srli    a4, a4, 1
    bne     a4, zero, sqrt_square_loop

    # sq = (mid * mid) >> 7
    srli    a2, a2, 7

    # If sq > mantissa, move the upper bound.
    bltu    t1, a2, sqrt_too_large

    # Candidate is valid.
    addi    t6, a1, 0
    addi    t4, a1, 1
    jal     zero, sqrt_search

sqrt_too_large:
    addi    t5, a1, -1
    jal     zero, sqrt_search

sqrt_finish:
    # Normalize result to [128, 256).
    addi    a5, zero, 256
    bltu    t6, a5, sqrt_pack

    srli    t6, t6, 1
    addi    t3, t3, 1

sqrt_pack:
    # Exponent overflow.
    addi    a5, zero, 255
    bge     t3, a5, sqrt_inf

    # Exponent underflow.
    bge     zero, t3, sqrt_zero

    slli    t3, t3, 7
    andi    t6, t6, 127
    or      a0, t3, t6
    jalr    zero, 0(ra)

sqrt_inf:
    lui     a0, 0x8
    addi    a0, a0, -128
    jalr    zero, 0(ra)

sqrt_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    jalr    zero, 0(ra)

sqrt_zero:
    addi    a0, zero, 0

sqrt_return:
    jalr    zero, 0(ra)

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
