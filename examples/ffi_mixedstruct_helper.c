typedef struct { long a; double b; } M;

M c_make_m(long a, double b) {
    M m = { a, b };
    return m;
}

double c_take_m(M m) {
    return (double)m.a + m.b;
}
