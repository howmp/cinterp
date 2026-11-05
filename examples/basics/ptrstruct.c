typedef struct { int *p; int x; } S;

int main(void) {
    int v = 7;
    S s = { &v, 3 };
    return *s.p + s.x;
}
