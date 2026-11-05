long c_mix10(long a, double b, long c, double d, long e,
             double f, long g, double h, long i, double j);
int printf(const char *fmt, ...);
int main(void) {
    long r = c_mix10(1, 2.0, 3, 4.0, 5, 6.0, 7, 8.0, 9, 10.0);
    printf("%d %d %d %d %d %.1f %.1f %.1f\n", 1, 2, 3, 4, 5, 1.5, 2.5, 3.5);
    return (int)r;
}
