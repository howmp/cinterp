// expect: 1
int main(void) {
    long double a = 1.0L;
    long double b = a + 0x1p-63L;
    return (int)((b - a) * 0x1p63L);
}
