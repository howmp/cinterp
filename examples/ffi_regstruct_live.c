typedef struct { double a, b; } D16;

D16 c_make_d16(double a, double b);
double c_sum_d16(D16 a, D16 b);

int main(void) {
    return (int)c_sum_d16(c_make_d16(1.0, 2.0), c_make_d16(3.0, 4.0));
}
