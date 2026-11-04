// expect: 10
typedef struct { int a, b; } P;

P make(int a, int b) {
    P p = { a, b };
    return p;
}

int take(P a, P b) {
    return a.a + a.b + b.a + b.b;
}

int main(void) {
    return take(make(1, 2), make(3, 4));
}
