typedef struct { int a, b; } S8;
typedef struct { double a, b; } D16;

long c_take_s8(S8 s) {
    return (long)s.a * 10 + s.b;
}

S8 c_make_s8(int a, int b) {
    S8 s = { a, b };
    return s;
}

double c_take_d16(D16 s) {
    return s.a + s.b;
}

D16 c_make_d16(double a, double b) {
    D16 s = { a, b };
    return s;
}
