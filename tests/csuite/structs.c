// expect: 47
typedef struct { int a, b; } P;
typedef union { int i; char c[4]; } U;
P add(P x, P y) { P r = { x.a + y.a, x.b + y.b }; return r; }
int main(void) {
    P p = { 1, 2 }, q = { 3, 4 };
    P r = add(p, q);
    U u;
    u.i = 0x01020304;
    return r.a * 10 + r.b + (u.c[0] == 4 ? 1 : 0);
}
