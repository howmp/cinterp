typedef struct { long a, b, c; } S24;

long c_sum_s24(S24 s);
S24 c_make_s24(long base);

int main(void) {
    S24 s = { 1, 2, 3 };
    S24 t = c_make_s24(10);
    return (int)(c_sum_s24(s) + t.a + t.c);
}
