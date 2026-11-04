long double c_addl(long double a, long double b);
long double c_scale(long double x);

int main(void) {
    return (int)(c_addl(1.0L, 2.0L) * c_scale(2.5L));
}
