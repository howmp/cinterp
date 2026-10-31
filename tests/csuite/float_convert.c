// expect: 42
int main(void) {
    volatile double x = 3.9;
    volatile float f = 3000000000.0f;
    unsigned int u = (unsigned int)x;
    double d = (double)4000000000u;
    return (u == 3u && d == 4000000000.0 && f > 2.0e9f) ? 42 : 1;
}
