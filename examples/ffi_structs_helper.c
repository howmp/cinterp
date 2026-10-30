typedef struct { long a, b, c; } S24;

long c_sum_s24(S24 s) {
    return s.a + s.b + s.c;
}

S24 c_make_s24(long base) {
    S24 s = { base, base + 1, base + 2 };
    return s;
}
