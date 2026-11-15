# Assignment 2 Rubik solver, RV32I + Zicsr, no M/C/F/D instructions.
# V2: current-frame pointer and threshold-aware heuristic lookup.
# Lookup tables are declared within this Assembly object via a textual include.
# The C header is deliberately left unchanged.
# ABI: a0=state, a1=out, a2=cap; return a0=length/-1/-2.
# Callee saved registers s0-s11 and ra are restored.

    .section .bss
    .balign 4
rubik_asm_dfs_stack:
    .space 144          # 12 frames * 12 bytes
rubik_asm_solution:
    .space 11

    .section .text
    .balign 4
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
rubik_solve_asm:
    addi sp, sp, -96
    sw ra, 48(sp)
    sw s0, 0(sp)
    sw s1, 4(sp)
    sw s2, 8(sp)
    sw s3, 12(sp)
    sw s4, 16(sp)
    sw s5, 20(sp)
    sw s6, 24(sp)
    sw s7, 28(sp)
    sw s8, 32(sp)
    sw s9, 36(sp)
    sw s10, 40(sp)
    sw s11, 44(sp)
    sw a2, 52(sp)       # original cap
    mv s11, a1          # output pointer
    beq a0, zero, rubik_invalid

    # The five tables are owned by this Assembly object.
    la s0, asm_permutation
    la s1, asm_orientation
    la s2, asm_perm_meta
    la s3, asm_pdb_row_offset
    la s4, asm_pdb3_packed
    la s5, rubik_asm_dfs_stack
    la s6, rubik_asm_solution

    # Scratch buffers for parsing (permutation + orientation).
    addi a1, sp, 64
    addi a2, sp, 72
    jal ra, rubik_parse_and_rank
    beq a2, zero, rubik_invalid
    mv s9, a0           # root permutation
    mv s10, a1          # root orientation

    mv a0, s9
    mv a1, s10
    jal ra, rubik_heuristic
    mv s7, a0           # first bound = h(root)

rubik_ida_bound_start:
    li t0, 11
    bltu t0, s7, rubik_search_failed
    # The root heuristic was already computed before the IDA* loop.
    or t0, s9, s10
    beq t0, zero, rubik_solution_found
    beq s7, zero, rubik_ida_next_bound

    # Explicit DFS frame: p.h,o.h,next_p.h,next_o.h,previous_face.b,face.b,turn.b,pad.
    # Reinitialize root pointer for each increasing IDA* bound.
    la s5, rubik_asm_dfs_stack
    li s8, 0
    sh s9, 0(s5)
    sh s10, 2(s5)
    sh s9, 4(s5)
    sh s10, 6(s5)
    li t0, -1
    sb t0, 8(s5)
    sb zero, 9(s5)
    sb zero, 10(s5)

rubik_search_loop:
    # V2: s5 is the current DFS frame, not the stack base.
    # Push/pop update it by exactly one 12-byte frame.
    mv t0, s5

    lbu t1, 9(t0)
    li t2, 3
    bgeu t1, t2, rubik_frame_exhausted
    lbu t2, 8(t0)
    beq t1, t2, rubik_advance_face
    lbu t3, 10(t0)
    li t2, 3
    bgeu t3, t2, rubik_advance_face

    mv a5, t1          # save face across heuristic
    mv a6, t3          # save old turn across heuristic
    lhu t4, 4(t0)
    lhu t5, 6(t0)

    beq t1, zero, rubik_trans_face0
    li t2, 1
    beq t1, t2, rubik_trans_face1
    li t6, 20160
    li t2, 2916
    j rubik_trans_base_ready
rubik_trans_face1:
    li t6, 10080
    li t2, 1458
    j rubik_trans_base_ready
rubik_trans_face0:
    li t6, 0
    li t2, 0
rubik_trans_base_ready:
    add t6, s0, t6
    slli a4, t4, 1
    add a4, t6, a4
    lhu a2, 0(a4)
    add t2, s1, t2
    slli a4, t5, 1
    add a4, t2, a4
    lhu a3, 0(a4)

    sh a2, 4(t0)
    sh a3, 6(t0)
    addi t3, t3, 1
    sb t3, 10(t0)
    addi a4, s8, 1
    mv a0, a2
    mv a1, a3
    # The partial permutation distance can reject a child without
    # loading the orientation/PDB row. a7 = remaining move budget.
    # Preserve a2: it still holds the child permutation rank.
    sub a7, s7, a4
    jal ra, rubik_heuristic_limited
    add t1, a4, a0
    bltu s7, t1, rubik_search_loop

    slli t1, a5, 1
    add t1, t1, a5
    add t1, t1, a6
    add t2, s6, s8
    sb t1, 0(t2)
    or t1, a2, a3
    beq t1, zero, rubik_solution_found
    beq a4, s7, rubik_search_loop

    mv s8, a4
    addi s5, s5, 12
    mv t0, s5
    sh a2, 0(t0)
    sh a3, 2(t0)
    sh a2, 4(t0)
    sh a3, 6(t0)
    sb a5, 8(t0)
    sb zero, 9(t0)
    sb zero, 10(t0)
    j rubik_search_loop

rubik_advance_face:
    addi t1, t1, 1
    sb t1, 9(t0)
    sb zero, 10(t0)
    lhu t2, 0(t0)
    lhu t3, 2(t0)
    sh t2, 4(t0)
    sh t3, 6(t0)
    j rubik_search_loop

rubik_frame_exhausted:
    beq s8, zero, rubik_ida_next_bound
    addi s8, s8, -1
    addi s5, s5, -12
    j rubik_search_loop

rubik_ida_next_bound:
    addi s7, s7, 1
    j rubik_ida_bound_start

rubik_solution_found:
    # Count bytes of formatted solution, including terminal NUL.
    li t0, 1             # NUL
    li t1, 0             # move index
rubik_size_loop:
    bgeu t1, s7, rubik_size_done
    addi t0, t0, 1      # face letter
    beq t1, zero, rubik_size_no_space
    addi t0, t0, 1      # separator
rubik_size_no_space:
    add t2, s6, t1
    lbu t3, 0(t2)
    li t4, 1
    beq t3, t4, rubik_size_extra
    li t4, 2
    beq t3, t4, rubik_size_extra
    li t4, 4
    beq t3, t4, rubik_size_extra
    li t4, 5
    beq t3, t4, rubik_size_extra
    li t4, 7
    beq t3, t4, rubik_size_extra
    li t4, 8
    bne t3, t4, rubik_size_next
rubik_size_extra:
    addi t0, t0, 1
rubik_size_next:
    addi t1, t1, 1
    j rubik_size_loop
rubik_size_done:
    lw t1, 52(sp)
    bltu t1, t0, rubik_buffer_small

    # Emit move names directly: no printf, no ecall.
    mv t0, s11
    li t1, 0
rubik_output_loop:
    bgeu t1, s7, rubik_output_done
    beq t1, zero, rubik_output_no_space
    li t2, 32
    sb t2, 0(t0)
    addi t0, t0, 1
rubik_output_no_space:
    add t2, s6, t1
    lbu t3, 0(t2)        # move code 0..8
    li t4, 3
    bltu t3, t4, rubik_output_R
    li t4, 6
    bltu t3, t4, rubik_output_B
    li t4, 68           # D
    addi t3, t3, -6
    j rubik_output_face
rubik_output_R:
    li t4, 82           # R
    j rubik_output_face
rubik_output_B:
    li t4, 66           # B
    addi t3, t3, -3
rubik_output_face:
    sb t4, 0(t0)
    addi t0, t0, 1
    beq t3, zero, rubik_output_next
    li t4, 1
    beq t3, t4, rubik_output_two
    li t4, 39           # apostrophe
    j rubik_output_suffix
rubik_output_two:
    li t4, 50           # '2'
rubik_output_suffix:
    sb t4, 0(t0)
    addi t0, t0, 1
rubik_output_next:
    addi t1, t1, 1
    j rubik_output_loop
rubik_output_done:
    sb zero, 0(t0)
    mv a0, s7
    j rubik_restore

rubik_buffer_small:
    lw t0, 52(sp)
    beq t0, zero, rubik_buffer_no_write
    sb zero, 0(s11)
rubik_buffer_no_write:
    li a0, -2
    j rubik_restore
rubik_search_failed:
    # Should not happen for valid states, but match C's fallback.
    j rubik_buffer_small
rubik_invalid:
    li a0, -1

rubik_restore:
    lw ra, 48(sp)
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    lw s3, 12(sp)
    lw s4, 16(sp)
    lw s5, 20(sp)
    lw s6, 24(sp)
    lw s7, 28(sp)
    lw s8, 32(sp)
    lw s9, 36(sp)
    lw s10, 40(sp)
    lw s11, 44(sp)
    addi sp, sp, 96
    ret
    .size rubik_solve_asm, .-rubik_solve_asm

# rubik_parse_and_rank(a0=input, a1=perm_buf, a2=orient_buf)
# Returns a0=permutation rank, a1=orientation rank, a2=1 on success.
# On failure, a2=0. Uses only RV32I shift/add/sub arithmetic.
rubik_parse_and_rank:
    mv a3, a0              # input base
    mv a4, a1              # permutation digit buffer
    mv a5, a2              # orientation digit buffer

    # Parse seven permutation digits, each in '1'..'7'.
    li t0, 0
rubik_parse_perm_loop:
    li t1, 7
    bgeu t0, t1, rubik_parse_orient_start
    add t2, a3, t0
    lbu t3, 0(t2)
    li t4, 49              # '1'
    bltu t3, t4, rubik_parse_fail
    li t5, 56              # '8', exclusive upper bound
    bgeu t3, t5, rubik_parse_fail
    addi t3, t3, -49
    add t2, a4, t0
    sb t3, 0(t2)
    addi t0, t0, 1
    j rubik_parse_perm_loop

rubik_parse_orient_start:
    li t0, 0
    li t6, 0               # sum modulo 3
rubik_parse_orient_loop:
    li t1, 7
    bgeu t0, t1, rubik_parse_shape_done
    addi t2, t0, 7
    add t2, a3, t2
    lbu t3, 0(t2)
    li t4, 49              # '1'
    bltu t3, t4, rubik_parse_fail
    li t5, 52              # '4', exclusive upper bound
    bgeu t3, t5, rubik_parse_fail
    addi t3, t3, -49
    add t2, a5, t0
    sb t3, 0(t2)

    add t6, t6, t3
    li t5, 3
    bltu t6, t5, rubik_orient_mod_ok
    addi t6, t6, -3
rubik_orient_mod_ok:
    addi t0, t0, 1
    j rubik_parse_orient_loop

rubik_parse_shape_done:
    # Exactly 14 characters are required.
    addi t2, a3, 14
    lbu t3, 0(t2)
    bne t3, zero, rubik_parse_fail
    bne t6, zero, rubik_parse_fail

    # Check that the seven permutation digits are all distinct.
    li t0, 0
rubik_perm_unique_outer:
    li t6, 7
    bgeu t0, t6, rubik_rank_perm_start
    add t1, a4, t0
    lbu t2, 0(t1)
    addi t3, t0, 1
rubik_perm_unique_inner:
    bgeu t3, t6, rubik_perm_unique_next
    add t4, a4, t3
    lbu t5, 0(t4)
    beq t2, t5, rubik_parse_fail
    addi t3, t3, 1
    j rubik_perm_unique_inner
rubik_perm_unique_next:
    addi t0, t0, 1
    j rubik_perm_unique_outer

    # Lehmer/factoradic permutation rank.
rubik_rank_perm_start:
    li a6, 0               # p rank accumulator
    li t0, 0               # i
rubik_rank_perm_outer:
    li t6, 7
    bgeu t0, t6, rubik_rank_orient_start
    add t4, a4, t0
    lbu t2, 0(t4)          # p[i]
    li t1, 0               # smaller
    addi t3, t0, 1         # j=i+1
rubik_rank_perm_inner:
    bgeu t3, t6, rubik_rank_perm_scale
    add t4, a4, t3
    lbu t5, 0(t4)
    bgeu t5, t2, rubik_rank_perm_no_inc
    addi t1, t1, 1
rubik_rank_perm_no_inc:
    addi t3, t3, 1
    j rubik_rank_perm_inner

rubik_rank_perm_scale:
    # a6 *= (7-i), with only shifts/add/sub.
    beq t0, zero, rubik_rank_mul7
    li t4, 1
    beq t0, t4, rubik_rank_mul6
    li t4, 2
    beq t0, t4, rubik_rank_mul5
    li t4, 3
    beq t0, t4, rubik_rank_mul4
    li t4, 4
    beq t0, t4, rubik_rank_mul3
    li t4, 5
    beq t0, t4, rubik_rank_mul2
    j rubik_rank_perm_add        # i=6, multiply by 1
rubik_rank_mul7:
    slli t4, a6, 3
    sub a6, t4, a6
    j rubik_rank_perm_add
rubik_rank_mul6:
    slli t4, a6, 2
    slli t5, a6, 1
    add a6, t4, t5
    j rubik_rank_perm_add
rubik_rank_mul5:
    slli t4, a6, 2
    add a6, t4, a6
    j rubik_rank_perm_add
rubik_rank_mul4:
    slli a6, a6, 2
    j rubik_rank_perm_add
rubik_rank_mul3:
    slli t4, a6, 1
    add a6, t4, a6
    j rubik_rank_perm_add
rubik_rank_mul2:
    slli a6, a6, 1
rubik_rank_perm_add:
    add a6, a6, t1
    addi t0, t0, 1
    j rubik_rank_perm_outer

    # Base-3 orientation rank uses the first six twists.
rubik_rank_orient_start:
    li t0, 0
    li t1, 0               # o rank accumulator
rubik_rank_orient_loop:
    li t2, 6
    bgeu t0, t2, rubik_parse_success
    slli t3, t1, 1
    add t1, t3, t1         # t1 *= 3
    add t4, a5, t0
    lbu t5, 0(t4)
    add t1, t1, t5
    addi t0, t0, 1
    j rubik_rank_orient_loop

rubik_parse_success:
    mv a0, a6
    mv a1, t1
    li a2, 1
    ret
rubik_parse_fail:
    li a2, 0
    ret

# rubik_heuristic(a0=p, a1=o) -> a0=max(h_perm, h_pdb)
rubik_heuristic:
    slli t0, a0, 1
    add t0, s2, t0
    lhu t2, 0(t0)
    andi t3, t2, 255
    srli t4, t2, 8

    slli t0, a1, 2
    add t0, s3, t0
    lw t5, 0(t0)
    srli t6, t3, 1
    add t5, t5, t6
    add t5, s4, t5
    lbu t5, 0(t5)

    andi t6, t3, 1
    slli t6, t6, 2
    srl t5, t5, t6
    andi t5, t5, 15

    bgeu t4, t5, rubik_heuristic_hp
    mv a0, t5
    ret
rubik_heuristic_hp:
    mv a0, t4
    ret

# rubik_heuristic_limited(a0=p, a1=o, a7=remaining moves)
# Returns exact max(h_perm,h_pdb) unless h_perm exceeds a7,
# in which case h_perm already proves the child should be pruned.
# This removes two table reads for common rejected children.
rubik_heuristic_limited:
    slli t0, a0, 1
    add t0, s2, t0
    lhu t2, 0(t0)
    srli t4, t2, 8
    bltu a7, t4, rubik_heuristic_limited_fast_reject
    andi t3, t2, 255
    slli t0, a1, 2
    add t0, s3, t0
    lw t5, 0(t0)
    srli t6, t3, 1
    add t5, t5, t6
    add t5, s4, t5
    lbu t5, 0(t5)
    andi t6, t3, 1
    slli t6, t6, 2
    srl t5, t5, t6
    andi t5, t5, 15
    bgeu t4, t5, rubik_heuristic_limited_fast_reject
    mv a0, t5
    ret
rubik_heuristic_limited_fast_reject:
    mv a0, t4
    ret



    # Include separate search data into the Assembly implementation object.
    .include "src/rubik/rubik_asm_tables.inc"
