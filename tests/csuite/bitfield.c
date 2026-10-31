// expect: 57
struct B { unsigned a : 3; unsigned b : 5; };
int main(void) {
    struct B x = { 0 };
    x.a = 5;
    x.b = 7;
    return (int)(x.a * 10 + x.b);
}
