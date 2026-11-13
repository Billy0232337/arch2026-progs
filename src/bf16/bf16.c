
#include "bf16.h"

#define BF16_SIGN_MASK 0x8000u
#define BF16_EXP_MASK 0x7F80u
#define BF16_FRAC_MASK 0x007Fu
#define BF16_INF 0x7F80u
#define BF16_NAN 0x7FC0u
#define BF16_BIAS 127

/* Convert float32 bits to BF16 with ties-to-even rounding. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exp = (f32bits >> 23) & 0xFFu;

    /* Preserve infinity and NaN patterns. */
    if (exp == 0xFFu)
        return (uint16_t) (f32bits >> 16);

    uint32_t bias = 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) ((f32bits + bias) >> 16);
}

/* Multiply BF16 values using integer arithmetic. */
uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign = (a ^ b) & BF16_SIGN_MASK;

    int exp_a = (a >> 7) & 0xFF;
    int exp_b = (b >> 7) & 0xFF;

    uint32_t frac_a = a & BF16_FRAC_MASK;
    uint32_t frac_b = b & BF16_FRAC_MASK;

    /* Process special operand a first. */
    if (exp_a == 0xFF) {
        if (frac_a != 0)
            return a;

        if ((b & 0x7FFFu) == 0)
            return BF16_NAN;

        return (uint16_t) (sign | BF16_INF);
    }

    /* Then process special operand b. */
    if (exp_b == 0xFF) {
        if (frac_b != 0)
            return b;

        if ((a & 0x7FFFu) == 0)
            return BF16_NAN;

        return (uint16_t) (sign | BF16_INF);
    }

    /* Zero multiplied by a finite number. */
    if ((a & 0x7FFFu) == 0 || (b & 0x7FFFu) == 0)
        return sign;

    uint32_t mant_a = frac_a;
    uint32_t mant_b = frac_b;

    /* Restore the implicit leading one for normal values. */
    if (exp_a != 0) {
        mant_a |= 0x80u;
    } else {
        exp_a = 1;
        while (mant_a < 0x80u) {
            mant_a <<= 1;
            exp_a--;
        }
    }

    if (exp_b != 0) {
        mant_b |= 0x80u;
    } else {
        exp_b = 1;
        while (mant_b < 0x80u) {
            mant_b <<= 1;
            exp_b--;
        }
    }

    /* The significands are eight bits each. */
    uint32_t product = mant_a * mant_b;
    int exp = exp_a + exp_b - BF16_BIAS;

    /* Normalize the product and truncate extra bits. */
    uint32_t mant;
    if (product & 0x8000u) {
        mant = product >> 8;
        exp++;
    } else {
        mant = product >> 7;
    }

    /* Overflow becomes signed infinity. */
    if (exp >= 0xFF)
        return (uint16_t) (sign | BF16_INF);


    /* Underflow becomes a denormal or signed zero. */
    if (exp <= 0) {
        if (exp < -6)
            return sign;

        uint32_t fraction = mant & BF16_FRAC_MASK;
        fraction >>= (1 - exp);

        return (uint16_t) (sign | fraction);
    }


    return (uint16_t) (sign | ((uint32_t) exp << 7) | (mant & BF16_FRAC_MASK));
}

/* Compute BF16 square root using an integer binary search. */
uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exp = (a >> 7) & 0xFFu;
    uint32_t frac = a & BF16_FRAC_MASK;

    /* Preserve NaN. */
    if (exp == 0xFFu && frac != 0)
        return a;

    /* Positive infinity remains infinity. */
    if (a == BF16_INF)
        return a;

    /* Both positive and negative zero return positive zero. */
    if ((a & 0x7FFFu) == 0)
        return 0;

    /* Negative nonzero inputs have no real square root. */
    if (a & BF16_SIGN_MASK)
        return BF16_NAN;

    /* Denormal inputs return positive zero. */
    if (exp == 0)
        return 0;

    int e = (int) exp - BF16_BIAS;
    uint32_t m = 0x80u | frac;

    int new_exp;

    /* Make the unbiased exponent even. */
    if (e & 1) {
        m <<= 1;
        new_exp = ((e - 1) >> 1) + BF16_BIAS;
    } else {
        new_exp = (e >> 1) + BF16_BIAS;
    }

    /* Search for the largest integer sqrt candidate. */
    uint32_t low = 90;
    uint32_t high = 256;
    uint32_t result = 128;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) >> 7;

        if (sq <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    if (result >= 256) {
        result >>= 1;
        new_exp++;
    }

    if (new_exp >= 0xFF)
        return BF16_INF;

    if (new_exp <= 0)
        return 0;

    return (uint16_t) (((uint32_t) new_exp << 7) | (result & BF16_FRAC_MASK));
}
