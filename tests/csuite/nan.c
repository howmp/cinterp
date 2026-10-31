// expect: 42
int main(void) {
    volatile double zero = 0.0;
    double n = zero / zero;
    return (n != n && !(n == n) && (n < 1.0) == 0) ? 42 : 1;
}
