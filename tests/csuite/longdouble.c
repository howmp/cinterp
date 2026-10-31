// expect: 7
long double scale(long double x) { return x * 3.0L; }
int main(void) {
    long double x = 2.5L;
    return (int)scale(x);
}
