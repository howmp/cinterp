typedef struct { int a, b; } S8;

long c_invoke6(long (*cb)(long, long, long, long, long, long),
               long a, long b, long c, long d, long e, long f);
S8 c_invoke_s8(S8 (*cb)(S8), S8 s);

long cb6(long a, long b, long c, long d, long e, long f) {
    return a + b + c + d + e + f;
}

S8 cb_s8(S8 x) {
    S8 y = { x.a + 1, x.b + 2 };
    return y;
}

int main(void) {
    S8 s = { 3, 4 };
    S8 r = c_invoke_s8(cb_s8, s);
    return (int)(c_invoke6(cb6, 1, 2, 3, 4, 5, 6) * 10 + r.a * 10 + r.b);
}
