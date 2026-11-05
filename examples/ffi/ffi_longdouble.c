long double c_addl(long double a, long double b);
long double c_scale(long double x);
int main(void) {
    long double x = 1.0L;
    long double y = 2.0L;
    long double z = c_addl(x, y);
    long double w = c_scale(z);
    return (int)(w * 10.0L);
}
