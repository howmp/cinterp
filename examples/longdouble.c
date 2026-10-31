long double addl(long double a, long double b) {
    return a + b;
}

int main(void) {
    long double x = 1.5L;
    long double y = 2.5L;
    long double z = addl(x, y) * 2.0L;
    if (z > 7.0L) {
        return (int)z;
    }
    return 0;
}
