
    .text
    .align 2
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function

gcd_u32_asm:
    # a0 = a
    # a1 = b
    # a2 = common shift
    # t0 = temporary value

    # Handle zero inputs.
    beq     a0, zero, return_b
    beq     a1, zero, done

    addi    a2, zero, 0

# Remove common factors of two.
common_twos:
    or      t0, a0, a1
    andi    t0, t0, 1
    bne     t0, zero, a_check

    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    a2, a2, 1
    jal     zero, common_twos

# Make a odd.
a_shift:
    srli    a0, a0, 1

a_check:
    andi    t0, a0, 1
    beq     t0, zero, a_shift

    # First entry: check b before shifting.
    jal     zero, b_check

# Remove factors of two from b.
b_shift:
    srli    a1, a1, 1

b_check:
    andi    t0, a1, 1
    beq     t0, zero, b_shift

# Both a and b are odd.
compare:
    bltu    a1, a0, swap_subtract

    # b >= a
    sub     a1, a1, a0
    beq     a1, zero, restore_twos

    # The difference is nonzero and even.
    jal     zero, b_shift

# b < a
swap_subtract:
    sub     t0, a0, a1
    addi    a0, a1, 0
    addi    a1, t0, 0

    # The new b is nonzero and even.
    jal     zero, b_shift

restore_twos:
    sll     a0, a0, a2

done:
    jalr    zero, 0(ra)

return_b:
    addi    a0, a1, 0
    jalr    zero, 0(ra)

    .size gcd_u32_asm, .-gcd_u32_asm

