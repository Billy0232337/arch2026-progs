#include "rubik.h"

#include <stdint.h>

#include "rubik_search_tables.h"

#define CUBIES 7u
#define MAX_DEPTH 11u
#define FACES 3u

typedef struct {
    uint8_t p[CUBIES];
    uint8_t o[CUBIES];
} state_t;

static int parse_state(const char *input, state_t *state)
{
    uint32_t seen = 0u;
    unsigned orientation_sum = 0u;

    if (input == NULL)
        return 0;

    for (unsigned i = 0; i < RUBIK_STATE_LEN; ++i) {
        unsigned char c = (unsigned char) input[i];

        if (c == '\0')
            return 0;

        if (i < CUBIES) {
            if (c < '1' || c > '7')
                return 0;

            uint8_t value = (uint8_t) (c - '1');
            uint32_t bit = 1u << value;
            if ((seen & bit) != 0u)
                return 0;

            seen |= bit;
            state->p[i] = value;
        } else {
            if (c < '1' || c > '3')
                return 0;

            uint8_t value = (uint8_t) (c - '1');
            state->o[i - CUBIES] = value;
            orientation_sum += value;
        }
    }

    if (input[RUBIK_STATE_LEN] != '\0')
        return 0;

    while (orientation_sum >= 3u)
        orientation_sum -= 3u;

    return orientation_sum == 0u;
}

static void rank_coordinates(const state_t *state,
                             uint16_t *p_out,
                             uint16_t *o_out)
{
    uint32_t p = 0u;

    for (unsigned i = 0; i < CUBIES; ++i) {
        uint8_t smaller = 0u;
        for (unsigned j = i + 1u; j < CUBIES; ++j) {
            if (state->p[j] < state->p[i])
                ++smaller;
        }

        switch (CUBIES - i) {
        case 7u:
            p = (p << 3) - p;
            break;
        case 6u:
            p = (p << 2) + (p << 1);
            break;
        case 5u:
            p = (p << 2) + p;
            break;
        case 4u:
            p <<= 2;
            break;
        case 3u:
            p = (p << 1) + p;
            break;
        case 2u:
            p <<= 1;
            break;
        default:
            break;
        }
        p += smaller;
    }

    uint32_t o = 0u;
    for (unsigned i = 0; i < 6u; ++i)
        o = (o << 1) + o + state->o[i];

    *p_out = (uint16_t) p;
    *o_out = (uint16_t) o;
}


static uint8_t solution[MAX_DEPTH];
static uint32_t search_nodes;

static inline uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint16_t meta = perm_meta[p];
    uint8_t p3 = (uint8_t) meta;
    uint8_t hp = (uint8_t) (meta >> 8);

    uint32_t byte_index = pdb_row_offset[o] + (uint32_t) (p3 >> 1);
    uint8_t packed = pdb3_packed[byte_index];
    uint8_t shift = (uint8_t) ((p3 & 1u) << 2);
    uint8_t hpdb = (uint8_t) ((packed >> shift) & 0x0fu);

    return hp > hpdb ? hp : hpdb;
}

/*
 * Resume state for one active DFS level.
 *
 * The explicit stack index is the depth, so v2's depth byte is unnecessary.
 * The node is evaluated before it is pushed, so v2's entered byte is also
 * unnecessary.
 */
typedef struct {
    uint16_t p;
    uint16_t o;
    uint16_t next_p;
    uint16_t next_o;
    int8_t previous_face;
    uint8_t face;
    uint8_t turn;
} dfs_frame_t;

static inline void init_frame(dfs_frame_t *f,
                              uint16_t p,
                              uint16_t o,
                              int8_t previous_face)
{
    f->p = p;
    f->o = o;
    f->next_p = p;
    f->next_o = o;
    f->previous_face = previous_face;
    f->face = 0u;
    f->turn = 0u;
}

/*
 * Iterative IDA* depth-first pass for one bound.
 *
 * A generated child is counted and evaluated immediately.  Only children that
 * survive f=g+h pruning and can still expand are pushed onto the explicit
 * stack.  This removes the entered-state branch from every loop iteration.
 */
static int dfs_iterative(uint16_t root_p, uint16_t root_o, uint8_t bound)
{
    dfs_frame_t stack[MAX_DEPTH + 1u];
    uint8_t sp = 0u;

    ++search_nodes;
    if (heuristic(root_p, root_o) > bound)
        return 0;
    if (root_p == 0u && root_o == 0u)
        return 1;
    if (bound == 0u)
        return 0;

    init_frame(&stack[0], root_p, root_o, -1);

    for (;;) {
        dfs_frame_t *f = &stack[sp];

        while (f->face < FACES) {
            if ((int8_t) f->face == f->previous_face) {
                ++f->face;
                f->turn = 0u;
                f->next_p = f->p;
                f->next_o = f->o;
                continue;
            }

            if (f->turn < 3u) {
                uint8_t face = f->face;
                uint8_t turn = f->turn;

                /* Incremental quarter turns produce face, face^2, face^3. */
                f->next_p = permutation[face][f->next_p];
                f->next_o = orientation[face][f->next_o];
                ++f->turn;

                uint16_t child_p = f->next_p;
                uint16_t child_o = f->next_o;
                uint8_t child_depth = (uint8_t) (sp + 1u);

                ++search_nodes;
                uint8_t h = heuristic(child_p, child_o);
                if ((unsigned) child_depth + h > bound)
                    continue;

                solution[sp] = (uint8_t) ((face << 1) + face + turn);

                if (child_p == 0u && child_o == 0u)
                    return 1;

                if (child_depth == bound)
                    continue;

                ++sp;
                init_frame(&stack[sp], child_p, child_o, (int8_t) face);
                goto next_iteration;
            }

            ++f->face;
            f->turn = 0u;
            f->next_p = f->p;
            f->next_o = f->o;
        }

        if (sp == 0u)
            return 0;
        --sp;

    next_iteration:;
    }
}

static int solve(uint16_t p, uint16_t o, uint8_t *solution_length)
{
    uint8_t first_bound = heuristic(p, o);
    search_nodes = 0u;

    for (uint8_t bound = first_bound; bound <= MAX_DEPTH; ++bound) {
        if (dfs_iterative(p, o, bound)) {
            *solution_length = bound;
            return 1;
        }
    }
    return 0;
}



/* A completed search records one move index (0..8) at each depth. */
static const char *const move_names[9] = {"R",  "R2", "R'", "B", "B2",
                                          "B'", "D",  "D2", "D'"};

int rubik_solve(const char *state, char *out, size_t cap)
{
    state_t cube;
    uint16_t p, o;
    uint8_t length = 0u;

    /* Invalid input must not modify the caller's output buffer. */
    if (!parse_state(state, &cube))
        return -1;

    rank_coordinates(&cube, &p, &o);
    if (!solve(p, o, &length)) {
        /* All legal states in this 2x2x2 model are within 11 moves. */
        if (cap > 0u)
            out[0] = '\0';
        return -2;
    }

    /* Count spaces, move letters, and optional suffixes before writing. */
    size_t needed = 1u; /* NUL */
    for (unsigned i = 0; i < length; ++i) {
        unsigned move = solution[i];
        needed += 1u; /* face letter */
        if (move == 1u || move == 2u || move == 4u || move == 5u ||
            move == 7u || move == 8u)
            ++needed; /* '2' or apostrophe */
        if (i != 0u)
            ++needed; /* separator */
    }

    if (cap < needed) {
        if (cap > 0u)
            out[0] = '\0';
        return -2;
    }

    size_t pos = 0u;
    for (unsigned i = 0; i < length; ++i) {
        const char *name = move_names[solution[i]];
        if (i != 0u)
            out[pos++] = ' ';
        out[pos++] = name[0];
        if (name[1] != '\0')
            out[pos++] = name[1];
    }
    out[pos] = '\0';
    return (int) length;
}
