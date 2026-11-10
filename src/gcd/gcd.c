
#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;

    if (b == 0)
        return a;

    uint32_t shift = 0;

    // Remove common factors of two.
    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        shift++;
    }

    // Make a odd.
    while ((a & 1u) == 0)
        a >>= 1;

    while (b != 0) {
        // Make b odd.
        while ((b & 1u) == 0)
            b >>= 1;

        // Keep a <= b.
        if (a > b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }

        b = b - a;
    }

    return a << shift;
}
