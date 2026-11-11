
# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair.
# Tests: tests/tfixed.c.

    .text

    # --------------------------------------------------
    # op1: bitwise addition with carry propagation
    # --------------------------------------------------

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi    t0, zero, 0
    beq     a1, zero, op1_done

op1_loop:
    and     t1, a0, a1
    slli    t1, t1, 1
    xor     a0, a0, a1
    addi    a1, t1, 0
    addi    t0, t0, 1
    bne     a1, zero, op1_loop

op1_done:
    sw      t0, 0(a2)
    jalr    zero, 0(ra)

    .size   op1_asm, .-op1_asm

    # --------------------------------------------------
    # op2: unsigned subtraction
    # --------------------------------------------------

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    jalr    zero, 0(ra)

    .size   op2_asm, .-op2_asm

    # --------------------------------------------------
    # op3: overflow-free floor average
    # --------------------------------------------------

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     t1, a0, a1
    srli    t1, t1, 1
    add     a0, t0, t1
    jalr    zero, 0(ra)

    .size   op3_asm, .-op3_asm

    # --------------------------------------------------
    # q_mul: signed Q11.20 multiplication
    #
    # a0 = signed a
    # a1 = signed b
    # t0 = product low word
    # t1 = product high word
    # t2 = shifted multiplicand low word
    # t3 = shifted multiplicand high word
    # t4 = unsigned multiplier
    # t5, t6 = temporary registers
    # --------------------------------------------------

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    addi    t0, zero, 0
    addi    t1, zero, 0

    addi    t2, a0, 0
    addi    t3, zero, 0
    addi    t4, a1, 0

    # Skip multiplication when b is zero.
    beq     t4, zero, qmul_signed

qmul_loop:
    andi    t5, t4, 1
    beq     t5, zero, qmul_skip_add

    # Add the low word.
    add     t0, t0, t2

    # Carry occurs when new low word < addend.
    sltu    t6, t0, t2

    # Add high word and carry.
    add     t1, t1, t3
    add     t1, t1, t6

qmul_skip_add:
    # Shift the 64-bit multiplicand left.
    srli    t5, t2, 31
    slli    t3, t3, 1
    or      t3, t3, t5
    slli    t2, t2, 1

    # Shift the multiplier right and repeat if nonzero.
    srli    t4, t4, 1
    bne     t4, zero, qmul_loop

qmul_signed:
    # Correct the high word for signed a.
    bge     a0, zero, qmul_check_b
    sub     t1, t1, a1

qmul_check_b:
    # Correct the high word for signed b.
    bge     a1, zero, qmul_round
    sub     t1, t1, a0

qmul_round:
    # Rounding bias: 2^19.
    lui     t5, 0x80

    add     t6, t0, t5
    sltu    t5, t6, t0
    add     t1, t1, t5

    # Extract bits 51..20.
    srli    t6, t6, 20
    slli    t1, t1, 12
    or      a0, t1, t6

    jalr    zero, 0(ra)

    .size   q_mul_asm, .-q_mul_asm

