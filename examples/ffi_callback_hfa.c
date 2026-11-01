typedef struct { float a, b, c, d; } F4;
typedef struct { double a, b; } D2;

F4 c_invoke_f4(F4 (*cb)(F4), F4 x);
double c_invoke_d2(D2 (*cb)(D2), D2 x);
long double c_invoke_ld(long double (*cb)(long double), long double x);

static F4 cb_f4(F4 x) {
    F4 y = { x.a + 1, x.b + 1, x.c + 1, x.d + 1 };
    return y;
}
static D2 cb_d2(D2 x) {
    D2 y = { x.a + 1, x.b + 2 };
    return y;
}
static long double cb_ld(long double x) { return x + 1.5L; }

int main(void) {
    F4 a = { 1, 2, 3, 4 };
    D2 b = { 3, 4 };
    F4 r = c_invoke_f4(cb_f4, a);
    double s = c_invoke_d2(cb_d2, b);
    long double t = c_invoke_ld(cb_ld, 2.0L);
    int sum = (int)(r.a + r.b + r.c + r.d);
    return (int)(sum * 10 + (s * 10) + (t * 2));
}
