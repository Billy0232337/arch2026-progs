
#include "fixed.h"

/* Bitwise addition with carry propagation. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;

    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++*n;
    }

    return a;
}

/* Unsigned subtraction modulo 2^32. */
uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* Overflow-free floor average. */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/* Q11.20 multiplication without hardware multiply. */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;

    uint32_t lo = 0;
    uint32_t hi = 0;

    uint32_t add_lo = ua;
    uint32_t add_hi = 0;
    uint32_t multiplier = ub;

    /* Build the unsigned 64-bit product. */
    while (multiplier != 0) {
        if ((multiplier & 1u) != 0) {
            uint32_t old_lo = lo;

            lo += add_lo;
            hi += add_hi + (lo < old_lo);
        }

        add_hi = (add_hi << 1) | (add_lo >> 31);
        add_lo <<= 1;
        multiplier >>= 1;
    }

    /* Convert unsigned product to signed product. */
    if (a < 0)
        hi -= ub;

    if (b < 0)
        hi -= ua;

    /* Add rounding bias: 2^(Q - 1). */
    uint32_t old_lo = lo;
    lo += UINT32_C(1) << (Q - 1);
    hi += (lo < old_lo);

    /* Extract bits corresponding to product >> Q. */
    uint32_t result = (hi << (32 - Q)) | (lo >> Q);

    return (int32_t) result;
}
