typedef struct { double a, b, c, d; } D4;
double c_hfa4(D4 s);
D4 c_hfa4_ret(void);
int main(void) {
    D4 d = c_hfa4_ret();
    return (int)(c_hfa4(d) * 10.0);
}
