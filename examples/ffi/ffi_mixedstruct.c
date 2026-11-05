typedef struct { long a; double b; } M;

M c_make_m(long a, double b);
double c_take_m(M m);

int main(void) {
    M m = c_make_m(3, 4.5);
    return (int)c_take_m(m) + (int)m.b;
}
